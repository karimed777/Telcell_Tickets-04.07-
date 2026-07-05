using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using TelcellTickets.Api.Data;
using TelcellTickets.Api.Dtos;
using TelcellTickets.Api.Models;
using TelcellTickets.Api.Services;

var builder = WebApplication.CreateBuilder(args);

// ─── Postgres через EF Core ──────────────────────────────────────────
var cs = builder.Configuration.GetConnectionString("Postgres")
         ?? "Host=localhost;Port=5432;Database=telcell_tickets;Username=postgres;Password=postgres";
builder.Services.AddDbContext<AppDbContext>(o => o.UseNpgsql(cs));

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// CORS — чтобы Flutter web (Chrome) мог ходить на API
builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
    p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

// ─── Схемы залов: WebSocket-хаб, логика резерваций, фоновая очистка ──────
builder.Services.AddSingleton<SeatHub>();
builder.Services.AddScoped<SeatReservationService>();
builder.Services.AddHostedService<ReservationCleanupService>();

var app = builder.Build();

// Применяем миграции + seed при старте
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
    DbSeeder.Seed(db);
}

app.UseSwagger();
app.UseSwaggerUI();
app.UseCors();

// ─── Веб-админка: статика из wwwroot/admin, WebSocket ───────────────────
app.UseWebSockets();
app.UseDefaultFiles();   // /admin/ -> /admin/index.html
app.UseStaticFiles();
// /admin без слэша -> редирект на index
app.MapGet("/admin", () => Results.Redirect("/admin/index.html"));

// ─── Маппинг в DTO ───────────────────────────────────────────────────
// Refund Guarantee пока не хранится в БД отдельной колонкой: выводим его
// из события (рекомендованные/featured события возвратны). Так появляется
// кнопка «Запросить возврат» без миграции схемы.
static bool RefundAllowed(Event e) => e.IsFeatured;
const int RefundUntilHoursDefault = 48;

static EventDto ToDto(Event e) => new(
    e.Id, e.Title, e.TitleAm, e.Description, e.DescriptionAm, e.Category.ToString(), e.StartsAt,
    e.CoverColorHex, e.CoverImageUrl, e.IsFeatured,
    new VenueDto(e.Venue!.Id, e.Venue.Name, e.Venue.NameAm, e.Venue.City, e.Venue.Address, e.Venue.AddressAm,
        e.Venue.Latitude, e.Venue.Longitude),
    e.TicketTypes.Select(t => new TicketTypeDto(t.Id, t.Name, t.NameAm, t.Price, t.Currency, t.Quantity - t.Sold)),
    e.TicketTypes.Count == 0 ? 0 : e.TicketTypes.Min(t => t.Price),
    RefundAllowed(e), RefundUntilHoursDefault,
    e.Status.ToString(), e.NewStartsAt, e.DecisionDeadline);

static TicketDto TicketToDto(Ticket t) => new(
    t.Id, t.EventId, t.Event!.Title, t.Event.StartsAt, t.Event.Venue!.Name,
    // Снимок названия/цены (для мест TicketType == null); fallback на тип билета.
    !string.IsNullOrEmpty(t.TypeName) ? t.TypeName : (t.TicketType?.Name ?? ""),
    t.Price != 0 ? t.Price : (t.TicketType?.Price ?? 0),
    t.TicketType?.Currency ?? "AMD",
    t.QrToken, t.Status.ToString(), t.IssuedAt, t.TransferredTo,
    RefundAllowed(t.Event), RefundUntilHoursDefault,
    t.Event.Status.ToString(), t.Event.NewStartsAt, t.Event.DecisionDeadline);

// ─── СОБЫТИЯ: список с поиском/фильтрами (как в Яндекс Афише) ─────────
// GET /api/events?category=Concert&q=rock&city=Yerevan&from=2026-07-01&featured=true
app.MapGet("/api/events", async (AppDbContext db,
    string? category, string? q, string? city, DateTimeOffset? from, DateTimeOffset? to, bool? featured) =>
{
    var query = db.Events
        .Include(e => e.Venue)
        .Include(e => e.TicketTypes)
        .AsQueryable();

    if (!string.IsNullOrWhiteSpace(category) &&
        Enum.TryParse<EventCategory>(category, true, out var cat))
        query = query.Where(e => e.Category == cat);

    if (!string.IsNullOrWhiteSpace(q))
    {
        var term = q.Trim().ToLower();
        query = query.Where(e =>
            e.Title.ToLower().Contains(term) ||
            e.Description.ToLower().Contains(term) ||
            e.Venue!.Name.ToLower().Contains(term));
    }

    if (!string.IsNullOrWhiteSpace(city))
        query = query.Where(e => e.Venue!.City == city);

    if (from.HasValue) query = query.Where(e => e.StartsAt >= from);
    if (to.HasValue) query = query.Where(e => e.StartsAt <= to);
    if (featured == true) query = query.Where(e => e.IsFeatured);

    var list = await query.OrderBy(e => e.StartsAt).ToListAsync();
    return Results.Ok(list.Select(ToDto));
});

// GET /api/events/{id}
app.MapGet("/api/events/{id:guid}", async (AppDbContext db, Guid id) =>
{
    var e = await db.Events.Include(x => x.Venue).Include(x => x.TicketTypes)
        .FirstOrDefaultAsync(x => x.Id == id);
    return e is null ? Results.NotFound() : Results.Ok(ToDto(e));
});

// ─── КАРТА: события с координатами площадок ───────────────────────────
// GET /api/map/events
app.MapGet("/api/map/events", async (AppDbContext db) =>
{
    var list = await db.Events.Include(e => e.Venue).Include(e => e.TicketTypes)
        .OrderBy(e => e.StartsAt).ToListAsync();
    return Results.Ok(list.Select(ToDto));
});

// ─── ПОКУПКА: mock-оплата → заказ Paid + билеты с QR (90 сек flow) ────
app.MapPost("/api/checkout", async (AppDbContext db, SeatHub hub, CheckoutRequestDto req) =>
{
    // ── Покупка по схеме зала (выбраны конкретные места) ────────────────
    if (req.SelectedSeatIds is { Count: > 0 })
    {
        if (string.IsNullOrWhiteSpace(req.SessionId))
            return Results.BadRequest(new { error = "Не указана сессия выбора мест." });

        var seats = await db.EventSeats
            .Include(s => s.EventSeatBlock)!.ThenInclude(b => b!.EventFloor)!.ThenInclude(f => f!.EventLayout)
            .Where(s => req.SelectedSeatIds.Contains(s.Id))
            .ToListAsync();

        if (seats.Count != req.SelectedSeatIds.Count)
            return Results.BadRequest(new { error = "Некоторые места не найдены." });

        var seatEventId = seats[0].EventSeatBlock!.EventFloor!.EventLayout!.EventId;

        // Все места должны держаться этой сессией и быть в статусе Reserved.
        foreach (var s in seats)
        {
            if (s.Status != SeatStatus.Reserved)
                return Results.BadRequest(new { error = $"Место Ряд {s.Row} Место {s.Number} недоступно." });
            var held = await db.SeatReservations
                .AnyAsync(r => r.EventSeatId == s.Id && r.SessionId == req.SessionId);
            if (!held)
                return Results.BadRequest(new { error = $"Место Ряд {s.Row} Место {s.Number} не зарезервировано вами." });
        }

        var seatUser = await db.Users.FirstOrDefaultAsync(u => u.Phone == req.BuyerPhone);
        if (seatUser is null)
        {
            seatUser = new AppUser { Id = Guid.NewGuid(), DisplayName = req.BuyerName, Phone = req.BuyerPhone };
            db.Users.Add(seatUser);
        }

        var seatOrder = new Order { Id = Guid.NewGuid(), UserId = seatUser.Id, Status = OrderStatus.Pending };
        var seatTickets = new List<Ticket>();
        decimal seatTotal = 0;

        foreach (var s in seats)
        {
            s.Status = SeatStatus.Sold;
            s.OrderId = seatOrder.Id;
            seatTotal += s.Price;
            seatTickets.Add(new Ticket
            {
                Id = Guid.NewGuid(), OrderId = seatOrder.Id,
                EventId = seatEventId, EventSeatId = s.Id, Status = TicketStatus.Issued,
                TypeName = $"{s.SeatType} · Ряд {s.Row} Место {s.Number}", Price = s.Price
            });
        }

        // Резервы больше не нужны — места проданы.
        var toDrop = await db.SeatReservations
            .Where(r => req.SelectedSeatIds.Contains(r.EventSeatId)).ToListAsync();
        db.SeatReservations.RemoveRange(toDrop);

        seatOrder.Total = seatTotal;
        seatOrder.Status = OrderStatus.Paid;
        seatOrder.PaidAt = DateTimeOffset.UtcNow;
        db.Orders.Add(seatOrder);
        db.Tickets.AddRange(seatTickets);
        await db.SaveChangesAsync();

        // Разослать всем подключённым, что места проданы.
        foreach (var s in seats)
            await hub.BroadcastAsync(seatEventId, new { type = "seat_sold", seatId = s.Id });

        foreach (var t in seatTickets)
            t.Event = await db.Events.Include(e => e.Venue).FirstAsync(e => e.Id == t.EventId);

        return Results.Ok(new OrderResultDto(seatOrder.Id, seatOrder.Status.ToString(),
            seatOrder.Total, seatOrder.Currency, seatTickets.Select(TicketToDto)));
    }

    if (req.Items is null || !req.Items.Any())
        return Results.BadRequest(new { error = "Корзина пуста." });

    // Пользователь по телефону (создаём при первой покупке)
    var user = await db.Users.FirstOrDefaultAsync(u => u.Phone == req.BuyerPhone);
    if (user is null)
    {
        user = new AppUser { Id = Guid.NewGuid(), DisplayName = req.BuyerName, Phone = req.BuyerPhone };
        db.Users.Add(user);
    }

    var order = new Order { Id = Guid.NewGuid(), UserId = user.Id, Status = OrderStatus.Pending };
    decimal total = 0;
    var tickets = new List<Ticket>();

    foreach (var item in req.Items)
    {
        var tt = await db.TicketTypes.Include(t => t.Event)!.ThenInclude(e => e!.Venue)
            .FirstOrDefaultAsync(t => t.Id == item.TicketTypeId);
        if (tt is null)
            return Results.BadRequest(new { error = $"Тип билета {item.TicketTypeId} не найден." });
        if (item.Quantity <= 0)
            return Results.BadRequest(new { error = "Количество должно быть больше нуля." });
        if (tt.Quantity - tt.Sold < item.Quantity)
            return Results.BadRequest(new { error = $"Недостаточно билетов: {tt.Name}." });

        for (var i = 0; i < item.Quantity; i++)
        {
            tickets.Add(new Ticket
            {
                Id = Guid.NewGuid(), OrderId = order.Id, TicketTypeId = tt.Id,
                EventId = tt.EventId, Status = TicketStatus.Issued,
                TypeName = tt.Name, Price = tt.Price
            });
        }
        tt.Sold += item.Quantity;
        total += tt.Price * item.Quantity;
    }

    // mock-оплата: считаем успешной мгновенно
    order.Total = total;
    order.Status = OrderStatus.Paid;
    order.PaidAt = DateTimeOffset.UtcNow;

    db.Orders.Add(order);
    db.Tickets.AddRange(tickets);
    await db.SaveChangesAsync();

    // Подгружаем навигационные свойства для DTO
    foreach (var t in tickets)
    {
        t.Event = await db.Events.Include(e => e.Venue).FirstAsync(e => e.Id == t.EventId);
        t.TicketType = await db.TicketTypes.FirstAsync(x => x.Id == t.TicketTypeId);
    }

    return Results.Ok(new OrderResultDto(order.Id, order.Status.ToString(),
        order.Total, order.Currency, tickets.Select(TicketToDto)));
});

// ─── МОИ БИЛЕТЫ ──────────────────────────────────────────────────────
// GET /api/users/{phone}/tickets
app.MapGet("/api/users/{phone}/tickets", async (AppDbContext db, string phone) =>
{
    var tickets = await db.Tickets
        .Include(t => t.Event).ThenInclude(e => e!.Venue)
        .Include(t => t.TicketType)
        .Include(t => t.Order)
        .Where(t => t.Order!.User!.Phone == phone)
        .OrderByDescending(t => t.IssuedAt)
        .ToListAsync();
    return Results.Ok(tickets.Select(TicketToDto));
});

// ─── CHECK-IN: скан QR на входе («1 сек на скан») ────────────────────
app.MapPost("/api/checkin", async (AppDbContext db, CheckInRequestDto req) =>
{
    var t = await db.Tickets
        .Include(x => x.Event).ThenInclude(e => e!.Venue)
        .Include(x => x.TicketType)
        .FirstOrDefaultAsync(x => x.QrToken == req.QrToken);

    if (t is null) return Results.NotFound(new { error = "Билет не найден." });
    if (t.Status == TicketStatus.CheckedIn)
        return Results.Conflict(new { error = "Билет уже использован.", checkedInAt = t.CheckedInAt });
    // Валидны: обычный билет и билет с подтверждённым переносом.
    if (t.Status != TicketStatus.Issued && t.Status != TicketStatus.RescheduledConfirmed)
        return Results.BadRequest(new { error = $"Билет недействителен ({t.Status})." });

    t.Status = TicketStatus.CheckedIn;
    t.CheckedInAt = DateTimeOffset.UtcNow;
    await db.SaveChangesAsync();
    return Results.Ok(new { ok = true, ticket = TicketToDto(t) });
});

// ─── ПЕРЕДАЧА БИЛЕТА: POST /api/tickets/{id}/transfer (PRD §5.5, US-03) ─
// Передаёт билет другому пользователю по контакту (email/телефон):
//  • проверяет существование билета;
//  • запрещает передачу использованных / уже переданных / недействительных;
//  • переводит билет в статус Transferred, аннулируя оригинальный QR;
//  • выдаёт новый QR-токен (билет остаётся валиден у получателя);
//  • возвращает обновлённый билет в форме TicketDto, ожидаемой Flutter.
app.MapPost("/api/tickets/{id:guid}/transfer", async (AppDbContext db, Guid id, TransferRequestDto req) =>
{
    if (string.IsNullOrWhiteSpace(req.ToContact))
        return Results.BadRequest(new { error = "Укажите контакт получателя (email или телефон)." });

    var t = await db.Tickets
        .Include(x => x.Event).ThenInclude(e => e!.Venue)
        .Include(x => x.TicketType)
        .FirstOrDefaultAsync(x => x.Id == id);

    if (t is null)
        return Results.NotFound(new { error = "Билет не найден." });
    if (t.Status == TicketStatus.CheckedIn)
        return Results.Conflict(new { error = "Билет уже использован — передача невозможна." });
    if (t.Status == TicketStatus.Transferred)
        return Results.Conflict(new { error = "Билет уже передан другому пользователю.", transferredTo = t.TransferredTo });
    if (t.Status != TicketStatus.Issued)
        return Results.BadRequest(new { error = $"Билет недействителен ({t.Status})." });

    // Аннулируем оригинальный QR и выдаём новый — старый код перестаёт работать.
    t.Status = TicketStatus.Transferred;
    t.TransferredTo = req.ToContact.Trim();
    t.TransferredAt = DateTimeOffset.UtcNow;
    t.QrToken = Guid.NewGuid().ToString("N");
    await db.SaveChangesAsync();

    return Results.Ok(TicketToDto(t));
});

// ─── ВОЗВРАТ БИЛЕТА: POST /api/tickets/{id}/request-refund (PRD §8, Сценарий В) ─
// Возврат по инициативе покупателя для билета с Refund Guarantee.
// Переводит билет в статус Refunded и аннулирует QR.
app.MapPost("/api/tickets/{id:guid}/request-refund", async (AppDbContext db, Guid id) =>
{
    var t = await db.Tickets
        .Include(x => x.Event).ThenInclude(e => e!.Venue)
        .Include(x => x.TicketType)
        .FirstOrDefaultAsync(x => x.Id == id);

    if (t is null)
        return Results.NotFound(new { error = "Билет не найден." });
    if (t.Status == TicketStatus.CheckedIn)
        return Results.Conflict(new { error = "Билет уже использован — возврат невозможен." });
    if (t.Status == TicketStatus.Refunded)
        return Results.Conflict(new { error = "Билет уже возвращён." });
    if (t.Status != TicketStatus.Issued)
        return Results.BadRequest(new { error = $"Возврат недоступен ({t.Status})." });
    if (!RefundAllowed(t.Event!))
        return Results.BadRequest(new { error = "Для этого билета возврат не предусмотрен." });

    t.Status = TicketStatus.Refunded;
    await db.SaveChangesAsync();
    return Results.Ok(TicketToDto(t));
});

// ─── ОТМЕНА / ПЕРЕНОС СОБЫТИЯ (админ) ────────────────────────────────
// POST /api/admin/events/{id}/cancel — событие отменено: все активные
// билеты переводятся в EventCancelled (авто-возврат средств, QR аннулирован).
app.MapPost("/api/admin/events/{id:guid}/cancel", async (AppDbContext db, Guid id) =>
{
    var e = await db.Events.FirstOrDefaultAsync(x => x.Id == id);
    if (e is null) return Results.NotFound(new { error = "Событие не найдено." });
    if (e.Status == EventStatus.Cancelled)
        return Results.Conflict(new { error = "Событие уже отменено." });

    e.Status = EventStatus.Cancelled;
    e.NewStartsAt = null;
    e.DecisionDeadline = null;

    var tickets = await db.Tickets
        .Where(t => t.EventId == id &&
            (t.Status == TicketStatus.Issued ||
             t.Status == TicketStatus.RescheduledPending ||
             t.Status == TicketStatus.RescheduledConfirmed))
        .ToListAsync();
    foreach (var t in tickets)
        t.Status = TicketStatus.EventCancelled;

    await db.SaveChangesAsync();
    return Results.Ok(new { status = "Cancelled", refundedTickets = tickets.Count });
});

/// Запрос переноса: новая дата обязательна; дедлайн решения по умолчанию +72ч.
app.MapPost("/api/admin/events/{id:guid}/reschedule", async (AppDbContext db, Guid id, RescheduleRequestDto req) =>
{
    var e = await db.Events.FirstOrDefaultAsync(x => x.Id == id);
    if (e is null) return Results.NotFound(new { error = "Событие не найдено." });
    if (e.Status == EventStatus.Cancelled)
        return Results.Conflict(new { error = "Событие отменено — перенос невозможен." });
    if (req.NewStartsAt <= DateTimeOffset.UtcNow)
        return Results.BadRequest(new { error = "Новая дата должна быть в будущем." });

    e.Status = EventStatus.Rescheduled;
    e.NewStartsAt = req.NewStartsAt;
    e.DecisionDeadline = req.DecisionDeadline ?? DateTimeOffset.UtcNow.AddHours(72);

    var tickets = await db.Tickets
        .Where(t => t.EventId == id && t.Status == TicketStatus.Issued)
        .ToListAsync();
    foreach (var t in tickets)
        t.Status = TicketStatus.RescheduledPending;

    await db.SaveChangesAsync();
    return Results.Ok(new { status = "Rescheduled", newStartsAt = e.NewStartsAt, decisionDeadline = e.DecisionDeadline, pendingTickets = tickets.Count });
});

// ─── РЕШЕНИЕ ПОКУПАТЕЛЯ по перенесённому событию ─────────────────────
// POST /api/tickets/{id}/reschedule/confirm — иду на новую дату (QR остаётся).
app.MapPost("/api/tickets/{id:guid}/reschedule/confirm", async (AppDbContext db, Guid id) =>
{
    var t = await db.Tickets
        .Include(x => x.Event).ThenInclude(e => e!.Venue)
        .Include(x => x.TicketType)
        .FirstOrDefaultAsync(x => x.Id == id);
    if (t is null) return Results.NotFound(new { error = "Билет не найден." });
    if (t.Status != TicketStatus.RescheduledPending)
        return Results.BadRequest(new { error = $"Подтверждение недоступно ({t.Status})." });

    t.Status = TicketStatus.RescheduledConfirmed;
    await db.SaveChangesAsync();
    return Results.Ok(TicketToDto(t));
});

// POST /api/tickets/{id}/reschedule/refund — не иду: возврат средств, QR аннулирован.
app.MapPost("/api/tickets/{id:guid}/reschedule/refund", async (AppDbContext db, Guid id) =>
{
    var t = await db.Tickets
        .Include(x => x.Event).ThenInclude(e => e!.Venue)
        .Include(x => x.TicketType)
        .FirstOrDefaultAsync(x => x.Id == id);
    if (t is null) return Results.NotFound(new { error = "Билет не найден." });
    if (t.Status != TicketStatus.RescheduledPending)
        return Results.BadRequest(new { error = $"Возврат недоступен ({t.Status})." });

    t.Status = TicketStatus.Refunded;
    await db.SaveChangesAsync();
    return Results.Ok(TicketToDto(t));
});

// ─── ПОИСК ПОЛУЧАТЕЛЯ: GET /api/users/lookup?contact=... ────────────
// Моментальный поиск перед передачей билета: по телефону или email
// возвращает имя получателя. 200 + Found=true, если пользователь
// есть; 404, если нет (фронт покажет «пользователь не найден»).
app.MapGet("/api/users/lookup", async (AppDbContext db, string? contact) =>
{
    var raw = (contact ?? "").Trim();
    if (raw.Length < 3)
        return Results.BadRequest(new { error = "Укажите телефон или email получателя." });

    AppUser? user;
    if (raw.Contains('@'))
    {
        var email = raw.ToLower();
        user = await db.Users.FirstOrDefaultAsync(u => u.Email != null && u.Email.ToLower() == email);
    }
    else
    {
        var phone = NormalizePhone(raw);
        user = await db.Users.FirstOrDefaultAsync(u => u.Phone == phone);
    }

    if (user is null)
        return Results.NotFound(new RecipientLookupDto(false, null, raw));
    return Results.Ok(new RecipientLookupDto(true, user.DisplayName, raw));
});

// ─── ПЛОЩАДКИ (для веб-админки: выбор площадки при создании шаблона) ───
app.MapGet("/api/venues", async (AppDbContext db) =>
{
    var list = await db.Venues.OrderBy(v => v.Name).ToListAsync();
    return Results.Ok(list.Select(v => new VenueDto(
        v.Id, v.Name, v.NameAm, v.City, v.Address, v.AddressAm, v.Latitude, v.Longitude)));
});

// ══════════════════════════════════════════════════════════════════════════
//  СХЕМЫ ЗАЛОВ — ШАБЛОНЫ (VenueLayout) для веб-админки
// ══════════════════════════════════════════════════════════════════════════

// Полная загрузка графа шаблона
static IQueryable<VenueLayout> LayoutQuery(AppDbContext db) => db.VenueLayouts
    .Include(l => l.Venue)
    .Include(l => l.Floors).ThenInclude(f => f.Stage)
    .Include(l => l.Floors).ThenInclude(f => f.SeatBlocks).ThenInclude(b => b.Seats);

// GET список шаблонов (поиск по названию, фильтр по площадке)
app.MapGet("/api/venue-layouts", async (AppDbContext db, string? search, Guid? venueId) =>
{
    var q = db.VenueLayouts.Include(l => l.Venue)
        .Include(l => l.Floors).ThenInclude(f => f.SeatBlocks).ThenInclude(b => b.Seats)
        .AsQueryable();

    if (!string.IsNullOrWhiteSpace(search))
    {
        var term = search.Trim().ToLower();
        q = q.Where(l => l.Name.ToLower().Contains(term));
    }
    if (venueId.HasValue) q = q.Where(l => l.VenueId == venueId);

    var list = await q.OrderByDescending(l => l.CreatedAt).ToListAsync();
    return Results.Ok(list.Select(l => new VenueLayoutSummaryDto(
        l.Id, l.VenueId, l.Venue?.Name ?? "", l.Name, l.CreatedAt,
        l.Floors.Count,
        l.Floors.SelectMany(f => f.SeatBlocks).SelectMany(b => b.Seats).Count(s => s.IsActive))));
});

// GET полная схема шаблона
app.MapGet("/api/venue-layouts/{id:guid}", async (AppDbContext db, Guid id) =>
{
    var l = await LayoutQuery(db).FirstOrDefaultAsync(x => x.Id == id);
    return l is null ? Results.NotFound() : Results.Ok(SeatingMapper.ToDto(l));
});

// POST создать шаблон
app.MapPost("/api/venue-layouts", async (AppDbContext db, SaveVenueLayoutDto dto) =>
{
    if (string.IsNullOrWhiteSpace(dto.Name))
        return Results.BadRequest(new { error = "Укажите название шаблона." });
    if (!await db.Venues.AnyAsync(v => v.Id == dto.VenueId))
        return Results.BadRequest(new { error = "Площадка не найдена." });

    var layout = new VenueLayout
    {
        Id = Guid.NewGuid(),
        VenueId = dto.VenueId,
        Name = dto.Name.Trim(),
        CreatedAt = DateTimeOffset.UtcNow,
        Floors = SeatingMapper.BuildFloors(dto.Floors ?? new())
    };
    db.VenueLayouts.Add(layout);
    await db.SaveChangesAsync();

    var saved = await LayoutQuery(db).FirstAsync(x => x.Id == layout.Id);
    return Results.Created($"/api/venue-layouts/{layout.Id}", SeatingMapper.ToDto(saved));
});

// PUT обновить шаблон (перестраиваем этажи целиком)
app.MapPut("/api/venue-layouts/{id:guid}", async (AppDbContext db, Guid id, SaveVenueLayoutDto dto) =>
{
    var layout = await db.VenueLayouts.Include(l => l.Floors)
        .FirstOrDefaultAsync(l => l.Id == id);
    if (layout is null) return Results.NotFound();

    layout.Name = dto.Name.Trim();
    if (dto.VenueId != Guid.Empty) layout.VenueId = dto.VenueId;

    db.VenueFloors.RemoveRange(layout.Floors); // каскад снесёт блоки/места/сцены
    layout.Floors = SeatingMapper.BuildFloors(dto.Floors ?? new());
    await db.SaveChangesAsync();

    var saved = await LayoutQuery(db).FirstAsync(x => x.Id == id);
    return Results.Ok(SeatingMapper.ToDto(saved));
});

// DELETE шаблон (если не используется в мероприятиях)
app.MapDelete("/api/venue-layouts/{id:guid}", async (AppDbContext db, Guid id) =>
{
    var layout = await db.VenueLayouts.FirstOrDefaultAsync(l => l.Id == id);
    if (layout is null) return Results.NotFound();
    if (await db.EventLayouts.AnyAsync(e => e.VenueLayoutId == id))
        return Results.Conflict(new { error = "Шаблон используется в мероприятиях, удаление запрещено." });

    db.VenueLayouts.Remove(layout);
    await db.SaveChangesAsync();
    return Results.NoContent();
});

// ════════════════════════════════════════════���═════════════════════════════
//  СХЕМА МЕРОПРИЯТИЯ (EventLayout)
// ══════════════════════════════════════════════════════════════════════════

static IQueryable<EventLayout> EventLayoutQuery(AppDbContext db) => db.EventLayouts
    .Include(l => l.Floors).ThenInclude(f => f.Stage)
    .Include(l => l.Floors).ThenInclude(f => f.SeatBlocks).ThenInclude(b => b.Seats);

// GET схема мероприятия (с реалтайм-статусами)
app.MapGet("/api/events/{eventId:guid}/layout", async (AppDbContext db, Guid eventId) =>
{
    var l = await EventLayoutQuery(db).FirstOrDefaultAsync(x => x.EventId == eventId);
    return l is null ? Results.NotFound() : Results.Ok(SeatingMapper.ToDto(l));
});

// POST создать/привязать схему к мероприятию
app.MapPost("/api/events/{eventId:guid}/layout", async (AppDbContext db, Guid eventId, CreateEventLayoutDto dto) =>
{
    if (!await db.Events.AnyAsync(e => e.Id == eventId))
        return Results.NotFound(new { error = "Мероприятие не найдено." });

    // Заменяем существующую схему, если была (удаляем отдельным SaveChanges,
    // чтобы не нарушить уникальный индекс по EventId при вставке новой).
    var existing = await db.EventLayouts.FirstOrDefaultAsync(l => l.EventId == eventId);
    if (existing is not null)
    {
        db.EventLayouts.Remove(existing);
        await db.SaveChangesAsync();
    }

    EventLayout layout;
    if (dto.VenueLayoutId is Guid tplId)
    {
        var tpl = await LayoutQuery(db).FirstOrDefaultAsync(x => x.Id == tplId);
        if (tpl is null) return Results.BadRequest(new { error = "Шаблон не найден." });
        layout = SeatingMapper.CopyToEvent(tpl, eventId, dto.HasSeatingPlan);
    }
    else
    {
        layout = SeatingMapper.BuildEventLayout(eventId, dto.HasSeatingPlan, dto.Floors);
    }

    db.EventLayouts.Add(layout);
    await db.SaveChangesAsync();

    var saved = await EventLayoutQuery(db).FirstAsync(x => x.Id == layout.Id);
    return Results.Ok(SeatingMapper.ToDto(saved));
});

// PUT редактировать схему конкретного мероприятия
app.MapPut("/api/events/{eventId:guid}/layout", async (AppDbContext db, Guid eventId, CreateEventLayoutDto dto) =>
{
    var layout = await db.EventLayouts.Include(l => l.Floors)
        .FirstOrDefaultAsync(l => l.EventId == eventId);
    if (layout is null) return Results.NotFound();

    layout.HasSeatingPlan = dto.HasSeatingPlan;
    db.EventFloors.RemoveRange(layout.Floors);

    var rebuilt = SeatingMapper.BuildEventLayout(eventId, dto.HasSeatingPlan, dto.Floors);
    layout.Floors = rebuilt.Floors;
    await db.SaveChangesAsync();

    var saved = await EventLayoutQuery(db).FirstAsync(x => x.Id == layout.Id);
    return Results.Ok(SeatingMapper.ToDto(saved));
});

// GET места этажа со статусами
app.MapGet("/api/events/{eventId:guid}/layout/floors/{floorId:guid}/seats", async (AppDbContext db, Guid eventId, Guid floorId) =>
{
    var floor = await db.EventFloors
        .Include(f => f.EventLayout)
        .Include(f => f.SeatBlocks).ThenInclude(b => b.Seats)
        .FirstOrDefaultAsync(f => f.Id == floorId);
    if (floor is null || floor.EventLayout!.EventId != eventId) return Results.NotFound();

    var seats = floor.SeatBlocks.SelectMany(b => b.Seats).Where(s => s.IsActive)
        .Select(s => new EventSeatDto(
            s.Id, s.Row, s.Number, s.SeatType.ToString(), s.Price, s.Description, s.Color,
            s.CanvasX, s.CanvasY, s.IsActive, s.Status.ToString()));
    return Results.Ok(seats);
});

// ══════════════════════════════════════════════════════════════════════════
//  WEBSOCKET — /ws/events/{eventId}/seats
//  ?sessionId=...  — сессия выбора (генерируется, если не передана)
//  ?token=...      — токен сессии вошедшего пользователя (для ReservedByUserId)
// ══════════════════════════════════════════════════════════════════════════
app.Map("/ws/events/{eventId:guid}/seats", async (HttpContext ctx, Guid eventId,
    SeatHub hub, IServiceScopeFactory scopes) =>
{
    if (!ctx.WebSockets.IsWebSocketRequest)
    {
        ctx.Response.StatusCode = StatusCodes.Status400BadRequest;
        return;
    }

    // Сессия покупателя. Клиент может прислать свою (переподключение сохраняет выбор).
    var sessionId = ctx.Request.Query["sessionId"].ToString();
    if (string.IsNullOrWhiteSpace(sessionId)) sessionId = Guid.NewGuid().ToString("N");

    // Если передан токен вошедшего пользователя — резервы пишутся с его userId.
    Guid? wsUserId = null;
    var wsToken = ctx.Request.Query["token"].ToString();
    if (!string.IsNullOrWhiteSpace(wsToken))
    {
        using var authScope = scopes.CreateScope();
        var authDb = authScope.ServiceProvider.GetRequiredService<AppDbContext>();
        var wsUser = await authDb.Users.FirstOrDefaultAsync(u => u.SessionToken == wsToken);
        wsUserId = wsUser?.Id;
    }

    var socket = await ctx.WebSockets.AcceptWebSocketAsync();
    var connId = Guid.NewGuid().ToString("N");
    hub.Add(new SeatHub.Connection
    {
        ConnectionId = connId, Socket = socket, SessionId = sessionId, EventId = eventId
    });

    await SeatHub.SendAsync(socket, new { type = "connected", sessionId });

    var buffer = new byte[8 * 1024];
    try
    {
        while (socket.State == WebSocketState.Open)
        {
            var result = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None);
            if (result.MessageType == WebSocketMessageType.Close) break;
            if (result.Count == 0) continue;

            var text = Encoding.UTF8.GetString(buffer, 0, result.Count);
            string? msgType = null;
            Guid seatId = Guid.Empty;
            try
            {
                using var doc = JsonDocument.Parse(text);
                if (doc.RootElement.TryGetProperty("type", out var tEl)) msgType = tEl.GetString();
                if (doc.RootElement.TryGetProperty("seatId", out var sEl) &&
                    Guid.TryParse(sEl.GetString(), out var g)) seatId = g;
            }
            catch { continue; }

            using var scope = scopes.CreateScope();
            var svc = scope.ServiceProvider.GetRequiredService<SeatReservationService>();

            switch (msgType)
            {
                case "reserve":
                    var res = await svc.ReserveAsync(eventId, sessionId, seatId, wsUserId);
                    if (!res.Ok)
                        await SeatHub.SendAsync(socket, new { type = "reserve_rejected", seatId, error = res.Error });
                    // при успехе seat_reserved придёт через broadcast (в т.ч. отправителю)
                    break;
                case "release":
                    if (seatId != Guid.Empty) await svc.ReleaseAsync(eventId, sessionId, seatId);
                    else await svc.ReleaseAllAsync(eventId, sessionId); // release без seatId = снять все
                    break;
                case "keepalive":
                    await svc.KeepaliveAsync(eventId, sessionId);
                    await SeatHub.SendAsync(socket, new { type = "keepalive_ok" });
                    break;
            }
        }
    }
    catch (WebSocketException) { /* соединение оборвалось */ }
    finally
    {
        hub.Remove(eventId, connId);
        if (socket.State == WebSocketState.Open)
            await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "bye", CancellationToken.None);
        // Резервы НЕ снимаем при обрыве — их подберёт 5-минутный таймер (переподключение сохраняет выбор).
    }
});

app.MapGet("/", () => "Telcell Tickets API · OK");

// ─── АВТОРИЗАЦИЯ: регистрация + вход (email/телефон + mock-OTP) ─────
const string devOtpCode = "0000";
const string adminPhone = "+37400000000";
const string adminCode = "9999";

static string NormalizePhone(string phone) => phone.Trim().Replace(" ", "").Replace("-", "");
static string NormalizeEmail(string email) => email.Trim().ToLower();
static UserDto UserToDto(AppUser u) => new(u.Id, u.DisplayName, u.Phone, u.Email, u.IsAdmin);

// POST /api/auth/register - Регистрация нового пользователя
app.MapPost("/api/auth/register", async (AppDbContext db, RegisterDto req) =>
{
    if (string.IsNullOrWhiteSpace(req.DisplayName) || req.DisplayName.Length < 2)
        return Results.BadRequest(new RegisterResultDto(false, "Укажите имя (минимум 2 символа)."));
    
    if (string.IsNullOrWhiteSpace(req.Email) || !req.Email.Contains('@'))
        return Results.BadRequest(new RegisterResultDto(false, "Укажите корректный email."));
    
    if (string.IsNullOrWhiteSpace(req.Phone) || req.Phone.Length < 6)
        return Results.BadRequest(new RegisterResultDto(false, "Укажите корректный номер телефона."));
    
    var phone = NormalizePhone(req.Phone);
    var email = NormalizeEmail(req.Email);
    
    // Проверяем что пользователь с таким телефоном или email не существует
    var existingPhone = await db.Users.FirstOrDefaultAsync(u => u.Phone == phone);
    if (existingPhone is not null)
        return Results.BadRequest(new RegisterResultDto(false, "Пользователь с таким телефоном уже зарегистрирован."));
    
    var existingEmail = await db.Users.FirstOrDefaultAsync(u => u.Email != null && u.Email.ToLower() == email);
    if (existingEmail is not null)
        return Results.BadRequest(new RegisterResultDto(false, "Пользователь с таким email уже зарегистрирован."));
    
    // Создаём нового пользователя с OTP кодом
    var user = new AppUser
    {
        Id = Guid.NewGuid(),
        Phone = phone,
        Email = email,
        DisplayName = req.DisplayName.Trim(),
        OtpCode = devOtpCode,
        OtpExpiresAt = DateTimeOffset.UtcNow.AddMinutes(5)
    };
    
    db.Users.Add(user);
    await db.SaveChangesAsync();
    
    return Results.Ok(new RegisterResultDto(true, null, user.OtpCode));
});

// POST /api/auth/login/request - Запрос кода для входа (email или телефон)
app.MapPost("/api/auth/login/request", async (AppDbContext db, LoginRequestDto req) =>
{
    if (string.IsNullOrWhiteSpace(req.Contact))
        return Results.BadRequest(new LoginRequestResultDto(false, "Укажите email или телефон."));
    
    var contact = req.Contact.Trim();
    AppUser? user = null;
    
    // Определяем это email или телефон
    if (contact.Contains('@'))
    {
        var email = NormalizeEmail(contact);
        user = await db.Users.FirstOrDefaultAsync(u => u.Email != null && u.Email.ToLower() == email);
    }
    else
    {
        var phone = NormalizePhone(contact);
        user = await db.Users.FirstOrDefaultAsync(u => u.Phone == phone);
    }
    
    if (user is null)
        return Results.NotFound(new LoginRequestResultDto(false, "Пользователь с таким email или телефоном не найден."));
    
    // Генерируем OTP код
    user.OtpCode = devOtpCode;
    user.OtpExpiresAt = DateTimeOffset.UtcNow.AddMinutes(5);
    await db.SaveChangesAsync();
    
    return Results.Ok(new LoginRequestResultDto(true, null, user.OtpCode));
});

// POST /api/auth/login/verify - Проверка кода и вход
app.MapPost("/api/auth/login/verify", async (AppDbContext db, VerifyCodeDto req) =>
{
    if (string.IsNullOrWhiteSpace(req.Contact))
        return Results.BadRequest(new { error = "Укажите email или телефон." });
    
    if (string.IsNullOrWhiteSpace(req.Code))
        return Results.BadRequest(new { error = "Укажите код." });
    
    var contact = req.Contact.Trim();
    AppUser? user = null;
    
    // Скрытый admin-вход
    if (contact == adminPhone && req.Code.Trim() == adminCode)
    {
        user = await db.Users.FirstOrDefaultAsync(u => u.Phone == adminPhone);
        if (user is null)
        {
            user = new AppUser
            {
                Id = Guid.NewGuid(),
                Phone = adminPhone,
                DisplayName = "Администратор",
                IsAdmin = true
            };
            db.Users.Add(user);
        }
        else
        {
            user.IsAdmin = true;
        }
        
        user.OtpCode = null;
        user.OtpExpiresAt = null;
        user.SessionToken = Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");
        await db.SaveChangesAsync();
        return Results.Ok(new AuthResultDto(user.SessionToken!, UserToDto(user)));
    }
    
    // Определяем это email или телефон
    if (contact.Contains('@'))
    {
        var email = NormalizeEmail(contact);
        user = await db.Users.FirstOrDefaultAsync(u => u.Email != null && u.Email.ToLower() == email);
    }
    else
    {
        var phone = NormalizePhone(contact);
        user = await db.Users.FirstOrDefaultAsync(u => u.Phone == phone);
    }
    
    if (user is null || user.OtpCode is null)
        return Results.NotFound(new { error = "Сначала запросите код входа." });
    
    if (user.OtpExpiresAt is null || user.OtpExpiresAt < DateTimeOffset.UtcNow)
        return Results.BadRequest(new { error = "Срок действия кода истёк. Запросите новый." });
    
    if (!string.Equals(user.OtpCode, req.Code.Trim(), StringComparison.Ordinal))
        return Results.BadRequest(new { error = "Неверный код." });
    
    // Код одноразовый: гасим его и выдаём токен сессии
    user.OtpCode = null;
    user.OtpExpiresAt = null;
    user.SessionToken = Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");
    await db.SaveChangesAsync();
    
    return Results.Ok(new AuthResultDto(user.SessionToken!, UserToDto(user)));
});

// Старые эндпоинты для совместимости
app.MapPost("/api/auth/request-otp", async (AppDbContext db, RequestOtpDto req) =>
{
    var phone = NormalizePhone(req.Phone ?? "");
    if (phone.Length < 6)
        return Results.BadRequest(new { error = "Укажите корректный номер телефона." });

    var user = await db.Users.FirstOrDefaultAsync(u => u.Phone == phone);
    if (user is null)
    {
        user = new AppUser
        {
            Id = Guid.NewGuid(),
            Phone = phone,
            DisplayName = string.IsNullOrWhiteSpace(req.DisplayName) ? "Гость" : req.DisplayName!.Trim(),
        };
        db.Users.Add(user);
    }
    else if (!string.IsNullOrWhiteSpace(req.DisplayName))
    {
        user.DisplayName = req.DisplayName!.Trim();
    }

    user.OtpCode = devOtpCode;
    user.OtpExpiresAt = DateTimeOffset.UtcNow.AddMinutes(5);
    await db.SaveChangesAsync();

    return Results.Ok(new RequestOtpResultDto(true, user.OtpCode));
});

app.MapPost("/api/auth/verify-otp", async (AppDbContext db, VerifyOtpDto req) =>
{
    var phone = NormalizePhone(req.Phone ?? "");
    const string adminPhone = "+37400000000";
    const string adminCode = "9999";
    var user = await db.Users.FirstOrDefaultAsync(u => u.Phone == phone);

    if (phone == adminPhone)
    {
        if (!string.Equals((req.Code ?? "").Trim(), adminCode, StringComparison.Ordinal))
            return Results.BadRequest(new { error = "Неверный код." });
        user ??= new AppUser { Id = Guid.NewGuid(), Phone = phone, DisplayName = "Администратор" };
        user.IsAdmin = true;
        user.OtpCode = null;
        user.OtpExpiresAt = null;
        user.SessionToken = Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");
        if (!db.Users.Local.Contains(user) && db.Entry(user).State == EntityState.Detached)
            db.Users.Add(user);
        await db.SaveChangesAsync();
        return Results.Ok(new AuthResultDto(user.SessionToken!, UserToDto(user)));
    }

    if (user is null || user.OtpCode is null)
        return Results.NotFound(new { error = "Сначала запросите код входа." });
    if (user.OtpExpiresAt is null || user.OtpExpiresAt < DateTimeOffset.UtcNow)
        return Results.BadRequest(new { error = "Срок действия кода истёк. Запросите новый." });
    if (!string.Equals(user.OtpCode, (req.Code ?? "").Trim(), StringComparison.Ordinal))
        return Results.BadRequest(new { error = "Неверный код." });

    user.OtpCode = null;
    user.OtpExpiresAt = null;
    user.SessionToken = Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");
    await db.SaveChangesAsync();

    return Results.Ok(new AuthResultDto(user.SessionToken!, UserToDto(user)));
});

// Текущий пользователь по токену (восстановление сессии при старте).
app.MapGet("/api/auth/me", async (AppDbContext db, HttpRequest http) =>
{
    var token = ExtractBearer(http);
    if (token is null) return Results.Unauthorized();
    var user = await db.Users.FirstOrDefaultAsync(u => u.SessionToken == token);
    return user is null ? Results.Unauthorized() : Results.Ok(UserToDto(user));
});

// Выход — аннулируем токен.
app.MapPost("/api/auth/logout", async (AppDbContext db, HttpRequest http) =>
{
    var token = ExtractBearer(http);
    if (token is not null)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.SessionToken == token);
        if (user is not null)
        {
            user.SessionToken = null;
            await db.SaveChangesAsync();
        }
    }
    return Results.Ok(new { ok = true });
});

app.Run();

// Извлекает Bearer-токен из заголовка Authorization.
static string? ExtractBearer(HttpRequest http)
{
    var header = http.Headers.Authorization.ToString();
    if (string.IsNullOrWhiteSpace(header)) return null;
    const string prefix = "Bearer ";
    return header.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
        ? header[prefix.Length..].Trim()
        : header.Trim();
}

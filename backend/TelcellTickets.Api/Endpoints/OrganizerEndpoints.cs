using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using TelcellTickets.Api.Data;
using TelcellTickets.Api.Dtos;
using TelcellTickets.Api.Models;
using TelcellTickets.Api.Services;

namespace TelcellTickets.Api.Endpoints;

public static class OrganizerEndpoints
{
    public static string HashPassword(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(16);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, 100_000, HashAlgorithmName.SHA256, 32);
        return $"{Convert.ToBase64String(salt)}.{Convert.ToBase64String(hash)}";
    }

    public static bool VerifyPassword(string password, string stored)
    {
        var parts = stored.Split('.');
        if (parts.Length != 2) return false;
        var salt = Convert.FromBase64String(parts[0]);
        var expected = Convert.FromBase64String(parts[1]);
        var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, 100_000, HashAlgorithmName.SHA256, 32);
        return CryptographicOperations.FixedTimeEquals(expected, actual);
    }

    public static async Task<AppUser?> CurrentUserAsync(AppDbContext db, HttpRequest http)
    {
        var header = http.Headers.Authorization.ToString();
        if (string.IsNullOrWhiteSpace(header)) return null;
        const string prefix = "Bearer ";
        var token = header.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
            ? header[prefix.Length..].Trim()
            : header.Trim();
        if (string.IsNullOrWhiteSpace(token)) return null;
        return await db.Users.FirstOrDefaultAsync(u => u.SessionToken == token);
    }

    public static async Task<IResult?> RequireOwnerAsync(AppDbContext db, HttpRequest http, Guid eventId)
    {
        var user = await CurrentUserAsync(db, http);
        if (user is null || (!user.IsOrganizer && !user.IsAdmin))
            return Results.Unauthorized();
        var ev = await db.Events.FirstOrDefaultAsync(e => e.Id == eventId);
        if (ev is null)
            return Results.NotFound(new { error = "Мероприятие не найдено." });
        if (!user.IsAdmin && ev.OrganizerId != user.Id)
            return Results.StatusCode(StatusCodes.Status403Forbidden);
        return null;
    }

    private static OrganizerDto ToOrganizerDto(AppUser u) =>
        new(u.Id, u.Email ?? "", u.OrganizerName ?? "", u.DisplayName, u.Phone, u.IsAdmin);

    private static string NewToken() =>
        Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");

    public static void MapOrganizerEndpoints(this WebApplication app)
    {
        app.MapPost("/api/organizer/register", async (AppDbContext db, OrganizerRegisterDto req) =>
        {
            if (string.IsNullOrWhiteSpace(req.Email) || !req.Email.Contains('@'))
                return Results.BadRequest(new { error = "Укажите корректный email." });
            if (string.IsNullOrWhiteSpace(req.Password) || req.Password.Length < 6)
                return Results.BadRequest(new { error = "Пароль должен быть не короче 6 символов." });
            if (string.IsNullOrWhiteSpace(req.OrganizerName) || req.OrganizerName.Trim().Length < 2)
                return Results.BadRequest(new { error = "Укажите название организации." });
            if (string.IsNullOrWhiteSpace(req.Phone) || req.Phone.Trim().Length < 6)
                return Results.BadRequest(new { error = "Укажите контактный телефон." });

            var email = req.Email.Trim().ToLower();
            var phone = req.Phone.Trim().Replace(" ", "").Replace("-", "");

            if (await db.Users.AnyAsync(u => u.Email != null && u.Email.ToLower() == email))
                return Results.BadRequest(new { error = "Пользователь с таким email уже зарегистрирован." });

            var user = new AppUser
            {
                Id = Guid.NewGuid(),
                Email = email,
                Phone = phone,
                DisplayName = string.IsNullOrWhiteSpace(req.ContactName) ? req.OrganizerName.Trim() : req.ContactName.Trim(),
                OrganizerName = req.OrganizerName.Trim(),
                IsOrganizer = true,
                PasswordHash = HashPassword(req.Password),
                SessionToken = NewToken()
            };
            db.Users.Add(user);
            await db.SaveChangesAsync();

            return Results.Ok(new OrganizerAuthResultDto(user.SessionToken!, ToOrganizerDto(user)));
        });

        app.MapPost("/api/organizer/login", async (AppDbContext db, OrganizerLoginDto req) =>
        {
            if (string.IsNullOrWhiteSpace(req.Email) || string.IsNullOrWhiteSpace(req.Password))
                return Results.BadRequest(new { error = "Укажите email и пароль." });

            var email = req.Email.Trim().ToLower();
            var user = await db.Users.FirstOrDefaultAsync(u => u.Email != null && u.Email.ToLower() == email);
            if (user is null || user.PasswordHash is null || !VerifyPassword(req.Password, user.PasswordHash))
                return Results.BadRequest(new { error = "Неверный email или пароль." });
            if (!user.IsOrganizer && !user.IsAdmin)
                return Results.BadRequest(new { error = "Этот аккаунт не является организатором." });

            user.SessionToken = NewToken();
            await db.SaveChangesAsync();
            return Results.Ok(new OrganizerAuthResultDto(user.SessionToken!, ToOrganizerDto(user)));
        });

        app.MapGet("/api/organizer/me", async (AppDbContext db, HttpRequest http) =>
        {
            var user = await CurrentUserAsync(db, http);
            if (user is null || (!user.IsOrganizer && !user.IsAdmin)) return Results.Unauthorized();
            return Results.Ok(ToOrganizerDto(user));
        });

        app.MapGet("/api/organizer/events", async (AppDbContext db, HttpRequest http,
            string? q, DateTimeOffset? from, DateTimeOffset? to, string? status, bool? hasLayout, string? sort) =>
        {
            var user = await CurrentUserAsync(db, http);
            if (user is null || (!user.IsOrganizer && !user.IsAdmin)) return Results.Unauthorized();

            var query = db.Events.Include(e => e.Venue).AsQueryable();
            if (!user.IsAdmin)
                query = query.Where(e => e.OrganizerId == user.Id);

            if (!string.IsNullOrWhiteSpace(q))
            {
                var term = q.Trim().ToLower();
                query = query.Where(e => e.Title.ToLower().Contains(term));
            }
            if (from.HasValue) query = query.Where(e => e.StartsAt >= from);
            if (to.HasValue) query = query.Where(e => e.StartsAt <= to);
            if (!string.IsNullOrWhiteSpace(status) && Enum.TryParse<EventStatus>(status, true, out var st))
                query = query.Where(e => e.Status == st);

            var events = await query.ToListAsync();
            var ids = events.Select(e => e.Id).ToList();

            var layouts = await db.EventLayouts
                .Where(l => ids.Contains(l.EventId) && l.HasSeatingPlan)
                .Select(l => l.EventId)
                .ToListAsync();
            var layoutSet = layouts.ToHashSet();

            var soldCounts = await db.Tickets
                .Where(t => ids.Contains(t.EventId) &&
                            (t.Status == TicketStatus.Issued || t.Status == TicketStatus.CheckedIn || t.Status == TicketStatus.Transferred))
                .GroupBy(t => t.EventId)
                .Select(g => new { g.Key, Count = g.Count() })
                .ToDictionaryAsync(x => x.Key, x => x.Count);

            if (hasLayout.HasValue)
                events = events.Where(e => layoutSet.Contains(e.Id) == hasLayout.Value).ToList();

            events = sort switch
            {
                "starts" => events.OrderBy(e => e.StartsAt).ToList(),
                "sold" => events.OrderByDescending(e => soldCounts.GetValueOrDefault(e.Id)).ToList(),
                _ => events.OrderByDescending(e => e.CreatedAt).ToList()
            };

            return Results.Ok(events.Select(e => new OrganizerEventDto(
                e.Id, e.Title, e.Description, e.Category.ToString(), e.StartsAt,
                e.CoverColorHex, e.CoverImageUrl, e.Status.ToString(),
                e.VenueId, e.Venue?.Name ?? "", e.Venue?.City ?? "",
                e.OrganizerId, layoutSet.Contains(e.Id),
                soldCounts.GetValueOrDefault(e.Id), e.CreatedAt)));
        });

        app.MapPost("/api/organizer/events", async (AppDbContext db, HttpRequest http, SaveOrganizerEventDto dto) =>
        {
            var user = await CurrentUserAsync(db, http);
            if (user is null || (!user.IsOrganizer && !user.IsAdmin)) return Results.Unauthorized();

            var validation = ValidateEvent(dto);
            if (validation is not null) return validation;
            if (!await db.Venues.AnyAsync(v => v.Id == dto.VenueId))
                return Results.BadRequest(new { error = "Площадка не найдена." });

            Enum.TryParse<EventCategory>(dto.Category, true, out var cat);
            Enum.TryParse<EventStatus>(dto.Status, true, out var st);

            var ev = new Event
            {
                Id = Guid.NewGuid(),
                Title = dto.Title.Trim(),
                TitleAm = dto.Title.Trim(),
                Description = (dto.Description ?? "").Trim(),
                DescriptionAm = (dto.Description ?? "").Trim(),
                Category = cat,
                StartsAt = dto.StartsAt,
                VenueId = dto.VenueId,
                CoverImageUrl = string.IsNullOrWhiteSpace(dto.CoverImageUrl) ? null : dto.CoverImageUrl.Trim(),
                CoverColorHex = string.IsNullOrWhiteSpace(dto.CoverColorHex) ? "#361268" : dto.CoverColorHex.Trim(),
                Status = st,
                OrganizerId = user.Id,
                CreatedAt = DateTimeOffset.UtcNow
            };
            db.Events.Add(ev);
            await db.SaveChangesAsync();

            var venue = await db.Venues.FirstAsync(v => v.Id == ev.VenueId);
            return Results.Created($"/api/organizer/events/{ev.Id}", new OrganizerEventDto(
                ev.Id, ev.Title, ev.Description, ev.Category.ToString(), ev.StartsAt,
                ev.CoverColorHex, ev.CoverImageUrl, ev.Status.ToString(),
                ev.VenueId, venue.Name, venue.City, ev.OrganizerId, false, 0, ev.CreatedAt));
        });

        app.MapPut("/api/organizer/events/{id:guid}", async (AppDbContext db, HttpRequest http, Guid id, SaveOrganizerEventDto dto) =>
        {
            var guard = await RequireOwnerAsync(db, http, id);
            if (guard is not null) return guard;

            var validation = ValidateEvent(dto);
            if (validation is not null) return validation;
            if (!await db.Venues.AnyAsync(v => v.Id == dto.VenueId))
                return Results.BadRequest(new { error = "Площадка не найдена." });

            var ev = await db.Events.Include(e => e.Venue).FirstAsync(e => e.Id == id);
            Enum.TryParse<EventCategory>(dto.Category, true, out var cat);
            Enum.TryParse<EventStatus>(dto.Status, true, out var st);

            ev.Title = dto.Title.Trim();
            ev.TitleAm = dto.Title.Trim();
            ev.Description = (dto.Description ?? "").Trim();
            ev.DescriptionAm = (dto.Description ?? "").Trim();
            ev.Category = cat;
            ev.StartsAt = dto.StartsAt;
            ev.VenueId = dto.VenueId;
            ev.CoverImageUrl = string.IsNullOrWhiteSpace(dto.CoverImageUrl) ? null : dto.CoverImageUrl.Trim();
            if (!string.IsNullOrWhiteSpace(dto.CoverColorHex)) ev.CoverColorHex = dto.CoverColorHex.Trim();
            ev.Status = st;
            await db.SaveChangesAsync();

            var venue = await db.Venues.FirstAsync(v => v.Id == ev.VenueId);
            var hasPlan = await db.EventLayouts.AnyAsync(l => l.EventId == id && l.HasSeatingPlan);
            var sold = await db.Tickets.CountAsync(t => t.EventId == id &&
                (t.Status == TicketStatus.Issued || t.Status == TicketStatus.CheckedIn || t.Status == TicketStatus.Transferred));
            return Results.Ok(new OrganizerEventDto(
                ev.Id, ev.Title, ev.Description, ev.Category.ToString(), ev.StartsAt,
                ev.CoverColorHex, ev.CoverImageUrl, ev.Status.ToString(),
                ev.VenueId, venue.Name, venue.City, ev.OrganizerId, hasPlan, sold, ev.CreatedAt));
        });

        app.MapGet("/api/organizer/events/{id:guid}", async (AppDbContext db, HttpRequest http, Guid id) =>
        {
            var guard = await RequireOwnerAsync(db, http, id);
            if (guard is not null) return guard;

            var ev = await db.Events.Include(e => e.Venue).FirstAsync(e => e.Id == id);
            var hasPlan = await db.EventLayouts.AnyAsync(l => l.EventId == id && l.HasSeatingPlan);
            var sold = await db.Tickets.CountAsync(t => t.EventId == id &&
                (t.Status == TicketStatus.Issued || t.Status == TicketStatus.CheckedIn || t.Status == TicketStatus.Transferred));
            return Results.Ok(new OrganizerEventDto(
                ev.Id, ev.Title, ev.Description, ev.Category.ToString(), ev.StartsAt,
                ev.CoverColorHex, ev.CoverImageUrl, ev.Status.ToString(),
                ev.VenueId, ev.Venue?.Name ?? "", ev.Venue?.City ?? "",
                ev.OrganizerId, hasPlan, sold, ev.CreatedAt));
        });

        app.MapGet("/api/organizer/events/{id:guid}/online", async (AppDbContext db, HttpRequest http, SeatHub hub, Guid id) =>
        {
            var guard = await RequireOwnerAsync(db, http, id);
            if (guard is not null) return guard;
            return Results.Ok(new { online = hub.OnlineCount(id) });
        });

        app.MapGet("/api/organizer/events/{id:guid}/buyers", async (AppDbContext db, HttpRequest http,
            Guid id, string? q, int page = 1, int pageSize = 20) =>
        {
            var guard = await RequireOwnerAsync(db, http, id);
            if (guard is not null) return guard;

            page = Math.Max(1, page);
            pageSize = Math.Clamp(pageSize, 1, 100);

            var grouped = db.Tickets
                .Where(t => t.EventId == id &&
                            (t.Status == TicketStatus.Issued || t.Status == TicketStatus.CheckedIn || t.Status == TicketStatus.Transferred))
                .Join(db.Orders, t => t.OrderId, o => o.Id, (t, o) => new { t, o })
                .Join(db.Users, x => x.o.UserId, u => u.Id, (x, u) => new { x.t, u })
                .GroupBy(x => new { x.u.Id, x.u.DisplayName, x.u.Phone, x.u.Email })
                .Select(g => new EventBuyerDto(
                    g.Key.Id, g.Key.DisplayName, g.Key.Phone, g.Key.Email,
                    g.Count(), g.Sum(x => x.t.Price), g.Max(x => x.t.IssuedAt)));

            if (!string.IsNullOrWhiteSpace(q))
            {
                var term = q.Trim().ToLower();
                grouped = grouped.Where(b =>
                    b.DisplayName.ToLower().Contains(term) ||
                    (b.Email != null && b.Email.ToLower().Contains(term)) ||
                    b.Phone.Contains(term));
            }

            var total = await grouped.CountAsync();
            var items = await grouped
                .OrderByDescending(b => b.LastPurchaseAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            return Results.Ok(new EventBuyersPageDto(total, page, pageSize, items));
        });
    }

    private static IResult? ValidateEvent(SaveOrganizerEventDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Title) || dto.Title.Trim().Length < 2)
            return Results.BadRequest(new { error = "Укажите название мероприятия." });
        if (!Enum.TryParse<EventCategory>(dto.Category, true, out _))
            return Results.BadRequest(new { error = "Некорректная категория." });
        if (!Enum.TryParse<EventStatus>(dto.Status, true, out _))
            return Results.BadRequest(new { error = "Некорректный статус." });
        return null;
    }
}

using Microsoft.EntityFrameworkCore;
using TelcellTickets.Api.Data;
using TelcellTickets.Api.Models;

namespace TelcellTickets.Api.Services;

/// <summary>
/// Бизнес-логика резерваций мест: reserve / release / keepalive / sell.
/// Работает с БД и рассылает изменения через <see cref="SeatHub"/>.
/// </summary>
public class SeatReservationService
{
    public static readonly TimeSpan ReservationTtl = TimeSpan.FromMinutes(5);
    public const int MaxSeatsPerSession = 5;

    private readonly AppDbContext _db;
    private readonly SeatHub _hub;

    public SeatReservationService(AppDbContext db, SeatHub hub)
    {
        _db = db;
        _hub = hub;
    }

    public sealed record Result(bool Ok, string? Error = null);

    /// <summary>Зарезервировать место за сессией на 5 минут.</summary>
    public async Task<Result> ReserveAsync(Guid eventId, string sessionId, Guid seatId, Guid? userId)
    {
        var seat = await _db.EventSeats
            .Include(s => s.EventSeatBlock)!.ThenInclude(b => b!.EventFloor)!.ThenInclude(f => f!.EventLayout)
            .FirstOrDefaultAsync(s => s.Id == seatId);

        if (seat is null || !seat.IsActive)
            return new(false, "Место не найдено.");

        if (seat.EventSeatBlock!.EventFloor!.EventLayout!.EventId != eventId)
            return new(false, "Место относится к другому мероприятию.");

        if (seat.Status == SeatStatus.Sold)
            return new(false, "Место уже продано.");

        // Уже держит эта же сессия — идемпотентно.
        var mine = await _db.SeatReservations
            .FirstOrDefaultAsync(r => r.EventSeatId == seatId && r.SessionId == sessionId);
        if (mine is not null)
        {
            mine.ReservedAt = DateTimeOffset.UtcNow;
            mine.ExpiresAt = DateTimeOffset.UtcNow.Add(ReservationTtl);
            await _db.SaveChangesAsync();
            return new(true);
        }

        if (seat.Status == SeatStatus.Reserved)
            return new(false, "Место уже занято другим покупателем.");

        var activeCount = await _db.SeatReservations
            .CountAsync(r => r.EventId == eventId && r.SessionId == sessionId);
        if (activeCount >= MaxSeatsPerSession)
            return new(false, $"Нельзя выбрать больше {MaxSeatsPerSession} мест.");

        var now = DateTimeOffset.UtcNow;
        seat.Status = SeatStatus.Reserved;
        seat.ReservedAt = now;
        seat.ReservedByUserId = userId;

        _db.SeatReservations.Add(new SeatReservation
        {
            Id = Guid.NewGuid(),
            EventId = eventId,
            SessionId = sessionId,
            EventSeatId = seatId,
            ReservedAt = now,
            ExpiresAt = now.Add(ReservationTtl)
        });

        await _db.SaveChangesAsync();
        await _hub.BroadcastAsync(eventId, new { type = "seat_reserved", seatId, sessionId });
        return new(true);
    }

    /// <summary>Снять резерв конкретного места этой сессии.</summary>
    public async Task ReleaseAsync(Guid eventId, string sessionId, Guid seatId)
    {
        var res = await _db.SeatReservations
            .FirstOrDefaultAsync(r => r.EventSeatId == seatId && r.SessionId == sessionId);
        if (res is null) return;

        _db.SeatReservations.Remove(res);
        await FreeSeatAsync(seatId);
        await _db.SaveChangesAsync();
        await _hub.BroadcastAsync(eventId, new { type = "seat_released", seatId });
    }

    /// <summary>Снять все резервы сессии для события (отмена/выход).</summary>
    public async Task ReleaseAllAsync(Guid eventId, string sessionId)
    {
        var mine = await _db.SeatReservations
            .Where(r => r.EventId == eventId && r.SessionId == sessionId).ToListAsync();
        if (mine.Count == 0) return;

        _db.SeatReservations.RemoveRange(mine);
        foreach (var r in mine) await FreeSeatAsync(r.EventSeatId);
        await _db.SaveChangesAsync();

        foreach (var r in mine)
            await _hub.BroadcastAsync(eventId, new { type = "seat_released", seatId = r.EventSeatId });
    }

    /// <summary>Продлить все резервы сессии ещё на 5 минут (диалог «Продолжаем?»).</summary>
    public async Task KeepaliveAsync(Guid eventId, string sessionId)
    {
        var mine = await _db.SeatReservations
            .Where(r => r.EventId == eventId && r.SessionId == sessionId).ToListAsync();
        var exp = DateTimeOffset.UtcNow.Add(ReservationTtl);
        foreach (var r in mine) r.ExpiresAt = exp;
        if (mine.Count > 0) await _db.SaveChangesAsync();
    }

    /// <summary>Освободить истёкшие резервы (вызывается фоновым сервисом).</summary>
    public async Task<int> ExpireDueAsync()
    {
        var now = DateTimeOffset.UtcNow;
        var due = await _db.SeatReservations.Where(r => r.ExpiresAt <= now).ToListAsync();
        if (due.Count == 0) return 0;

        _db.SeatReservations.RemoveRange(due);
        foreach (var r in due) await FreeSeatAsync(r.EventSeatId);
        await _db.SaveChangesAsync();

        foreach (var r in due)
            await _hub.BroadcastAsync(r.EventId, new { type = "seat_released", seatId = r.EventSeatId });
        return due.Count;
    }

    private async Task FreeSeatAsync(Guid seatId)
    {
        var seat = await _db.EventSeats.FirstOrDefaultAsync(s => s.Id == seatId);
        if (seat is null || seat.Status == SeatStatus.Sold) return;
        seat.Status = SeatStatus.Available;
        seat.ReservedAt = null;
        seat.ReservedByUserId = null;
    }
}

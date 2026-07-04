namespace TelcellTickets.Api.Dtos;

// ══════════════════════════════════════════════════════════════════════════
//  DTO схем залов. Веб-админка шлёт/получает эти структуры целиком (JSON).
// ══════════════════════════════════════════════════════════════════════════

public record StageDto(
    double CanvasX,
    double CanvasY,
    double Width,
    double Height,
    string Label);

public record SeatDto(
    Guid? Id,
    int Row,
    int Number,
    string SeatType,
    decimal Price,
    string? Description,
    string Color,
    double CanvasX,
    double CanvasY,
    bool IsActive);

public record SeatBlockDto(
    Guid? Id,
    string SeatType,
    decimal DefaultPrice,
    string? DefaultDescription,
    string DefaultColor,
    double CanvasX,
    double CanvasY,
    double RotationDeg,
    int Rows,
    int SeatsPerRow,
    List<SeatDto> Seats);

public record FloorDto(
    Guid? Id,
    string Name,
    int Order,
    StageDto? Stage,
    List<SeatBlockDto> SeatBlocks);

/// <summary>Полная схема шаблона (ответ GET /api/venue-layouts/{id}).</summary>
public record VenueLayoutDto(
    Guid Id,
    Guid VenueId,
    string VenueName,
    string Name,
    DateTimeOffset CreatedAt,
    List<FloorDto> Floors);

/// <summary>Краткая карточка шаблона в списке.</summary>
public record VenueLayoutSummaryDto(
    Guid Id,
    Guid VenueId,
    string VenueName,
    string Name,
    DateTimeOffset CreatedAt,
    int FloorCount,
    int SeatCount);

/// <summary>Тело POST/PUT /api/venue-layouts.</summary>
public record SaveVenueLayoutDto(
    Guid VenueId,
    string Name,
    List<FloorDto> Floors);

// ── Схема конкретного мероприятия ─────────────────────────────────────────

public record EventSeatDto(
    Guid Id,
    int Row,
    int Number,
    string SeatType,
    decimal Price,
    string? Description,
    string Color,
    double CanvasX,
    double CanvasY,
    bool IsActive,
    string Status);

public record EventSeatBlockDto(
    Guid Id,
    string SeatType,
    decimal DefaultPrice,
    string? DefaultDescription,
    string DefaultColor,
    double CanvasX,
    double CanvasY,
    double RotationDeg,
    int Rows,
    int SeatsPerRow,
    List<EventSeatDto> Seats);

public record EventFloorDto(
    Guid Id,
    string Name,
    int Order,
    StageDto? Stage,
    List<EventSeatBlockDto> SeatBlocks);

public record EventLayoutDto(
    Guid Id,
    Guid EventId,
    bool HasSeatingPlan,
    Guid? VenueLayoutId,
    List<EventFloorDto> Floors);

/// <summary>Тело POST /api/events/{eventId}/layout.</summary>
public record CreateEventLayoutDto(
    Guid? VenueLayoutId,
    bool HasSeatingPlan,
    // Если рисуют схему прямо под событие (без шаблона) — можно прислать этажи.
    List<FloorDto>? Floors);

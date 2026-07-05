using TelcellTickets.Api.Models;

namespace TelcellTickets.Api.Dtos;

// ─── Ответы ───────────────────────────────────────────────────────────

public record VenueDto(Guid Id, string Name, string NameAm, string City, string Address, string AddressAm, double Latitude, double Longitude);

public record TicketTypeDto(Guid Id, string Name, string NameAm, decimal Price, string Currency, int Available);

public record EventDto(
    Guid Id,
    string Title,
    string TitleAm,
    string Description,
    string DescriptionAm,
    string Category,
    DateTimeOffset StartsAt,
    string CoverColorHex,
    string? CoverImageUrl,
    bool IsFeatured,
    VenueDto Venue,
    IEnumerable<TicketTypeDto> TicketTypes,
    decimal MinPrice,
    // Refund Guarantee (PRD §8, Сценарий В): можно ли вернуть билет.
    bool RefundGuarantee = false,
    int RefundUntilHours = 24);

public record TicketDto(
    Guid Id,
    Guid EventId,
    string EventTitle,
    DateTimeOffset StartsAt,
    string VenueName,
    string TicketTypeName,
    decimal Price,
    string Currency,
    string QrToken,
    string Status,
    DateTimeOffset IssuedAt,
    string? TransferredTo = null,
    // Возврат разрешён для этого билета (наследуется от события).
    bool RefundGuarantee = false,
    int RefundUntilHours = 24);

public record OrderResultDto(Guid OrderId, string Status, decimal Total, string Currency, IEnumerable<TicketDto> Tickets);

// ─── Запросы ──────────────────────────────────────────────────────────

/// <summary>Покупка: список (тип билета + количество) + покупатель.</summary>
public record CheckoutItemDto(Guid TicketTypeId, int Quantity);

public record CheckoutRequestDto(
    string BuyerName,
    string BuyerPhone,
    IEnumerable<CheckoutItemDto> Items,
    // ── Покупка по схеме зала ─────────────────────────────────────────────
    // Если непусто — берём именно эти места (они должны быть Reserved этой сессией).
    IReadOnlyList<Guid>? SelectedSeatIds = null,
    string? SessionId = null);

public record CheckInRequestDto(string QrToken);

/// <summary>Передача билета другому пользователю (PRD §5.5, US-03).</summary>
public record TransferRequestDto(string ToContact);

/// <summary>Результат поиска получателя по контакту (телефон или email)
/// для передачи билета. Found=false означает, что такого
/// пользователя нет — передача невозможна (q_recipient_lookup:
/// показываем «пользователь не найден»).</summary>
public record RecipientLookupDto(bool Found, string? DisplayName, string Contact);

// ─── Авторизация (телефон/email + mock-OTP) ─────────────────────────────────

/// <summary>Регистрация нового пользователя.</summary>
public record RegisterDto(string DisplayName, string Email, string Phone);

/// <summary>Результат регистрации.</summary>
public record RegisterResultDto(bool Success, string? Error = null, string? DevCode = null);

/// <summary>Запрос на отправку кода (вход): email или телефон.</summary>
public record LoginRequestDto(string Contact);

/// <summary>Ответ на запрос кода. В dev-режиме код возвращается в DevCode.</summary>
public record LoginRequestResultDto(bool Sent, string? Error = null, string? DevCode = null);

/// <summary>Проверка кода и выдача сессии.</summary>
public record VerifyCodeDto(string Contact, string Code);

/// <summary>Профиль пользователя для клиента. IsAdmin=true только
/// для скрытого admin-входа — открывает админ-панель на клиенте.</summary>
public record UserDto(Guid Id, string DisplayName, string Phone, string? Email = null, bool IsAdmin = false);

/// <summary>Результат входа: токен сессии + профиль.</summary>
public record AuthResultDto(string Token, UserDto User);

// Старые DTO для совместимости
public record RequestOtpDto(string Phone, string? DisplayName = null);
public record RequestOtpResultDto(bool Sent, string? DevCode = null);
public record VerifyOtpDto(string Phone, string Code);

public record OrganizerRegisterDto(
    string Email,
    string Password,
    string OrganizerName,
    string ContactName,
    string Phone);

public record OrganizerLoginDto(string Email, string Password);

public record OrganizerDto(
    Guid Id,
    string Email,
    string OrganizerName,
    string ContactName,
    string Phone,
    bool IsAdmin);

public record OrganizerAuthResultDto(string Token, OrganizerDto Organizer);

public record OrganizerEventDto(
    Guid Id,
    string Title,
    string Description,
    string Category,
    DateTimeOffset StartsAt,
    string CoverColorHex,
    string? CoverImageUrl,
    string Status,
    Guid VenueId,
    string VenueName,
    string VenueCity,
    Guid? OrganizerId,
    bool HasSeatingPlan,
    int TicketsSold,
    DateTimeOffset CreatedAt);

public record SaveOrganizerEventDto(
    string Title,
    string? Description,
    string Category,
    DateTimeOffset StartsAt,
    Guid VenueId,
    string? CoverImageUrl,
    string? CoverColorHex,
    string Status);

public record EventBuyerDto(
    Guid UserId,
    string DisplayName,
    string Phone,
    string? Email,
    int TicketCount,
    decimal Total,
    DateTimeOffset LastPurchaseAt);

public record EventBuyersPageDto(
    int Total,
    int Page,
    int PageSize,
    IEnumerable<EventBuyerDto> Items);

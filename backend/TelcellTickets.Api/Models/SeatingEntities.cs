namespace TelcellTickets.Api.Models;

/// <summary>Тип кресла. Определяет форму отрисовки и семантику места.</summary>
public enum SeatType
{
    Standard,
    VIP,
    Sofa,
    Standing,
    Disabled
}

/// <summary>Доступность конкретного места на мероприятии (реалтайм).</summary>
public enum SeatStatus
{
    Available,
    Reserved,
    Sold
}

// ══════════════════════════════════════════════════════════════════════════
//  ШАБЛОНЫ ЗАЛОВ (VenueLayout) — то, что рисует администратор в веб-админке.
//  Многоразовые: один шаблон можно копировать в любое число мероприятий.
// ══════════════════════════════════════════════════════════════════════════

/// <summary>Шаблон зала, привязанный к площадке (Venue).</summary>
public class VenueLayout
{
    public Guid Id { get; set; }

    public Guid VenueId { get; set; }
    public Venue? Venue { get; set; }

    /// <summary>Название шаблона для поиска ("Большой зал", "Летняя сцена").</summary>
    public string Name { get; set; } = "";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public ICollection<VenueFloor> Floors { get; set; } = new List<VenueFloor>();
}

/// <summary>Этаж/уровень внутри шаблона зала ("Партер", "Балкон").</summary>
public class VenueFloor
{
    public Guid Id { get; set; }

    public Guid VenueLayoutId { get; set; }
    public VenueLayout? VenueLayout { get; set; }

    public string Name { get; set; } = "";

    /// <summary>Порядок отображения вкладок этажей.</summary>
    public int Order { get; set; }

    public Stage? Stage { get; set; }
    public ICollection<SeatBlock> SeatBlocks { get; set; } = new List<SeatBlock>();
}

/// <summary>Прямоугольный блок кресел на холсте (сетка Rows × SeatsPerRow).</summary>
public class SeatBlock
{
    public Guid Id { get; set; }

    public Guid VenueFloorId { get; set; }
    public VenueFloor? VenueFloor { get; set; }

    public SeatType SeatType { get; set; } = SeatType.Standard;
    public decimal DefaultPrice { get; set; }
    public string? DefaultDescription { get; set; }
    public string DefaultColor { get; set; } = "#6C63FF";

    /// <summary>Позиция центра блока на холсте.</summary>
    public double CanvasX { get; set; }
    public double CanvasY { get; set; }

    /// <summary>Произвольный угол поворота блока в градусах.</summary>
    public double RotationDeg { get; set; }

    public int Rows { get; set; }
    public int SeatsPerRow { get; set; }

    public ICollection<Seat> Seats { get; set; } = new List<Seat>();
}

/// <summary>Отдельное кресло в блоке. Может переопределять параметры блока.</summary>
public class Seat
{
    public Guid Id { get; set; }

    public Guid SeatBlockId { get; set; }
    public SeatBlock? SeatBlock { get; set; }

    /// <summary>Номер ряда (сквозная нумерация по всему этажу).</summary>
    public int Row { get; set; }

    /// <summary>Номер места (сквозная нумерация по всему этажу).</summary>
    public int Number { get; set; }

    public SeatType SeatType { get; set; } = SeatType.Standard;
    public decimal Price { get; set; }
    public string? Description { get; set; }
    public string Color { get; set; } = "#6C63FF";

    /// <summary>Абсолютная позиция кресла на холсте (с учётом поворота блока).</summary>
    public double CanvasX { get; set; }
    public double CanvasY { get; set; }

    /// <summary>false — место удалено вручную из блока.</summary>
    public bool IsActive { get; set; } = true;
}

/// <summary>Сцена/экран/арена — обязательный элемент на каждом этаже.</summary>
public class Stage
{
    public Guid Id { get; set; }

    public Guid VenueFloorId { get; set; }
    public VenueFloor? VenueFloor { get; set; }

    public double CanvasX { get; set; }
    public double CanvasY { get; set; }
    public double Width { get; set; } = 240;
    public double Height { get; set; } = 64;

    public string Label { get; set; } = "СЦЕНА";
}

// ══════════════════════════════════════════════════════════════════════════
//  СХЕМА МЕРОПРИЯТИЯ (EventLayout) — КОПИЯ шаблона под конкретное событие.
//  Копия, а не ссылка: правки шаблона не ломают уже созданные события.
// ══════════════════════════════════════════════════════════════════════════

/// <summary>Связь мероприятия со схемой зала (одна на событие).</summary>
public class EventLayout
{
    public Guid Id { get; set; }

    public Guid EventId { get; set; }
    public Event? Event { get; set; }

    /// <summary>Шаблон, из которого скопировано (null если рисовали с нуля).</summary>
    public Guid? VenueLayoutId { get; set; }

    /// <summary>true — схема зала; false — старые «плюсики» (TicketType).</summary>
    public bool HasSeatingPlan { get; set; }

    public ICollection<EventFloor> Floors { get; set; } = new List<EventFloor>();
}

/// <summary>Копия VenueFloor под мероприятие.</summary>
public class EventFloor
{
    public Guid Id { get; set; }

    public Guid EventLayoutId { get; set; }
    public EventLayout? EventLayout { get; set; }

    public string Name { get; set; } = "";
    public int Order { get; set; }

    public EventStage? Stage { get; set; }
    public ICollection<EventSeatBlock> SeatBlocks { get; set; } = new List<EventSeatBlock>();
}

/// <summary>Копия Stage под мероприятие.</summary>
public class EventStage
{
    public Guid Id { get; set; }

    public Guid EventFloorId { get; set; }
    public EventFloor? EventFloor { get; set; }

    public double CanvasX { get; set; }
    public double CanvasY { get; set; }
    public double Width { get; set; } = 240;
    public double Height { get; set; } = 64;
    public string Label { get; set; } = "СЦЕНА";
}

/// <summary>Копия SeatBlock под мероприятие.</summary>
public class EventSeatBlock
{
    public Guid Id { get; set; }

    public Guid EventFloorId { get; set; }
    public EventFloor? EventFloor { get; set; }

    public SeatType SeatType { get; set; } = SeatType.Standard;
    public decimal DefaultPrice { get; set; }
    public string? DefaultDescription { get; set; }
    public string DefaultColor { get; set; } = "#6C63FF";

    public double CanvasX { get; set; }
    public double CanvasY { get; set; }
    public double RotationDeg { get; set; }
    public int Rows { get; set; }
    public int SeatsPerRow { get; set; }

    public ICollection<EventSeat> Seats { get; set; } = new List<EventSeat>();
}

/// <summary>Копия Seat под мероприятие + реалтайм-состояние продажи.</summary>
public class EventSeat
{
    public Guid Id { get; set; }

    public Guid EventSeatBlockId { get; set; }
    public EventSeatBlock? EventSeatBlock { get; set; }

    public int Row { get; set; }
    public int Number { get; set; }

    public SeatType SeatType { get; set; } = SeatType.Standard;
    public decimal Price { get; set; }
    public string? Description { get; set; }
    public string Color { get; set; } = "#6C63FF";

    public double CanvasX { get; set; }
    public double CanvasY { get; set; }
    public bool IsActive { get; set; } = true;

    // ── Реалтайм ──────────────────────────────────────────────────────────
    public SeatStatus Status { get; set; } = SeatStatus.Available;

    /// <summary>Кто держит резерв (может быть null для гостя — держим по сессии).</summary>
    public Guid? ReservedByUserId { get; set; }
    public DateTimeOffset? ReservedAt { get; set; }

    /// <summary>Заказ, к которому привязано место после оплаты.</summary>
    public Guid? OrderId { get; set; }
}

/// <summary>Лог активных резерваций для WebSocket (истекают через 5 минут).</summary>
public class SeatReservation
{
    public Guid Id { get; set; }

    public Guid EventId { get; set; }

    /// <summary>ID сессии покупателя (не userId — чтобы работало и для гостей).</summary>
    public string SessionId { get; set; } = "";

    public Guid EventSeatId { get; set; }

    public DateTimeOffset ReservedAt { get; set; }

    /// <summary>ReservedAt + 5 минут. По истечении место освобождается.</summary>
    public DateTimeOffset ExpiresAt { get; set; }
}

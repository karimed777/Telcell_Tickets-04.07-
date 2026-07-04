using TelcellTickets.Api.Dtos;
using TelcellTickets.Api.Models;

namespace TelcellTickets.Api.Services;

/// <summary>Сборка/маппинг схем залов: DTO ↔ сущности, копия шаблона в событие,
/// сквозная нумерация рядов и мест.</summary>
public static class SeatingMapper
{
    // ── Парсинг enum типа кресла (терпимый к регистру) ────────────────────
    public static SeatType ParseSeatType(string? s) =>
        Enum.TryParse<SeatType>(s, ignoreCase: true, out var v) ? v : SeatType.Standard;

    // ══════════════════════════════════════════════════════════════════════
    //  DTO -> сущности VenueLayout (создание/обновление шаблона)
    // ══════════════════════════════════════════════════════════════════════
    public static List<VenueFloor> BuildFloors(List<FloorDto> dtos)
    {
        var floors = new List<VenueFloor>();
        foreach (var f in dtos)
        {
            var floor = new VenueFloor
            {
                Id = Guid.NewGuid(),
                Name = f.Name,
                Order = f.Order,
                Stage = f.Stage is null ? null : new Stage
                {
                    Id = Guid.NewGuid(),
                    CanvasX = f.Stage.CanvasX,
                    CanvasY = f.Stage.CanvasY,
                    Width = f.Stage.Width,
                    Height = f.Stage.Height,
                    Label = f.Stage.Label
                }
            };

            foreach (var b in f.SeatBlocks)
            {
                var block = new SeatBlock
                {
                    Id = Guid.NewGuid(),
                    SeatType = ParseSeatType(b.SeatType),
                    DefaultPrice = b.DefaultPrice,
                    DefaultDescription = b.DefaultDescription,
                    DefaultColor = b.DefaultColor,
                    CanvasX = b.CanvasX,
                    CanvasY = b.CanvasY,
                    RotationDeg = b.RotationDeg,
                    Rows = b.Rows,
                    SeatsPerRow = b.SeatsPerRow
                };
                foreach (var s in b.Seats)
                {
                    block.Seats.Add(new Seat
                    {
                        Id = Guid.NewGuid(),
                        Row = s.Row,
                        Number = s.Number,
                        SeatType = ParseSeatType(s.SeatType),
                        Price = s.Price,
                        Description = s.Description,
                        Color = s.Color,
                        CanvasX = s.CanvasX,
                        CanvasY = s.CanvasY,
                        IsActive = s.IsActive
                    });
                }
                floor.SeatBlocks.Add(block);
            }

            RenumberFloor(floor);
            floors.Add(floor);
        }
        return floors;
    }

    /// <summary>Сквозная нумерация по всему этажу: обход всех блоков
    /// сверху-вниз (CanvasY), слева-направо (CanvasX). Ряды группируются
    /// по вертикальным полосам, места нумеруются подряд.</summary>
    public static void RenumberFloor(VenueFloor floor)
    {
        const double band = 24; // порог отнесения к одному ряду (px)
        var active = floor.SeatBlocks
            .SelectMany(b => b.Seats)
            .Where(s => s.IsActive)
            .OrderBy(s => s.CanvasY)
            .ToList();

        var rows = new List<List<Seat>>();
        double baseline = double.NegativeInfinity;
        foreach (var s in active)
        {
            if (rows.Count == 0 || s.CanvasY - baseline > band)
            {
                rows.Add(new List<Seat>());
                baseline = s.CanvasY;
            }
            rows[^1].Add(s);
        }

        var number = 1;
        for (var r = 0; r < rows.Count; r++)
        {
            foreach (var s in rows[r].OrderBy(x => x.CanvasX))
            {
                s.Row = r + 1;
                s.Number = number++;
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Копия шаблона -> схема мероприятия (КОПИЯ, не ссылка)
    // ══════════════════════════════════════════════════════════════════════
    public static EventLayout CopyToEvent(VenueLayout src, Guid eventId, bool hasSeatingPlan)
    {
        var layout = new EventLayout
        {
            Id = Guid.NewGuid(),
            EventId = eventId,
            VenueLayoutId = src.Id,
            HasSeatingPlan = hasSeatingPlan
        };

        foreach (var f in src.Floors.OrderBy(x => x.Order))
        {
            var floor = new EventFloor
            {
                Id = Guid.NewGuid(),
                Name = f.Name,
                Order = f.Order,
                Stage = f.Stage is null ? null : new EventStage
                {
                    Id = Guid.NewGuid(),
                    CanvasX = f.Stage.CanvasX,
                    CanvasY = f.Stage.CanvasY,
                    Width = f.Stage.Width,
                    Height = f.Stage.Height,
                    Label = f.Stage.Label
                }
            };
            foreach (var b in f.SeatBlocks)
            {
                var block = new EventSeatBlock
                {
                    Id = Guid.NewGuid(),
                    SeatType = b.SeatType,
                    DefaultPrice = b.DefaultPrice,
                    DefaultDescription = b.DefaultDescription,
                    DefaultColor = b.DefaultColor,
                    CanvasX = b.CanvasX,
                    CanvasY = b.CanvasY,
                    RotationDeg = b.RotationDeg,
                    Rows = b.Rows,
                    SeatsPerRow = b.SeatsPerRow
                };
                foreach (var s in b.Seats.Where(x => x.IsActive))
                {
                    block.Seats.Add(new EventSeat
                    {
                        Id = Guid.NewGuid(),
                        Row = s.Row,
                        Number = s.Number,
                        SeatType = s.SeatType,
                        Price = s.Price,
                        Description = s.Description,
                        Color = s.Color,
                        CanvasX = s.CanvasX,
                        CanvasY = s.CanvasY,
                        IsActive = true,
                        Status = SeatStatus.Available
                    });
                }
                floor.SeatBlocks.Add(block);
            }
            layout.Floors.Add(floor);
        }
        return layout;
    }

    /// <summary>Схема мероприятия из DTO-этажей (рисование без шаблона).</summary>
    public static EventLayout BuildEventLayout(Guid eventId, bool hasSeatingPlan, List<FloorDto>? dtos)
    {
        var layout = new EventLayout
        {
            Id = Guid.NewGuid(),
            EventId = eventId,
            HasSeatingPlan = hasSeatingPlan
        };
        if (dtos is null) return layout;

        // Переиспользуем сборку/нумерацию шаблона, затем конвертируем.
        foreach (var vf in BuildFloors(dtos))
        {
            var floor = new EventFloor
            {
                Id = Guid.NewGuid(),
                Name = vf.Name,
                Order = vf.Order,
                Stage = vf.Stage is null ? null : new EventStage
                {
                    Id = Guid.NewGuid(),
                    CanvasX = vf.Stage.CanvasX,
                    CanvasY = vf.Stage.CanvasY,
                    Width = vf.Stage.Width,
                    Height = vf.Stage.Height,
                    Label = vf.Stage.Label
                }
            };
            foreach (var b in vf.SeatBlocks)
            {
                var block = new EventSeatBlock
                {
                    Id = Guid.NewGuid(),
                    SeatType = b.SeatType,
                    DefaultPrice = b.DefaultPrice,
                    DefaultDescription = b.DefaultDescription,
                    DefaultColor = b.DefaultColor,
                    CanvasX = b.CanvasX,
                    CanvasY = b.CanvasY,
                    RotationDeg = b.RotationDeg,
                    Rows = b.Rows,
                    SeatsPerRow = b.SeatsPerRow
                };
                foreach (var s in b.Seats.Where(x => x.IsActive))
                {
                    block.Seats.Add(new EventSeat
                    {
                        Id = Guid.NewGuid(),
                        Row = s.Row, Number = s.Number,
                        SeatType = s.SeatType, Price = s.Price,
                        Description = s.Description, Color = s.Color,
                        CanvasX = s.CanvasX, CanvasY = s.CanvasY,
                        IsActive = true, Status = SeatStatus.Available
                    });
                }
                floor.SeatBlocks.Add(block);
            }
            layout.Floors.Add(floor);
        }
        return layout;
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Сущности -> DTO (ответы API)
    // ══════════════════════════════════════════════════════════════════════
    public static VenueLayoutDto ToDto(VenueLayout l) => new(
        l.Id, l.VenueId, l.Venue?.Name ?? "", l.Name, l.CreatedAt,
        l.Floors.OrderBy(f => f.Order).Select(f => new FloorDto(
            f.Id, f.Name, f.Order,
            f.Stage is null ? null : new StageDto(f.Stage.CanvasX, f.Stage.CanvasY, f.Stage.Width, f.Stage.Height, f.Stage.Label),
            f.SeatBlocks.Select(b => new SeatBlockDto(
                b.Id, b.SeatType.ToString(), b.DefaultPrice, b.DefaultDescription, b.DefaultColor,
                b.CanvasX, b.CanvasY, b.RotationDeg, b.Rows, b.SeatsPerRow,
                b.Seats.Select(s => new SeatDto(
                    s.Id, s.Row, s.Number, s.SeatType.ToString(), s.Price, s.Description, s.Color,
                    s.CanvasX, s.CanvasY, s.IsActive)).ToList())).ToList())).ToList());

    public static EventLayoutDto ToDto(EventLayout l) => new(
        l.Id, l.EventId, l.HasSeatingPlan, l.VenueLayoutId,
        l.Floors.OrderBy(f => f.Order).Select(f => new EventFloorDto(
            f.Id, f.Name, f.Order,
            f.Stage is null ? null : new StageDto(f.Stage.CanvasX, f.Stage.CanvasY, f.Stage.Width, f.Stage.Height, f.Stage.Label),
            f.SeatBlocks.Select(b => new EventSeatBlockDto(
                b.Id, b.SeatType.ToString(), b.DefaultPrice, b.DefaultDescription, b.DefaultColor,
                b.CanvasX, b.CanvasY, b.RotationDeg, b.Rows, b.SeatsPerRow,
                b.Seats.Select(s => new EventSeatDto(
                    s.Id, s.Row, s.Number, s.SeatType.ToString(), s.Price, s.Description, s.Color,
                    s.CanvasX, s.CanvasY, s.IsActive, s.Status.ToString())).ToList())).ToList())).ToList());
}

using Microsoft.EntityFrameworkCore;
using TelcellTickets.Api.Models;

namespace TelcellTickets.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Venue> Venues => Set<Venue>();
    public DbSet<Event> Events => Set<Event>();
    public DbSet<TicketType> TicketTypes => Set<TicketType>();
    public DbSet<AppUser> Users => Set<AppUser>();
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<Ticket> Tickets => Set<Ticket>();

    // ── Схемы залов ───────────────────────────────────────────────────────
    public DbSet<VenueLayout> VenueLayouts => Set<VenueLayout>();
    public DbSet<VenueFloor> VenueFloors => Set<VenueFloor>();
    public DbSet<SeatBlock> SeatBlocks => Set<SeatBlock>();
    public DbSet<Seat> Seats => Set<Seat>();
    public DbSet<Stage> Stages => Set<Stage>();

    public DbSet<EventLayout> EventLayouts => Set<EventLayout>();
    public DbSet<EventFloor> EventFloors => Set<EventFloor>();
    public DbSet<EventStage> EventStages => Set<EventStage>();
    public DbSet<EventSeatBlock> EventSeatBlocks => Set<EventSeatBlock>();
    public DbSet<EventSeat> EventSeats => Set<EventSeat>();
    public DbSet<SeatReservation> SeatReservations => Set<SeatReservation>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Event>()
            .HasOne(e => e.Venue)
            .WithMany(v => v.Events)
            .HasForeignKey(e => e.VenueId)
            .OnDelete(DeleteBehavior.Restrict);

        b.Entity<TicketType>()
            .HasOne(t => t.Event)
            .WithMany(e => e.TicketTypes)
            .HasForeignKey(t => t.EventId)
            .OnDelete(DeleteBehavior.Cascade);

        b.Entity<TicketType>().Ignore(t => t.Available);
        b.Entity<TicketType>().Property(t => t.Price).HasColumnType("numeric(12,2)");
        b.Entity<Order>().Property(o => o.Total).HasColumnType("numeric(12,2)");

        b.Entity<Order>()
            .HasOne(o => o.User)
            .WithMany()
            .HasForeignKey(o => o.UserId);

        b.Entity<Ticket>()
            .HasOne(t => t.Order)
            .WithMany(o => o.Tickets)
            .HasForeignKey(t => t.OrderId)
            .OnDelete(DeleteBehavior.Cascade);

        b.Entity<Ticket>()
            .HasOne(t => t.TicketType)
            .WithMany()
            .HasForeignKey(t => t.TicketTypeId)
            .IsRequired(false)
            .OnDelete(DeleteBehavior.Restrict);

        b.Entity<Ticket>()
            .HasOne(t => t.EventSeat)
            .WithMany()
            .HasForeignKey(t => t.EventSeatId)
            .IsRequired(false)
            .OnDelete(DeleteBehavior.Restrict);

        b.Entity<Ticket>().Property(t => t.Price).HasColumnType("numeric(12,2)");

        b.Entity<Ticket>()
            .HasIndex(t => t.QrToken)
            .IsUnique();

        b.Entity<Event>()
            .HasOne(e => e.Organizer)
            .WithMany()
            .HasForeignKey(e => e.OrganizerId)
            .IsRequired(false)
            .OnDelete(DeleteBehavior.SetNull);

        // enum -> string в БД (читаемо для дебага)
        b.Entity<Event>().Property(e => e.Category).HasConversion<string>();
        b.Entity<Event>().Property(e => e.Status).HasConversion<string>();
        b.Entity<Ticket>().Property(t => t.Status).HasConversion<string>();
        b.Entity<Order>().Property(o => o.Status).HasConversion<string>();

        ConfigureSeating(b);
    }

    // ── Конфигурация схем залов ───────────────────────────────────────────
    private static void ConfigureSeating(ModelBuilder b)
    {
        // Шаблоны (VenueLayout → Floor → SeatBlock → Seat, + Stage на этаж)
        b.Entity<VenueLayout>(e =>
        {
            e.HasOne(x => x.Venue).WithMany().HasForeignKey(x => x.VenueId)
                .OnDelete(DeleteBehavior.Restrict);
            e.HasMany(x => x.Floors).WithOne(f => f.VenueLayout!)
                .HasForeignKey(f => f.VenueLayoutId).OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => x.Name);
        });

        b.Entity<VenueFloor>(e =>
        {
            e.HasMany(x => x.SeatBlocks).WithOne(sb => sb.VenueFloor!)
                .HasForeignKey(sb => sb.VenueFloorId).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Stage).WithOne(s => s.VenueFloor!)
                .HasForeignKey<Stage>(s => s.VenueFloorId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<SeatBlock>(e =>
        {
            e.Property(x => x.SeatType).HasConversion<string>();
            e.Property(x => x.DefaultPrice).HasColumnType("numeric(12,2)");
            e.HasMany(x => x.Seats).WithOne(s => s.SeatBlock!)
                .HasForeignKey(s => s.SeatBlockId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<Seat>(e =>
        {
            e.Property(x => x.SeatType).HasConversion<string>();
            e.Property(x => x.Price).HasColumnType("numeric(12,2)");
        });

        // Копии под мероприятие (EventLayout → EventFloor → EventSeatBlock → EventSeat)
        b.Entity<EventLayout>(e =>
        {
            e.HasOne(x => x.Event).WithMany().HasForeignKey(x => x.EventId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => x.EventId).IsUnique();
            e.HasMany(x => x.Floors).WithOne(f => f.EventLayout!)
                .HasForeignKey(f => f.EventLayoutId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<EventFloor>(e =>
        {
            e.HasMany(x => x.SeatBlocks).WithOne(sb => sb.EventFloor!)
                .HasForeignKey(sb => sb.EventFloorId).OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Stage).WithOne(s => s.EventFloor!)
                .HasForeignKey<EventStage>(s => s.EventFloorId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<EventSeatBlock>(e =>
        {
            e.Property(x => x.SeatType).HasConversion<string>();
            e.Property(x => x.DefaultPrice).HasColumnType("numeric(12,2)");
            e.HasMany(x => x.Seats).WithOne(s => s.EventSeatBlock!)
                .HasForeignKey(s => s.EventSeatBlockId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<EventSeat>(e =>
        {
            e.Property(x => x.SeatType).HasConversion<string>();
            e.Property(x => x.Status).HasConversion<string>();
            e.Property(x => x.Price).HasColumnType("numeric(12,2)");
            e.HasIndex(x => x.EventSeatBlockId);
        });

        b.Entity<SeatReservation>(e =>
        {
            e.HasIndex(x => x.EventId);
            e.HasIndex(x => x.EventSeatId);
            e.HasIndex(x => x.SessionId);
            e.HasIndex(x => x.ExpiresAt);
        });
    }
}

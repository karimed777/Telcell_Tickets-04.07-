namespace TelcellTickets.Api.Services;

/// <summary>
/// Фоновый сервис: каждые 30 секунд освобождает истёкшие резервы мест
/// и рассылает seat_released подключённым к событиям.
/// </summary>
public class ReservationCleanupService : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromSeconds(30);

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<ReservationCleanupService> _log;

    public ReservationCleanupService(IServiceScopeFactory scopeFactory,
        ILogger<ReservationCleanupService> log)
    {
        _scopeFactory = scopeFactory;
        _log = log;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var svc = scope.ServiceProvider.GetRequiredService<SeatReservationService>();
                var freed = await svc.ExpireDueAsync();
                if (freed > 0) _log.LogInformation("Освобождено истёкших резервов: {Count}", freed);
            }
            catch (Exception ex)
            {
                _log.LogError(ex, "Ошибка при очистке резерваций");
            }
        }
    }
}

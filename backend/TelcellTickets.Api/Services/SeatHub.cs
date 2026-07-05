using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace TelcellTickets.Api.Services;

/// <summary>
/// Реестр WebSocket-подключений по событиям + рассылка сообщений.
/// Singleton: живёт всё время работы приложения. Без SignalR — чистый
/// System.Net.WebSockets, как требует ТЗ.
/// </summary>
public class SeatHub
{
    /// <summary>Одно подключение покупателя к схеме события.</summary>
    public sealed class Connection
    {
        public required string ConnectionId { get; init; }
        public required WebSocket Socket { get; init; }
        public required string SessionId { get; init; }
        public required Guid EventId { get; init; }
        public bool IsObserver { get; init; }
    }

    public int OnlineCount(Guid eventId)
    {
        if (!_byEvent.TryGetValue(eventId, out var conns)) return 0;
        return conns.Values.Count(c => !c.IsObserver && c.Socket.State == WebSocketState.Open);
    }

    // eventId -> (connectionId -> connection)
    private readonly ConcurrentDictionary<Guid, ConcurrentDictionary<string, Connection>> _byEvent = new();

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public void Add(Connection c) =>
        _byEvent.GetOrAdd(c.EventId, _ => new()).TryAdd(c.ConnectionId, c);

    public void Remove(Guid eventId, string connectionId)
    {
        if (_byEvent.TryGetValue(eventId, out var conns))
            conns.TryRemove(connectionId, out _);
    }

    /// <summary>Разослать сообщение всем подключённым к событию.</summary>
    public async Task BroadcastAsync(Guid eventId, object message)
    {
        if (!_byEvent.TryGetValue(eventId, out var conns) || conns.IsEmpty) return;

        var json = JsonSerializer.Serialize(message, JsonOpts);
        var bytes = Encoding.UTF8.GetBytes(json);

        foreach (var conn in conns.Values)
        {
            if (conn.Socket.State != WebSocketState.Open) continue;
            try
            {
                await conn.Socket.SendAsync(
                    new ArraySegment<byte>(bytes),
                    WebSocketMessageType.Text,
                    endOfMessage: true,
                    CancellationToken.None);
            }
            catch
            {
                // Битое соединение — уберём при следующем цикле чтения.
            }
        }
    }

    /// <summary>Отправить одному подключению (ответ на его запрос).</summary>
    public static async Task SendAsync(WebSocket socket, object message)
    {
        if (socket.State != WebSocketState.Open) return;
        var json = JsonSerializer.Serialize(message, JsonOpts);
        var bytes = Encoding.UTF8.GetBytes(json);
        await socket.SendAsync(new ArraySegment<byte>(bytes),
            WebSocketMessageType.Text, true, CancellationToken.None);
    }
}

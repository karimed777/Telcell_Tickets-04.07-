import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/seating.dart';

/// Типы реалтайм-событий (совпадают с сообщениями WebSocket бэкенда).
enum SeatEventType { connected, reserved, released, sold, rejected }

class SeatEvent {
  final SeatEventType type;
  final String? seatId;
  final String? sessionId; // чтобы отличить свой резерв от чужого
  final String? error;
  const SeatEvent(this.type, {this.seatId, this.sessionId, this.error});
}

/// Абстракция реалтайм-канала выбора мест.
/// Реализации: [MockSeatingRealtime] (сейчас, без бэкенда) и — при подключении
/// реального бэкенда — WebSocket-клиент на /ws/events/{id}/seats.
abstract class SeatingRealtime {
  Stream<SeatEvent> get events;
  String get sessionId;

  void reserve(String seatId);
  void release(String seatId);
  void releaseAll();
  void keepalive();
  Future<void> close();
}

/// Реальный WebSocket-клиент к C# backend: /ws/events/{eventId}/seats.
///
/// Протокол (совпадает с Program.cs + SeatHub):
///   сервер → клиент:
///     { type: "connected",        sessionId }            — подтверждение подключения
///     { type: "seat_reserved",    seatId, sessionId }    — место зарезервировано (кем-то)
///     { type: "seat_released",    seatId }               — резерв снят
///     { type: "seat_sold",        seatId }               — место продано
///     { type: "reserve_rejected", seatId, error }        — отказ (занято / лимит 5 мест)
///     { type: "keepalive_ok" }                           — резерв продлён
///   клиент → сервер:
///     { type: "reserve",  seatId } / { type: "release", seatId } /
///     { type: "release" } (без seatId = снять все) / { type: "keepalive" }
///
/// SessionId генерируется на клиенте и передаётся в query — при
/// переподключении выбор мест сохраняется (сервер знает нашу сессию).
class WsSeatingRealtime implements SeatingRealtime {
  /// http(s)://host[:port] бэкенда — конвертируется в ws(s)://.
  final String baseUrl;
  final String eventId;

  /// Токен вошедшего пользователя (резервы пишутся с его userId).
  final String? authToken;

  final _ctrl = StreamController<SeatEvent>.broadcast();
  final String _sessionId;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _closed = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  WsSeatingRealtime({
    required this.baseUrl,
    required this.eventId,
    this.authToken,
    String? sessionId,
  }) : _sessionId = sessionId ??
            '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(0xFFFFFF)}' {
    _connect();
  }

  Uri get _wsUri {
    final ws = baseUrl
        .replaceFirst(RegExp('^https'), 'wss')
        .replaceFirst(RegExp('^http'), 'ws');
    final q = <String, String>{'sessionId': _sessionId};
    if (authToken != null && authToken!.isNotEmpty) q['token'] = authToken!;
    return Uri.parse('$ws/ws/events/$eventId/seats').replace(queryParameters: q);
  }

  void _connect() {
    if (_closed) return;
    try {
      _channel = WebSocketChannel.connect(_wsUri);
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _sub?.cancel();
    _sub = null;
    _channel = null;
    // Экспоненциальная задержка: 1с, 2с, 4с … максимум 15с.
    final delay = Duration(seconds: min(15, 1 << min(_reconnectAttempt, 4)));
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connect);
  }

  void _onMessage(dynamic raw) {
    _reconnectAttempt = 0; // соединение живое
    Map<String, dynamic> j;
    try {
      j = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final seatId = j['seatId']?.toString();
    switch (j['type'] as String?) {
      case 'connected':
        _ctrl.add(SeatEvent(SeatEventType.connected, sessionId: _sessionId));
        break;
      case 'seat_reserved':
        _ctrl.add(SeatEvent(SeatEventType.reserved,
            seatId: seatId, sessionId: j['sessionId']?.toString()));
        break;
      case 'seat_released':
        _ctrl.add(SeatEvent(SeatEventType.released, seatId: seatId));
        break;
      case 'seat_sold':
        _ctrl.add(SeatEvent(SeatEventType.sold, seatId: seatId));
        break;
      case 'reserve_rejected':
        _ctrl.add(SeatEvent(SeatEventType.rejected,
            seatId: seatId, error: j['error']?.toString()));
        break;
      case 'keepalive_ok':
        break; // резерв продлён — UI-реакции не требуется
    }
  }

  void _send(Map<String, dynamic> msg) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode(msg));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  @override
  Stream<SeatEvent> get events => _ctrl.stream;

  @override
  String get sessionId => _sessionId;

  @override
  void reserve(String seatId) => _send({'type': 'reserve', 'seatId': seatId});

  @override
  void release(String seatId) => _send({'type': 'release', 'seatId': seatId});

  @override
  void releaseAll() => _send({'type': 'release'}); // без seatId = снять все

  @override
  void keepalive() => _send({'type': 'keepalive'});

  @override
  Future<void> close() async {
    _closed = true;
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    await _ctrl.close();
  }
}

/// Мок-реализация: эмулирует WebSocket через Timer.
/// Каждые 8 секунд случайное свободное место становится Reserved (голубая
/// обводка) на 10 секунд, затем снова Available — чтобы тестировать реалтайм
/// визуал без бэкенда.
class MockSeatingRealtime implements SeatingRealtime {
  static const int maxSeats = 5;
  static const String _me = 'me';
  static const String _other = 'other';

  final SeatingLayout layout;
  final _ctrl = StreamController<SeatEvent>.broadcast();
  final _mine = <String>{};
  final _reservedByOther = <String>{};
  final _rnd = Random();
  Timer? _timer;

  MockSeatingRealtime(this.layout) {
    // Первый тик — «подключились».
    Future<void>.microtask(() => _ctrl.add(const SeatEvent(SeatEventType.connected, sessionId: _me)));
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _emulateOther());
  }

  @override
  Stream<SeatEvent> get events => _ctrl.stream;

  @override
  String get sessionId => _me;

  List<SeatModel> get _freeSeats => layout.floors
      .expand((f) => f.allSeats)
      .where((s) =>
          s.state == SeatState.available &&
          !_mine.contains(s.id) &&
          !_reservedByOther.contains(s.id))
      .toList();

  void _emulateOther() {
    final free = _freeSeats;
    if (free.isEmpty) return;
    final seat = free[_rnd.nextInt(free.length)];
    _reservedByOther.add(seat.id);
    _ctrl.add(SeatEvent(SeatEventType.reserved, seatId: seat.id, sessionId: _other));
    Timer(const Duration(seconds: 10), () {
      if (_reservedByOther.remove(seat.id)) {
        _ctrl.add(SeatEvent(SeatEventType.released, seatId: seat.id));
      }
    });
  }

  @override
  void reserve(String seatId) {
    if (_mine.length >= maxSeats) {
      _ctrl.add(SeatEvent(SeatEventType.rejected, seatId: seatId, error: 'Нельзя выбрать больше $maxSeats мест'));
      return;
    }
    final seat = layout.findSeat(seatId);
    if (seat == null || seat.state == SeatState.sold || _reservedByOther.contains(seatId)) {
      _ctrl.add(SeatEvent(SeatEventType.rejected, seatId: seatId, error: 'Место недоступно'));
      return;
    }
    _mine.add(seatId);
    _ctrl.add(SeatEvent(SeatEventType.reserved, seatId: seatId, sessionId: _me));
  }

  @override
  void release(String seatId) {
    if (_mine.remove(seatId)) {
      _ctrl.add(SeatEvent(SeatEventType.released, seatId: seatId));
    }
  }

  @override
  void releaseAll() {
    final ids = _mine.toList();
    _mine.clear();
    for (final id in ids) {
      _ctrl.add(SeatEvent(SeatEventType.released, seatId: id));
    }
  }

  @override
  void keepalive() {/* в моке резерв не истекает — no-op */}

  @override
  Future<void> close() async {
    _timer?.cancel();
    await _ctrl.close();
  }
}

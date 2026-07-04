import 'dart:async';
import 'dart:math';

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

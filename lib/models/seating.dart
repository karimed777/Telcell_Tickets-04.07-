import 'package:flutter/material.dart';

/// Тип кресла (форма отрисовки + семантика). Совпадает с backend SeatType.
enum SeatKind { standard, vip, sofa, standing, disabled }

SeatKind seatKindFromString(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'vip':
      return SeatKind.vip;
    case 'sofa':
      return SeatKind.sofa;
    case 'standing':
      return SeatKind.standing;
    case 'disabled':
      return SeatKind.disabled;
    default:
      return SeatKind.standard;
  }
}

extension SeatKindX on SeatKind {
  /// Русское название для попапа информации о месте.
  String get ru {
    switch (this) {
      case SeatKind.standard:
        return 'Стандарт';
      case SeatKind.vip:
        return 'VIP';
      case SeatKind.sofa:
        return 'Диван';
      case SeatKind.standing:
        return 'Стоячее';
      case SeatKind.disabled:
        return 'Место для инвалида';
    }
  }
}

/// Реалтайм-статус места (с сервера). Совпадает с backend SeatStatus.
enum SeatState { available, reserved, sold }

SeatState seatStateFromString(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'reserved':
      return SeatState.reserved;
    case 'sold':
      return SeatState.sold;
    default:
      return SeatState.available;
  }
}

Color hexColor(String? hex) {
  var h = (hex ?? '#6C63FF').replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFF6C63FF);
}

/// Отдельное место.
class SeatModel {
  final String id;
  final int row;
  final int number;
  final SeatKind kind;
  final int price; // в драмах
  final String? description;
  final Color color;
  final double x; // абсолютные координаты на холсте
  final double y;

  /// Серверный статус (available/reserved/sold). Изменяется по WebSocket.
  SeatState state;

  SeatModel({
    required this.id,
    required this.row,
    required this.number,
    required this.kind,
    required this.price,
    this.description,
    required this.color,
    required this.x,
    required this.y,
    this.state = SeatState.available,
  });

  factory SeatModel.fromJson(Map<String, dynamic> j) => SeatModel(
        id: j['id'].toString(),
        row: (j['row'] ?? 0) as int,
        number: (j['number'] ?? 0) as int,
        kind: seatKindFromString(j['seatType'] as String?),
        price: ((j['price'] ?? 0) as num).toInt(),
        description: j['description'] as String?,
        color: hexColor(j['color'] as String?),
        x: ((j['canvasX'] ?? 0) as num).toDouble(),
        y: ((j['canvasY'] ?? 0) as num).toDouble(),
        state: seatStateFromString(j['status'] as String?),
      );
}

/// Блок кресел (нужен угол поворота для отрисовки).
class SeatBlockModel {
  final String id;
  final SeatKind kind;
  final double rotationDeg;
  final List<SeatModel> seats;

  SeatBlockModel({
    required this.id,
    required this.kind,
    required this.rotationDeg,
    required this.seats,
  });

  factory SeatBlockModel.fromJson(Map<String, dynamic> j) => SeatBlockModel(
        id: j['id'].toString(),
        kind: seatKindFromString(j['seatType'] as String?),
        rotationDeg: ((j['rotationDeg'] ?? 0) as num).toDouble(),
        seats: ((j['seats'] ?? []) as List)
            .map((s) => SeatModel.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

/// Сцена/экран на этаже.
class StageModel {
  final double x, y, width, height;
  final String label;
  StageModel({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.label,
  });

  factory StageModel.fromJson(Map<String, dynamic> j) => StageModel(
        x: ((j['canvasX'] ?? 0) as num).toDouble(),
        y: ((j['canvasY'] ?? 0) as num).toDouble(),
        width: ((j['width'] ?? 240) as num).toDouble(),
        height: ((j['height'] ?? 64) as num).toDouble(),
        label: (j['label'] ?? 'СЦЕНА') as String,
      );
}

/// Этаж/уровень.
class FloorModel {
  final String id;
  final String name;
  final int order;
  final StageModel? stage;
  final List<SeatBlockModel> blocks;

  FloorModel({
    required this.id,
    required this.name,
    required this.order,
    this.stage,
    required this.blocks,
  });

  factory FloorModel.fromJson(Map<String, dynamic> j) => FloorModel(
        id: j['id'].toString(),
        name: (j['name'] ?? '') as String,
        order: (j['order'] ?? 0) as int,
        stage: j['stage'] == null
            ? null
            : StageModel.fromJson(j['stage'] as Map<String, dynamic>),
        blocks: ((j['seatBlocks'] ?? []) as List)
            .map((b) => SeatBlockModel.fromJson(b as Map<String, dynamic>))
            .toList(),
      );

  /// Все активные места этажа (для быстрого поиска по id).
  Iterable<SeatModel> get allSeats => blocks.expand((b) => b.seats);
}

/// Схема мероприятия.
class SeatingLayout {
  final String eventId;
  final bool hasSeatingPlan;
  final List<FloorModel> floors;

  SeatingLayout({
    required this.eventId,
    required this.hasSeatingPlan,
    required this.floors,
  });

  factory SeatingLayout.fromJson(Map<String, dynamic> j) => SeatingLayout(
        eventId: j['eventId'].toString(),
        hasSeatingPlan: (j['hasSeatingPlan'] ?? false) as bool,
        floors: ((j['floors'] ?? []) as List)
            .map((f) => FloorModel.fromJson(f as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order)),
      );

  SeatModel? findSeat(String id) {
    for (final f in floors) {
      for (final s in f.allSeats) {
        if (s.id == id) return s;
      }
    }
    return null;
  }
}

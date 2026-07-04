import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/seating.dart';
import '../services/seating_realtime.dart';
import '../services/tickets_api.dart';
import '../theme/app_theme.dart';
import 'checkout_screen.dart';

/// Экран выбора мест по схеме зала (PRD-схема залов, часть 4.2).
class SeatingPlanScreen extends StatefulWidget {
  final Event event;
  final SeatingLayout layout;
  const SeatingPlanScreen({super.key, required this.event, required this.layout});

  @override
  State<SeatingPlanScreen> createState() => _SeatingPlanScreenState();
}

class _SeatingPlanScreenState extends State<SeatingPlanScreen>
    with SingleTickerProviderStateMixin {
  late final SeatingRealtime _rt;
  late final TabController _tabs;
  StreamSubscription<SeatEvent>? _sub;

  /// Мои выбранные места (розовая обводка).
  final Set<String> _mine = {};

  /// Зарезервированы другими (голубая обводка).
  final Set<String> _others = {};

  Timer? _continueTimer; // диалог «продолжаем?» каждые 5 минут

  SeatingLayout get layout => widget.layout;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: layout.floors.length, vsync: this);
    _rt = Api.instance.openSeating(layout, widget.event.id);
    _sub = _rt.events.listen(_onEvent);
    _continueTimer = Timer.periodic(const Duration(minutes: 5), (_) => _askContinue());
  }

  @override
  void dispose() {
    _continueTimer?.cancel();
    _sub?.cancel();
    _rt.close();
    _tabs.dispose();
    super.dispose();
  }

  void _onEvent(SeatEvent e) {
    if (!mounted) return;
    setState(() {
      switch (e.type) {
        case SeatEventType.reserved:
          if (e.seatId == null) break;
          if (e.sessionId == _rt.sessionId) {
            _mine.add(e.seatId!);
          } else {
            _others.add(e.seatId!);
          }
          break;
        case SeatEventType.released:
          if (e.seatId != null) {
            _mine.remove(e.seatId);
            _others.remove(e.seatId);
          }
          break;
        case SeatEventType.sold:
          final s = layout.findSeat(e.seatId ?? '');
          if (s != null) s.state = SeatState.sold;
          _mine.remove(e.seatId);
          _others.remove(e.seatId);
          break;
        case SeatEventType.rejected:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.error ?? 'Место недоступно')),
          );
          break;
        case SeatEventType.connected:
          break;
      }
    });
  }

  int get _total {
    var sum = 0;
    for (final id in _mine) {
      final s = layout.findSeat(id);
      if (s != null) sum += s.price;
    }
    return sum;
  }

  List<SeatModel> get _selectedSeats =>
      _mine.map((id) => layout.findSeat(id)).whereType<SeatModel>().toList();

  void _onSeatTap(SeatModel seat) {
    if (seat.state == SeatState.sold) return;
    if (_others.contains(seat.id)) return; // занято другим
    _showSeatSheet(seat);
  }

  void _showSeatSheet(SeatModel seat) {
    final selected = _mine.contains(seat.id);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('Ряд ${seat.row}, Место ${seat.number}',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(seat.kind.ru,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSecondary,
                )),
            if ((seat.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(seat.description!,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),
            Text('${money(seat.price)} ֏',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(color: AppColors.orange)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: selected
                  ? OutlinedButton(
                      onPressed: () {
                        _rt.release(seat.id);
                        setState(() => _mine.remove(seat.id));
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Убрать'),
                    )
                  : ElevatedButton(
                      onPressed: () {
                        if (_mine.length >= MockSeatingRealtime.maxSeats) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Нельзя выбрать больше 5 мест')),
                          );
                          return;
                        }
                        _rt.reserve(seat.id);
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Добавить'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Диалог «Продолжаем выбор?» — каждые 5 минут.
  void _askContinue() {
    if (!mounted || _mine.isEmpty) return;
    Timer? auto;
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
      ),
      builder: (ctx) {
        // 20 секунд без реакции → сброс мест.
        auto = Timer(const Duration(seconds: 20), () {
          _rt.releaseAll();
          setState(_mine.clear);
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Места сброшены, выберите снова')),
          );
        });
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Вы всё ещё выбираете места?',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () { auto?.cancel(); _rt.keepalive(); Navigator.of(ctx).pop(); },
                  child: const Text('Да, продолжаем'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    auto?.cancel();
                    _rt.releaseAll();
                    setState(_mine.clear);
                    Navigator.of(ctx).pop(); // закрыть диалог
                    Navigator.of(context).pop(); // закрыть экран
                  },
                  child: const Text('Отменить выбор'),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() => auto?.cancel());
  }

  void _goToCheckout() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CheckoutScreen(
        event: widget.event,
        quantities: const {},
        selectedSeats: _selectedSeats,
        seatSessionId: _rt.sessionId,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121F),
        foregroundColor: Colors.white,
        title: Text(widget.event.title,
            style: const TextStyle(color: Colors.white, fontFamily: AppTheme.fontFamily, fontSize: 16, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: AppColors.orange,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: [for (final f in layout.floors) Tab(text: f.name)],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final f in layout.floors)
            _FloorView(
              floor: f,
              mine: _mine,
              others: _others,
              onSeatTap: _onSeatTap,
            ),
        ],
      ),
      bottomNavigationBar: _SeatingBottomBar(
        count: _mine.length,
        total: _total,
        onPay: _mine.isEmpty ? null : _goToCheckout,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Холст одного этажа: InteractiveViewer + CustomPaint + хит-тест по тапу
// ══════════════════════════════════════════════════════════════════════════
class _FloorView extends StatefulWidget {
  final FloorModel floor;
  final Set<String> mine;
  final Set<String> others;
  final void Function(SeatModel) onSeatTap;
  const _FloorView({
    required this.floor,
    required this.mine,
    required this.others,
    required this.onSeatTap,
  });

  @override
  State<_FloorView> createState() => _FloorViewState();
}

class _FloorViewState extends State<_FloorView> {
  final _controller = TransformationController();
  static const double _pad = 60;
  late final Rect _bounds = _computeBounds();

  Rect _computeBounds() {
    double minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    void ext(double x, double y, double w, double h) {
      minX = math.min(minX, x - w / 2); maxX = math.max(maxX, x + w / 2);
      minY = math.min(minY, y - h / 2); maxY = math.max(maxY, y + h / 2);
    }
    final st = widget.floor.stage;
    if (st != null) ext(st.x, st.y, st.width, st.height);
    for (final b in widget.floor.blocks) {
      for (final s in b.seats) ext(s.x, s.y, 36, 36);
    }
    if (minX == double.infinity) return const Rect.fromLTWH(0, 0, 400, 400);
    return Rect.fromLTRB(minX - _pad, minY - _pad, maxX + _pad, maxY + _pad);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Offset _toCanvas(double wx, double wy) => Offset(wx - _bounds.left, wy - _bounds.top);

  void _handleTap(Offset local) {
    // local — в координатах canvas-ребёнка (InteractiveViewer уже размапил трансформ).
    for (final b in widget.floor.blocks) {
      final a = -b.rotationDeg * math.pi / 180;
      final cosA = math.cos(a), sinA = math.sin(a);
      for (final s in b.seats) {
        final c = _toCanvas(s.x, s.y);
        final dx = local.dx - c.dx, dy = local.dy - c.dy;
        final lx = dx * cosA - dy * sinA;
        final ly = dx * sinA + dy * cosA;
        if (lx.abs() <= 20 && ly.abs() <= 20) {
          widget.onSeatTap(s);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canvasSize = _bounds.size;
    return LayoutBuilder(builder: (context, box) {
      final fit = math.min(box.maxWidth / canvasSize.width, box.maxHeight / canvasSize.height);
      // Центрируем и вписываем при первом кадре.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.value == Matrix4.identity()) {
          final tx = (box.maxWidth - canvasSize.width * fit) / 2;
          final ty = (box.maxHeight - canvasSize.height * fit) / 2;
          _controller.value = Matrix4.identity()
            ..translate(tx, ty)
            ..scale(fit);
        }
      });

      return Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: 0.3,
              maxScale: 4,
              boundaryMargin: const EdgeInsets.all(400),
              child: SizedBox(
                width: canvasSize.width,
                height: canvasSize.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _handleTap(d.localPosition),
                  child: CustomPaint(
                    painter: _SeatingPainter(
                      floor: widget.floor,
                      origin: _bounds.topLeft,
                      mine: widget.mine,
                      others: widget.others,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Кнопки зума
          Positioned(
            right: 12, bottom: 12,
            child: Column(children: [
              _zoomBtn(Icons.add, () => _zoom(1.25)),
              const SizedBox(height: 8),
              _zoomBtn(Icons.remove, () => _zoom(0.8)),
              const SizedBox(height: 8),
              _zoomBtn(Icons.fit_screen_outlined, () {
                final fit2 = math.min(box.maxWidth / canvasSize.width, box.maxHeight / canvasSize.height);
                final tx = (box.maxWidth - canvasSize.width * fit2) / 2;
                final ty = (box.maxHeight - canvasSize.height * fit2) / 2;
                _controller.value = Matrix4.identity()..translate(tx, ty)..scale(fit2);
              }),
            ]),
          ),
        ],
      );
    });
  }

  void _zoom(double factor) {
    final m = _controller.value.clone()..scale(factor);
    _controller.value = m;
  }

  Widget _zoomBtn(IconData icon, VoidCallback onTap) => Material(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 40, height: 40, child: Icon(icon, color: Colors.white, size: 20)),
        ),
      );
}

// ── Отрисовка мест и сцены (вид сверху) ──────────────────────────────────
class _SeatingPainter extends CustomPainter {
  final FloorModel floor;
  final Offset origin; // мировые координаты левого-верхнего угла canvas
  final Set<String> mine;
  final Set<String> others;

  _SeatingPainter({
    required this.floor,
    required this.origin,
    required this.mine,
    required this.others,
  });

  Offset _c(double wx, double wy) => Offset(wx - origin.dx, wy - origin.dy);

  @override
  void paint(Canvas canvas, Size size) {
    // Сцена
    final st = floor.stage;
    if (st != null) {
      final c = _c(st.x, st.y);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: st.width, height: st.height),
        const Radius.circular(10),
      );
      canvas.drawRRect(rrect, Paint()..color = const Color(0xFF3A3A5C));
      final tp = TextPainter(
        text: TextSpan(text: st.label, style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w700, fontFamily: AppTheme.fontFamily)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }

    for (final b in floor.blocks) {
      for (final s in b.seats) {
        _drawSeat(canvas, s, b.rotationDeg);
      }
    }
  }

  void _drawSeat(Canvas canvas, SeatModel s, double rotationDeg) {
    final c = _c(s.x, s.y);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rotationDeg * math.pi / 180);

    final sold = s.state == SeatState.sold;
    final fill = Paint()..color = sold ? const Color(0xFF4A4A5A) : s.color;
    const half = 18.0;

    // обводка по состоянию выбора
    Paint? stroke;
    if (mine.contains(s.id)) {
      stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = const Color(0xFFFF4FA3);
    } else if (others.contains(s.id)) {
      stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = const Color(0xFF00D9FF);
    }

    void back(double x, double y, double w) {
      canvas.drawRect(Rect.fromLTWH(x, y - 3, w, 3), Paint()..color = Colors.black.withOpacity(0.25));
    }

    switch (s.kind) {
      case SeatKind.standing:
        canvas.drawCircle(Offset.zero, half * 0.9, fill);
        if (stroke != null) canvas.drawCircle(Offset.zero, half * 0.9 + 2, stroke);
        break;
      case SeatKind.sofa:
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 54, height: 30), const Radius.circular(6));
        canvas.drawRRect(r, fill);
        back(-27, -15, 54);
        if (stroke != null) canvas.drawRRect(r.inflate(2), stroke);
        break;
      case SeatKind.vip:
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 40, height: 32), const Radius.circular(6));
        canvas.drawRRect(r, fill);
        canvas.drawRect(Rect.fromLTWH(-24, -8, 3, 16), fill); // подлокотники
        canvas.drawRect(Rect.fromLTWH(21, -8, 3, 16), fill);
        back(-20, -16, 40);
        if (stroke != null) canvas.drawRRect(r.inflate(3), stroke);
        break;
      case SeatKind.disabled:
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 32, height: 32), const Radius.circular(6));
        canvas.drawRRect(r, fill);
        final tp = TextPainter(
          text: const TextSpan(text: '♿', style: TextStyle(color: Colors.white, fontSize: 18)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, -Offset(tp.width / 2, tp.height / 2));
        if (stroke != null) canvas.drawRRect(r.inflate(3), stroke);
        break;
      case SeatKind.standard:
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 30, height: 28), const Radius.circular(6));
        canvas.drawRRect(r, fill);
        back(-15, -14, 30);
        if (stroke != null) canvas.drawRRect(r.inflate(3), stroke);
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SeatingPainter old) =>
      old.mine != mine || old.others != others || old.floor != floor;
}

// ── Нижняя панель: выбрано/итого + оплата ────────────────────────────────
class _SeatingBottomBar extends StatelessWidget {
  final int count;
  final int total;
  final VoidCallback? onPay;
  const _SeatingBottomBar({required this.count, required this.total, this.onPay});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2A),
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Выбрано: $count мест',
                      style: const TextStyle(color: Colors.white70, fontFamily: AppTheme.fontFamily, fontSize: 12, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text('${money(total)} ֏',
                      style: const TextStyle(color: Colors.white, fontFamily: AppTheme.fontFamily, fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: onPay,
              child: const Text('Перейти к оплате'),
            ),
          ],
        ),
      ),
    );
  }
}

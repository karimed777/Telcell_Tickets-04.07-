import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_strings.dart';
import '../models/event.dart';
import '../models/seating.dart';
import '../services/session.dart';
import '../services/tickets_api.dart';
import '../theme/app_theme.dart';
import '../widgets/event_cover.dart';
import '../widgets/language_pill.dart';
import '../widgets/purchase_widgets.dart';
import 'auth_screen.dart';
import 'checkout_screen.dart';
import 'seating_plan_screen.dart';

/// Экран события — стиль Telcell Wallet.
/// Здесь же, под описанием, покупатель выбирает тип билета и количество,
/// а затем переходит к оплате (CheckoutScreen).
class EventDetailsScreen extends StatefulWidget {
  final Event event;
  const EventDetailsScreen({super.key, required this.event});

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  final Map<String, int> _qty = {};

  /// Схема зала события (если есть). Загружается асинхронно.
  SeatingLayout? _layout;

  Event get event => widget.event;

  bool get _hasSeatingPlan => _layout?.hasSeatingPlan == true;

  @override
  void initState() {
    super.initState();
    for (final tt in event.ticketTypes) {
      _qty[tt.name] = 0;
    }
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    try {
      final l = await Api.instance.getEventLayout(event.id);
      if (mounted && l != null) setState(() => _layout = l);
    } catch (_) {/* нет схемы — остаёмся на плюсиках */}
  }

  /// Выбор мест доступен ТОЛЬКО вошедшим пользователям (гость — нет).
  Future<void> _openSeatingPlan() async {
    if (!AppSession.instance.isLoggedIn) {
      final wantsLogin = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
        ),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded,
                  color: AppColors.indigo, size: 40),
              const SizedBox(height: 14),
              Text('Для выбора мест необходимо войти в аккаунт',
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Войти'),
                ),
              ),
            ],
          ),
        ),
      );
      if (wantsLogin != true || !mounted) return;

      // Открываем вход в режиме «вернуться после успеха».
      final loggedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AuthScreen(popOnSuccess: true)),
      );
      if (loggedIn != true || !mounted) return;
    }

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SeatingPlanScreen(event: event, layout: _layout!),
    ));
  }

  int get _total {
    int sum = 0;
    for (final tt in event.ticketTypes) {
      sum += tt.price * (_qty[tt.name] ?? 0);
    }
    return sum;
  }

  int get _count => _qty.values.fold(0, (a, b) => a + b);

  void _goToPayment() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CheckoutScreen(event: event, quantities: Map.from(_qty)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocale.stringsOf(context);
    final isAm = AppLocale.of(context).language == AppLanguage.am;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: darkBgOverlay,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 260,
              pinned: true,
              backgroundColor: AppColors.background,
              systemOverlayStyle: darkBgOverlay,
              leading: _CircleBackBtn(),
              actions: [
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Center(child: LanguagePill()),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _CircleIconBtn(Icons.share_outlined),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    EventCover(event: event, iconSize: 50),
                    // Низ-фейд
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              AppColors.background,
                            ],
                            stops: const [0.6, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Категория
                    Positioned(
                      bottom: 16, left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.orange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          t.category(event.category.key),
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(event.getTitle(isAm),
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 14),
                  // Мета-чипы
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      _MetaChip(Icons.schedule_outlined, event.dateLabel),
                      _MetaChip(Icons.place_outlined,
                          '${event.getVenue(isAm)}, ${event.city}'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  // Описание
                  Text(t.aboutEvent,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(event.getDescription(isAm),
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 22),
                  // Выбор билетов (тип/место + количество)
                  Text(t.selectTickets,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  if (_hasSeatingPlan)
                    _SeatingPlanCta(onTap: _openSeatingPlan)
                  else
                    for (final tt in event.ticketTypes) ...[
                      TicketCounter(
                        tt: tt,
                        qty: _qty[tt.name] ?? 0,
                        onChange: (v) => setState(() => _qty[tt.name] = v),
                      ),
                      const SizedBox(height: 10),
                    ],
                ]),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _hasSeatingPlan
            ? _SeatingPlanBar(onTap: _openSeatingPlan, fromLabel: event.priceLabel)
            : _BuyBar(
                total: _total,
                count: _count,
                fromLabel: event.priceLabel,
                onPay: _total > 0 ? _goToPayment : null,
              ),
      ),
    );
  }
}

class _CircleBackBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.30),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_rounded,
              color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  const _CircleIconBtn(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.30),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.inkSecondary),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.inkPrimary,
              )),
        ],
      ),
    );
  }
}

/// Нижняя панель: сумма выбранного + переход к оплате.
class _BuyBar extends StatelessWidget {
  final int total;
  final int count;
  final String fromLabel;
  final VoidCallback? onPay;
  const _BuyBar({
    required this.total,
    required this.count,
    required this.fromLabel,
    this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocale.stringsOf(context);
    final enabled = onPay != null;
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(enabled ? '$count · ${t.total.toLowerCase()}' : t.priceFrom,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 11,
                    color: AppColors.inkSecondary,
                  )),
              Text(enabled ? '${money(total)} ֏' : fromLabel,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.inkPrimary,
                  )),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: onPay,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      enabled ? AppColors.orange : AppColors.surfaceGray,
                ),
                child: Text(
                  enabled ? t.proceedToPay : t.selectTickets,
                  style: TextStyle(
                    color: enabled ? Colors.white : AppColors.inkSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточка-приглашение к выбору мест по схеме зала (в теле экрана).
class _SeatingPlanCta extends StatelessWidget {
  final VoidCallback onTap;
  const _SeatingPlanCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.indigoLight,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_seat_rounded, color: AppColors.indigo),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Выбор мест на схеме зала',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text('Откройте план зала и выберите места',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.inkSecondary),
          ],
        ),
      ),
    );
  }
}

/// Нижняя панель для событий со схемой зала — ведёт на экран выбора мест.
class _SeatingPlanBar extends StatelessWidget {
  final VoidCallback onTap;
  final String fromLabel;
  const _SeatingPlanBar({required this.onTap, required this.fromLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Цена',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 11,
                    color: AppColors.inkSecondary,
                  )),
              Text(fromLabel,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.inkPrimary,
                  )),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.event_seat_rounded, size: 18),
                label: const Text('Выбрать места'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

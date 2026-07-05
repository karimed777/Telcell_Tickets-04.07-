import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_api.dart';
import '../services/http_tickets_api.dart';
import '../services/session.dart';
import '../services/tickets_api.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_shapes.dart';
import 'home_shell.dart';

/// Экран авторизации Telcell Tickets.
///
/// Две вкладки:
///  • «Регистрация» — имя + телефон + email, один код подтверждения
///    отправляется и на телефон, и на почту (пока демо-режим);
///  • «Вход» — выбор способа (телефон или email), туда приходит код.
///
/// После успеха сессия сохраняется в [AppSession] и открывается каталог
/// (либо экран закрывается с результатом true, если [popOnSuccess]).
class AuthScreen extends StatefulWidget {
  /// true — после успешного входа закрыть экран с результатом true
  /// (возврат в поток покупки), вместо перехода на главную.
  final bool popOnSuccess;

  const AuthScreen({super.key, this.popOnSuccess = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  int _tab = 0; // 0 — регистрация, 1 — вход

  void _onSuccess() {
    if (widget.popOnSuccess) {
      Navigator.of(context).pop(true);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: lightBgOverlay,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: [
              // ── Фирменная шапка ──
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.indigo,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Center(child: BrandMark(size: 32)),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Telcell Tickets',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AppColors.inkPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _tab == 0
                    ? 'Создайте профиль, чтобы покупать\nи хранить билеты'
                    : 'Войдите, чтобы вернуться\nк своим билетам',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // ── Переключатель Регистрация / Вход ──
              _PillTabs(
                index: _tab,
                labels: const ['Регистрация', 'Вход'],
                onChanged: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 24),

              if (_tab == 0)
                _RegisterForm(onSuccess: _onSuccess)
              else
                _LoginForm(onSuccess: _onSuccess),
            ],
          ),
        ),
      ),
    );
  }
}

/// ══════════════════════════════════════════════════════════════════════════
/// Переключатель-«пилюля» в стиле Telcell Wallet.
/// ══════════════════════════════════════════════════════════════════════════
class _PillTabs extends StatelessWidget {
  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  const _PillTabs({
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = i == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: selected ? AppColors.orange : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.inkSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// ══════════════════════════════════════════════════════════════════════════
/// Регистрация: имя + телефон + email → один код (демо) → профиль создан.
/// ══════════════════════════════════════════════════════════════════════════
class _RegisterForm extends StatefulWidget {
  final VoidCallback onSuccess;
  const _RegisterForm({required this.onSuccess});

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _loading = false;
  bool _codeSent = false;
  String? _error;
  String? _devCode;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_nameCtrl.text.trim().length < 2) {
      return 'Укажите имя (минимум 2 символа)';
    }
    final phone = _phoneCtrl.text.trim().replaceAll(RegExp(r'[\s\-]'), '');
    if (phone.length < 6 || !RegExp(r'^\+?\d+$').hasMatch(phone)) {
      return 'Укажите корректный номер телефона';
    }
    final email = _emailCtrl.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Укажите корректный email';
    }
    return null;
  }

  Future<void> _sendCode() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await Auth.instance.register(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _devCode = code;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = extractAuthError(e.toString());
      });
    }
  }

  Future<void> _verify() async {
    if (_codeCtrl.text.trim().length < 4) {
      setState(() => _error = 'Введите код подтверждения');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Auth.instance.verifyLoginCode(
        contact: _phoneCtrl.text.trim(),
        code: _codeCtrl.text.trim(),
      );
      await _applySession(result, fallbackEmail: _emailCtrl.text.trim());
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = extractAuthError(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_codeSent) {
      return _CodeStep(
        message:
            'Мы отправили код подтверждения на телефон\n${_phoneCtrl.text.trim()} и почту ${_emailCtrl.text.trim()}',
        codeCtrl: _codeCtrl,
        devCode: _devCode,
        loading: _loading,
        error: _error,
        buttonLabel: 'Подтвердить и создать профиль',
        onSubmit: _verify,
        onBack: () => setState(() {
          _codeSent = false;
          _codeCtrl.clear();
          _error = null;
        }),
        onChanged: () => setState(() {}),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameCtrl,
          enabled: !_loading,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Имя',
            prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          enabled: !_loading,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: 'Телефон (+374 ...)',
            prefixIcon: Icon(Icons.phone_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailCtrl,
          enabled: !_loading,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'Email',
            prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Один код подтверждения придёт и в SMS, и на почту.',
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 12,
            color: AppColors.inkSecondary,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorText(_error!),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _loading ? null : _sendCode,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text('Получить код'),
          ),
        ),
      ],
    );
  }
}

/// ══════════════════════════════════════════════════════════════════════════
/// Вход: выбор способа (телефон / email) → контакт → код.
/// ══════════════════════════════════════════════════════════════════════════
class _LoginForm extends StatefulWidget {
  final VoidCallback onSuccess;
  const _LoginForm({required this.onSuccess});

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _contactCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  int _method = 0; // 0 — телефон, 1 — email
  bool _loading = false;
  bool _codeSent = false;
  String? _error;
  String? _devCode;

  @override
  void dispose() {
    _contactCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  bool get _byPhone => _method == 0;

  String? _validate() {
    final c = _contactCtrl.text.trim();
    if (_byPhone) {
      final phone = c.replaceAll(RegExp(r'[\s\-]'), '');
      if (phone.length < 6 || !RegExp(r'^\+?\d+$').hasMatch(phone)) {
        return 'Укажите корректный номер телефона';
      }
    } else {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(c)) {
        return 'Укажите корректный email';
      }
    }
    return null;
  }

  Future<void> _sendCode() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await Auth.instance.requestLoginCode(
        contact: _contactCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _devCode = code;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = extractAuthError(e.toString());
      });
    }
  }

  Future<void> _verify() async {
    if (_codeCtrl.text.trim().length < 4) {
      setState(() => _error = 'Введите код подтверждения');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Auth.instance.verifyLoginCode(
        contact: _contactCtrl.text.trim(),
        code: _codeCtrl.text.trim(),
      );
      await _applySession(result);
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = extractAuthError(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_codeSent) {
      return _CodeStep(
        message: _byPhone
            ? 'Мы отправили код в SMS на номер\n${_contactCtrl.text.trim()}'
            : 'Мы отправили код на почту\n${_contactCtrl.text.trim()}',
        codeCtrl: _codeCtrl,
        devCode: _devCode,
        loading: _loading,
        error: _error,
        buttonLabel: 'Войти',
        onSubmit: _verify,
        onBack: () => setState(() {
          _codeSent = false;
          _codeCtrl.clear();
          _error = null;
        }),
        onChanged: () => setState(() {}),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Выбор способа входа
        Row(
          children: [
            Expanded(
              child: _MethodChip(
                icon: Icons.phone_outlined,
                label: 'По телефону',
                selected: _byPhone,
                onTap: () => setState(() {
                  _method = 0;
                  _error = null;
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MethodChip(
                icon: Icons.alternate_email_rounded,
                label: 'По email',
                selected: !_byPhone,
                onTap: () => setState(() {
                  _method = 1;
                  _error = null;
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _contactCtrl,
          enabled: !_loading,
          keyboardType:
              _byPhone ? TextInputType.phone : TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: _byPhone ? 'Телефон (+374 ...)' : 'Email',
            prefixIcon: Icon(
              _byPhone ? Icons.phone_outlined : Icons.alternate_email_rounded,
              size: 18,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _byPhone
              ? 'Код подтверждения придёт в SMS.'
              : 'Код подтверждения придёт на почту.',
          style: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 12,
            color: AppColors.inkSecondary,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorText(_error!),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _loading ? null : _sendCode,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text('Получить код'),
          ),
        ),
      ],
    );
  }
}

/// Чип выбора способа входа (телефон / email).
class _MethodChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MethodChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 48,
        decoration: BoxDecoration(
          color: selected ? AppColors.orangeLight : AppColors.surfaceGray,
          borderRadius: BorderRadius.circular(AppRadii.input),
          border: Border.all(
            color: selected ? AppColors.orange : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: selected ? AppColors.orange : AppColors.inkSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.orange : AppColors.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Общий шаг ввода кода подтверждения.
class _CodeStep extends StatelessWidget {
  final String message;
  final TextEditingController codeCtrl;
  final String? devCode;
  final bool loading;
  final String? error;
  final String buttonLabel;
  final VoidCallback onSubmit;
  final VoidCallback onBack;
  final VoidCallback onChanged;

  const _CodeStep({
    required this.message,
    required this.codeCtrl,
    required this.devCode,
    required this.loading,
    required this.error,
    required this.buttonLabel,
    required this.onSubmit,
    required this.onBack,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.indigoLight,
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          child: Row(
            children: [
              const Icon(Icons.mark_email_read_outlined,
                  color: AppColors.indigo, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: AppColors.inkPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: codeCtrl,
          enabled: !loading,
          autofocus: true,
          keyboardType: TextInputType.number,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(
            hintText: 'Код подтверждения',
            prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
          ),
        ),
        if (devCode != null) ...[
          const SizedBox(height: 8),
          Text(
            'Демо-режим: код — $devCode',
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 12,
              color: AppColors.inkSecondary,
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          _ErrorText(error!),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: loading ? null : onSubmit,
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : Text(buttonLabel),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: loading ? null : onBack,
          child: const Text(
            'Назад',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String text;
  const _ErrorText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.error,
      ),
    );
  }
}

/// Сохраняет успешный вход: сессия + личность для API билетов.
Future<void> _applySession(AuthResult result, {String? fallbackEmail}) async {
  await AppSession.instance.signIn(
    token: result.token,
    phone: result.user.phone,
    name: result.user.name,
    email: (result.user.email?.isNotEmpty ?? false)
        ? result.user.email
        : fallbackEmail,
    isAdmin: result.user.isAdmin,
  );
  final api = Api.instance;
  if (api is HttpTicketsApi) {
    api.setIdentity(
      phone: result.user.phone,
      name: result.user.name,
      token: result.token,
    );
  }
  MockTicketsApi.registerKnownUser(result.user.phone, result.user.name);
}

/// Достаёт человекочитаемое сообщение из ошибки вида {"error": "..."}.
String extractAuthError(String raw) {
  final match = RegExp(r'\{[^}]*"error"[^}]*\}').firstMatch(raw);
  if (match != null) {
    try {
      final j = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      final msg = j['error'];
      if (msg is String && msg.isNotEmpty) return msg;
    } catch (_) {}
  }
  if (raw.contains('Connection refused') ||
      raw.contains('ERR_CONNECTION_REFUSED')) {
    return 'Не удалось подключиться к серверу';
  }
  if (raw.contains('SocketException') || raw.contains('Failed host lookup')) {
    return 'Проверьте подключение к интернету';
  }
  return 'Ошибка сети';
}

import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/auth_api.dart';
import '../services/session.dart';
import '../services/http_tickets_api.dart';
import '../services/tickets_api.dart';
import 'home_shell.dart';

/// Экран авторизации с вкладками "Регистрация" и "Вход"
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Добро пожаловать'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Регистрация'),
            Tab(text: 'Вход'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RegisterTab(onSuccess: _navigateToHome),
          _LoginTab(onSuccess: _navigateToHome),
        ],
      ),
    );
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
  }
}

/// Вкладка регистрации
class _RegisterTab extends StatefulWidget {
  final VoidCallback onSuccess;
  const _RegisterTab({required this.onSuccess});

  @override
  State<_RegisterTab> createState() => _RegisterTabState();
}

class _RegisterTabState extends State<_RegisterTab> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loading = false;
  bool _codeSent = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    // Валидация
    if (_nameController.text.trim().length < 2) {
      setState(() => _error = 'Укажите имя (минимум 2 символа)');
      return;
    }
    
    if (!_emailController.text.contains('@')) {
      setState(() => _error = 'Укажите корректный email');
      return;
    }
    
    final phone = _phoneController.text.trim().replaceAll(' ', '').replaceAll('-', '');
    if (phone.length < 6 || !RegExp(r'^\+?\d+$').hasMatch(phone)) {
      setState(() => _error = 'Укажите корректный номер телефона');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final code = await Auth.instance.register(
        name: _nameController.text,
        email: _emailController.text,
        phone: _phoneController.text,
      );
      
      setState(() {
        _codeSent = true;
        _loading = false;
      });

      if (code != null) {
        _codeController.text = code;
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = _extractError(e.toString());
      });
    }
  }

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await Auth.instance.verifyLoginCode(
        contact: _phoneController.text,
        code: _codeController.text,
      );

      await AppSession.instance.signIn(
        phone: result.user.phone,
        name: result.user.name,
        token: result.token,
        isAdmin: result.user.isAdmin,
      );

      if (Api.instance is HttpTicketsApi) {
        (Api.instance as HttpTicketsApi).setIdentity(
          phone: result.user.phone,
          name: result.user.name,
          token: result.token,
        );
      }

      widget.onSuccess();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = _extractError(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_codeSent) ...[
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Имя',
                border: OutlineInputBorder(),
              ),
              enabled: !_loading,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              enabled: !_loading,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Телефон',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              enabled: !_loading,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: _loading ? null : _register,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Зарегистрироваться'),
            ),
          ] else ...[
            const Text('Код отправлен на ваш телефон',
                style: TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Код подтверждения',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              enabled: !_loading,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: _loading ? null : _verify,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Подтвердить'),
            ),
          ],
        ],
      ),
    );
  }

  String _extractError(String raw) {
    // Пытаемся найти JSON с ошибкой
    final match = RegExp(r'\{[^}]*"error"[^}]*\}').firstMatch(raw);
    if (match != null) {
      try {
        final j = jsonDecode(match.group(0)!) as Map<String, dynamic>;
        return j['error'] as String? ?? 'Ошибка';
      } catch (_) {}
    }
    // Специфические ошибки
    if (raw.contains('Connection refused') || raw.contains('ERR_CONNECTION_REFUSED')) {
      return 'Не удалось подключиться к серверу';
    }
    if (raw.contains('SocketException') || raw.contains('Failed host lookup')) {
      return 'Проверьте подключение к интернету';
    }
    return 'Ошибка сети';
  }
}

/// Вкладка входа
class _LoginTab extends StatefulWidget {
  final VoidCallback onSuccess;
  const _LoginTab({required this.onSuccess});

  @override
  State<_LoginTab> createState() => _LoginTabState();
}

class _LoginTabState extends State<_LoginTab> {
  final _contactController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loading = false;
  bool _codeSent = false;
  String? _error;

  @override
  void dispose() {
    _contactController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final code = await Auth.instance.requestLoginCode(
        contact: _contactController.text,
      );

      setState(() {
        _codeSent = true;
        _loading = false;
      });

      if (code != null) {
        _codeController.text = code;
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = _extractError(e.toString());
      });
    }
  }

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await Auth.instance.verifyLoginCode(
        contact: _contactController.text,
        code: _codeController.text,
      );

      await AppSession.instance.signIn(
        phone: result.user.phone,
        name: result.user.name,
        token: result.token,
        isAdmin: result.user.isAdmin,
      );

      if (Api.instance is HttpTicketsApi) {
        (Api.instance as HttpTicketsApi).setIdentity(
          phone: result.user.phone,
          name: result.user.name,
          token: result.token,
        );
      }

      widget.onSuccess();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = _extractError(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_codeSent) ...[
            TextField(
              controller: _contactController,
              decoration: const InputDecoration(
                labelText: 'Email или телефон',
                border: OutlineInputBorder(),
              ),
              enabled: !_loading,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: _loading ? null : _requestCode,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Получить код'),
            ),
          ] else ...[
            const Text('Код отправлен', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Код подтверждения',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              enabled: !_loading,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: _loading ? null : _verify,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Войти'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _codeSent = false;
                  _codeController.clear();
                  _error = null;
                });
              },
              child: const Text('Назад'),
            ),
          ],
        ],
      ),
    );
  }

  String _extractError(String raw) {
    // Пытаемся найти JSON с ошибкой
    final match = RegExp(r'\{[^}]*"error"[^}]*\}').firstMatch(raw);
    if (match != null) {
      try {
        final j = jsonDecode(match.group(0)!) as Map<String, dynamic>;
        return j['error'] as String? ?? 'Ошибка';
      } catch (_) {}
    }
    // Специфические ошибки
    if (raw.contains('Connection refused') || raw.contains('ERR_CONNECTION_REFUSED')) {
      return 'Не удалось подключиться к серверу';
    }
    if (raw.contains('SocketException') || raw.contains('Failed host lookup')) {
      return 'Проверьте подключение к интернету';
    }
    return 'Ошибка сети';
  }
}

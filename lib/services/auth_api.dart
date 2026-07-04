import 'dart:convert';
import 'package:http/http.dart' as http;

/// Профиль пользователя, возвращаемый авторизацией.
class AuthUser {
  final String id;
  final String name;
  final String phone;
  final String? email;

  /// Признак администратора. true только для скрытого admin-входа
  /// (на backend — флаг AppUser.IsAdmin). Открывает админ-панель.
  final bool isAdmin;

  const AuthUser({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.isAdmin = false,
  });
}

/// Результат успешного входа: токен сессии + профиль.
class AuthResult {
  final String token;
  final AuthUser user;
  const AuthResult({required this.token, required this.user});
}

/// Контракт авторизации.
abstract class AuthApi {
  /// Регистрация нового пользователя
  Future<String?> register({
    required String name,
    required String email,
    required String phone,
  });

  /// Запрос кода для входа (email или телефон)
  Future<String?> requestLoginCode({required String contact});

  /// Проверка кода и вход
  Future<AuthResult> verifyLoginCode({
    required String contact,
    required String code,
  });

  /// Выход из аккаунта
  Future<void> logout({required String token});

  // Старые методы для совместимости
  Future<String?> requestOtp({required String phone, String? name});
  Future<AuthResult> verifyOtp({required String phone, required String code});
}

/// Демо-реализация: код всегда «0000».
class MockAuthApi implements AuthApi {
  static const _delay = Duration(milliseconds: 300);
  static const devCode = '0000';
  static const adminPhone = '+37400000000';
  static const adminCode = '9999';

  final Map<String, _MockUser> _users = {};
  final Map<String, String> _pending = {}; // contact -> code

  @override
  Future<String?> register({
    required String name,
    required String email,
    required String phone,
  }) async {
    await Future<void>.delayed(_delay);
    final p = _norm(phone);
    final e = email.trim().toLowerCase();

    if (_users.values.any((u) => u.phone == p)) {
      throw StateError(
          '{"error":"Пользователь с таким телефоном уже зарегистрирован."}');
    }
    if (_users.values.any((u) => u.email == e)) {
      throw StateError(
          '{"error":"Пользователь с таким email уже зарегистрирован."}');
    }

    final id = 'user-${DateTime.now().microsecondsSinceEpoch}';
    _users[id] = _MockUser(
        id: id, name: name.trim(), email: e, phone: p, isAdmin: false);
    return devCode;
  }

  @override
  Future<String?> requestLoginCode({required String contact}) async {
    await Future<void>.delayed(_delay);
    final c = contact.trim();
    final user = _users.values.firstWhere(
      (u) =>
          u.phone == _norm(c) ||
          (c.contains('@') && u.email == c.toLowerCase()),
      orElse: () => throw StateError(
          '{"error":"Пользователь с таким email или телефоном не найден."}'),
    );
    _pending[c] = devCode;
    return devCode;
  }

  @override
  Future<AuthResult> verifyLoginCode({
    required String contact,
    required String code,
  }) async {
    await Future<void>.delayed(_delay);
    final c = contact.trim();

    // Admin вход
    if (_norm(c) == adminPhone && code.trim() == adminCode) {
      final admin = _users.values
          .firstWhere((u) => u.phone == adminPhone, orElse: () {
        final id = 'admin-${DateTime.now().microsecondsSinceEpoch}';
        _users[id] = _MockUser(
            id: id,
            name: 'Администратор',
            email: '',
            phone: adminPhone,
            isAdmin: true);
        return _users[id]!;
      });
      return AuthResult(
        token: 'admin-${DateTime.now().microsecondsSinceEpoch}',
        user: AuthUser(
            id: admin.id,
            name: admin.name,
            phone: admin.phone,
            email: admin.email,
            isAdmin: true),
      );
    }

    if (_pending[c] != code.trim()) {
      throw StateError('{"error":"Неверный код."}');
    }

    final user = _users.values.firstWhere(
      (u) =>
          u.phone == _norm(c) ||
          (c.contains('@') && u.email == c.toLowerCase()),
    );
    _pending.remove(c);

    return AuthResult(
      token: 'mock-${DateTime.now().microsecondsSinceEpoch}',
      user: AuthUser(
          id: user.id,
          name: user.name,
          phone: user.phone,
          email: user.email,
          isAdmin: user.isAdmin),
    );
  }

  @override
  Future<void> logout({required String token}) async {
    await Future<void>.delayed(_delay);
  }

  @override
  Future<String?> requestOtp({required String phone, String? name}) async {
    await Future<void>.delayed(_delay);
    final p = _norm(phone);
    _pending[p] = (name ?? '').trim().isEmpty ? 'Гость' : name!.trim();
    if (p == adminPhone) return null;
    return devCode;
  }

  @override
  Future<AuthResult> verifyOtp({
    required String phone,
    required String code,
  }) async {
    await Future<void>.delayed(_delay);
    final p = _norm(phone);

    if (p == adminPhone) {
      if (code.trim() != adminCode) {
        throw StateError('{"error":"Неверный код."}');
      }
      return AuthResult(
        token: 'admin-${DateTime.now().microsecondsSinceEpoch}',
        user: AuthUser(
            id: 'admin-$p',
            name: 'Администратор',
            phone: p,
            isAdmin: true),
      );
    }

    if (code.trim() != devCode) {
      throw StateError('{"error":"Неверный код."}');
    }
    final name = _pending[p] ?? 'Гость';
    return AuthResult(
      token: 'mock-${DateTime.now().microsecondsSinceEpoch}',
      user: AuthUser(id: 'mock-$p', name: name, phone: p),
    );
  }

  static String _norm(String phone) => phone.trim().replaceAll(' ', '');
}

class _MockUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  final bool isAdmin;
  _MockUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.isAdmin,
  });
}

/// Реализация поверх C# backend.
class HttpAuthApi implements AuthApi {
  final String baseUrl;
  final http.Client _client;

  HttpAuthApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  @override
  Future<String?> register({
    required String name,
    required String email,
    required String phone,
  }) async {
    final res = await _client.post(
      _u('/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'displayName': name,
        'email': email,
        'phone': phone,
      }),
    );
    _ensureOk(res);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['devCode'] as String?;
  }

  @override
  Future<String?> requestLoginCode({required String contact}) async {
    final res = await _client.post(
      _u('/api/auth/login/request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'contact': contact}),
    );
    _ensureOk(res);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['devCode'] as String?;
  }

  @override
  Future<AuthResult> verifyLoginCode({
    required String contact,
    required String code,
  }) async {
    final res = await _client.post(
      _u('/api/auth/login/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'contact': contact, 'code': code}),
    );
    _ensureOk(res);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final u = j['user'] as Map<String, dynamic>;
    return AuthResult(
      token: j['token'] as String,
      user: AuthUser(
        id: u['id'] as String,
        name: u['displayName'] as String,
        phone: u['phone'] as String,
        email: u['email'] as String?,
        isAdmin: u['isAdmin'] as bool? ?? false,
      ),
    );
  }

  @override
  Future<void> logout({required String token}) async {
    await _client.post(
      _u('/api/auth/logout'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
  }

  @override
  Future<String?> requestOtp({required String phone, String? name}) async {
    final res = await _client.post(
      _u('/api/auth/request-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'displayName': name}),
    );
    _ensureOk(res);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['devCode'] as String?;
  }

  @override
  Future<AuthResult> verifyOtp({
    required String phone,
    required String code,
  }) async {
    final res = await _client.post(
      _u('/api/auth/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'code': code}),
    );
    _ensureOk(res);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final u = j['user'] as Map<String, dynamic>;
    return AuthResult(
      token: j['token'] as String,
      user: AuthUser(
        id: u['id'] as String,
        name: u['displayName'] as String,
        phone: u['phone'] as String,
        email: u['email'] as String?,
        isAdmin: u['isAdmin'] as bool? ?? false,
      ),
    );
  }

  void _ensureOk(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError(res.body);
    }
  }
}

/// Единая точка доступа к авторизации (как [Api] для билетов).
class Auth {
  Auth._();
  static AuthApi instance = MockAuthApi();
}

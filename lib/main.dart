import 'package:flutter/material.dart';
import 'l10n/app_strings.dart';
import 'theme/app_theme.dart';
import 'services/session.dart';
import 'services/http_tickets_api.dart';
import 'services/tickets_api.dart';
import 'services/auth_api.dart';
import 'services/notifications.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';

/// Источник данных приложения.
const bool kUseBackend = true;
const String kApiBaseUrl = 'http://localhost:5000';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kUseBackend) {
    Api.instance = HttpTicketsApi(baseUrl: kApiBaseUrl);
    Auth.instance = HttpAuthApi(baseUrl: kApiBaseUrl);
  }

  await AppSession.instance.load();
  await AppNotifications.instance.init();

  final api = Api.instance;
  if (api is HttpTicketsApi && AppSession.instance.isLoggedIn) {
    api.setIdentity(
      phone: AppSession.instance.phone,
      name: AppSession.instance.name,
      token: AppSession.instance.token,
    );
  }

  runApp(const TelcellTicketsApp());
}

class TelcellTicketsApp extends StatefulWidget {
  const TelcellTicketsApp({super.key});

  @override
  State<TelcellTicketsApp> createState() => _TelcellTicketsAppState();
}

class _TelcellTicketsAppState extends State<TelcellTicketsApp> {
  AppLanguage _lang = AppLanguage.ru;

  void _toggle() {
    setState(() {
      _lang = _lang == AppLanguage.ru ? AppLanguage.am : AppLanguage.ru;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget start = AppSession.instance.isLoggedIn
        ? const HomeShell()
        : const AuthScreen();

    return AppLocale(
      language: _lang,
      toggle: _toggle,
      child: MaterialApp(
        title: 'Telcell Tickets',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: start,
      ),
    );
  }
}

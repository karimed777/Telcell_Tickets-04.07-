import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_strings.dart';
import '../services/session.dart';
import '../services/auth_api.dart';
import '../services/http_tickets_api.dart';
import '../services/tickets_api.dart';
import '../theme/app_theme.dart';
import 'auth_screen.dart';

/// Страница профиля пользователя
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final token = AppSession.instance.token;
    if (token != null && token.isNotEmpty) {
      try {
        await Auth.instance.logout(token: token);
      } catch (_) {}
    }
    
    await AppSession.instance.signOut();
    final api = Api.instance;
    if (api is HttpTicketsApi) api.setIdentity(token: null);
    
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: lightBgOverlay,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Профиль'),
          centerTitle: false,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // Аватар
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              // Имя
              Text(
                session.name ?? 'Пользователь',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.inkPrimary,
                ),
              ),
              const SizedBox(height: 8),
              // Телефон
              if (session.phone != null)
                Text(
                  session.phone!,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.inkSecondary,
                  ),
                ),
              const SizedBox(height: 40),
              // Карточка с информацией
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _ProfileItem(
                      icon: Icons.person_outline_rounded,
                      title: 'Имя',
                      value: session.name ?? 'Не указано',
                    ),
                    const Divider(height: 1, indent: 60),
                    _ProfileItem(
                      icon: Icons.phone_outlined,
                      title: 'Телефон',
                      value: session.phone ?? 'Не указан',
                    ),
                    if (session.isAdmin) ...[
                      const Divider(height: 1, indent: 60),
                      _ProfileItem(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'Роль',
                        value: 'Администратор',
                        valueColor: AppColors.orange,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // Кнопка выхода
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => _signOut(context),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Выйти из аккаунта'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;

  const _ProfileItem({
    required this.icon,
    required this.title,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.orange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: AppColors.orange,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: valueColor ?? AppColors.inkPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

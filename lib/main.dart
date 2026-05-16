// lib/main.dart

import 'package:final_project/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_text.dart';
import 'core/supabase_config.dart';
import 'core/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/update_password_screen.dart';

void main() async {
  // 1. Requirement: Ensure Flutter framework and engine are initialized
  // This is critical for background SMS listeners and database operations
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Notification Service to handle transaction alerts
  await NotificationService().initNotification();

  // 3. Initialize Supabase before the app starts with your credentials
  // Ensure that these credentials remain valid in your Supabase project settings
  await SupabaseConfig.ensureInitialized();

  // 4. Load saved language before the first frame. The UI stays LTR globally.
  await AppText.init();

  // 5. SMS automation is started after login from Dashboard or Settings.
  runApp(const FinancialMindApp());
}

// The FinancialMindApp is the root widget of the application, responsible for setting up localization, theming, and routing.
class FinancialMindApp extends StatelessWidget {
  const FinancialMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppText.languageCode,
      builder: (context, languageCode, _) {
        return MaterialApp(
          title: 'Financial Mind',
          debugShowCheckedModeBanner: false,
          locale: Locale(languageCode),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            return AppLanguageScope(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },

          // Applying the professional dark theme (Neon Design System)
          theme: AppTheme.darkTheme,

          // Initial route shown to the user upon app launch
          home: const LoginScreen(),

          // Defining the app routes for structured navigation
          // These routes are crucial for moving between authentication and dashboard
          routes: {
            '/login': (context) => const LoginScreen(),
            '/register': (context) => const RegisterScreen(),
            '/dashboard': (context) => const DashboardScreen(),
            '/update-password': (context) => const UpdatePasswordScreen(),
          },
        );
      },
    );
  }
}

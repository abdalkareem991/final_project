import 'package:final_project/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  await Supabase.initialize(
    url: 'https://nkzcmxuthxwpgmhvnxcb.supabase.co',
    anonKey: 'sb_publishable_GaooL_VcN7UWg2HgPC2z9g_7v3Zb_en',
  );

  runApp(const FinancialMindApp());
}

class FinancialMindApp extends StatelessWidget {
  const FinancialMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Financial Mind',
      debugShowCheckedModeBanner: false,

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
  }
}

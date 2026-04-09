import 'package:final_project/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_theme.dart';
import 'screens/dashboard_screen.dart'; // Added dashboard screen
import 'screens/login_screen.dart';
import 'screens/register_screen.dart'; // Added registration screen
import 'screens/update_password_screen.dart';

void main() async {
  // Required to ensure Flutter framework is ready before initialization
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase before the app starts with your credentials
  await NotificationService().initNotification();

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

      // Applying the professional dark theme we designed
      theme: AppTheme.darkTheme,

      // Initial route shown to the user
      home: const LoginScreen(),

      // Defining the app routes for navigation
      // This is crucial for deep links and manual navigation
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/update-password': (context) => const UpdatePasswordScreen(),
      },
    );
  }
}

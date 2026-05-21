import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../services/supabase_service.dart';

class UpdatePasswordScreen extends StatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _newPasswordController = TextEditingController();
  final _supabaseService = SupabaseService();
  bool _isLoading = false;

  AppThemeColors get _colors => context.themeColors;
  Color get _bgColor => _colors.background;
  Color get _textColor => _colors.textPrimary;
  Color get _mutedTextColor => _colors.textMuted;
  Color get _accentGreen => _colors.primary;

  Future<void> _handleUpdate() async {
    setState(() => _isLoading = true);
    try {
      await _supabaseService.updatePassword(_newPasswordController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated! Please login.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: Text('New Password', style: TextStyle(color: _textColor)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              style: TextStyle(color: _textColor),
              decoration: InputDecoration(
                labelText: 'New Password',
                labelStyle: TextStyle(color: _mutedTextColor),
              ),
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _handleUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentGreen,
                      foregroundColor: _colors.onPrimary,
                    ),
                    child: const Text('Update Password'),
                  ),
          ],
        ),
      ),
    );
  }
}

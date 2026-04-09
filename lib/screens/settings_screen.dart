// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:final_project/services/notification_service.dart';

import '../models/profile_model.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'update_password_screen.dart';
import 'bank_selection_screen.dart'; // Your new Privacy feature screen

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _supabaseService = SupabaseService();

  // Local Settings State for Persistence
  bool _isBiometricEnabled = false;
  bool _isNotificationsEnabled = true;
  String _selectedLanguage = "English";
  String _selectedCurrency = "JOD (JD)";

  // UI Theme Constants (Neon-Dark Professional Style)
  static const Color _bgColor = Color(0xFF061414);
  static const Color _cardColor = Color(0xFF111D1D);
  static const Color _accentGreen = Color(0xFF34EAB9);

  @override
  void initState() {
    super.initState();
    _loadUserSettings(); // Hydrate UI from Local Storage on init
  }

  /// Logic: Fetches all saved preferences from SharedPreferences
  Future<void> _loadUserSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isBiometricEnabled = prefs.getBool('biometric_enabled') ?? false;
      _isNotificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _selectedLanguage = prefs.getString('language') ?? "English";
      _selectedCurrency = prefs.getString('currency') ?? "JOD (JD)";
    });
  }

  /// Logic: Updates and Persists user preferences locally
  Future<void> _updatePreference(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
    _loadUserSettings(); // Refresh UI State
  }

  /// Logic: Signs out from Supabase and redirects to Login
  Future<void> _handleSignOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      debugPrint("Sign Out Error: $e");
    }
  }

  /// UI: Shows detailed user information in a Bottom Sheet
  void _showProfileDetails(ProfileModel profile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "User Account Details",
              style: TextStyle(
                color: _accentGreen,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(color: Colors.white10, height: 30),
            _detailRow("Full Name", profile.fullName),
            _detailRow("Phone Number", profile.phone ?? "Not provided"),
            _detailRow(
              "Net Worth",
              "JD ${profile.totalNetWorth.toStringAsFixed(2)}",
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Settings",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildProfileSection(),
            const SizedBox(height: 30),
            _buildSettingsGroup("Account Security", [
              _buildSettingItem(
                icon: Icons.lock_outline,
                title: "Change Password",
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const UpdatePasswordScreen()),
                ),
              ),
              _buildSettingItem(
                icon: Icons.fingerprint,
                title: "Biometric Authentication",
                trailing: Switch(
                  value: _isBiometricEnabled,
                  onChanged: (val) => _updatePreference('biometric_enabled', val),
                  activeColor: _accentGreen,
                  activeTrackColor: _accentGreen.withOpacity(0.3),
                  inactiveThumbColor: Colors.grey,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            _buildSettingsGroup("Automation & Privacy", [
              _buildSettingItem(
                icon: Icons.security_outlined,
                title: "Bank SMS Monitoring",
                subtitle: "Select banks to track transactions",
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BankSelectionScreen()),
                ),
              ),
              _buildSettingItem(
                icon: Icons.notifications_none,
                title: "Push Notifications",
                trailing: Switch(
                  value: _isNotificationsEnabled,
                  onChanged: (val) async {
                    await _updatePreference('notifications_enabled', val);
                    if (val) {
                      // Trigger a verification alert to confirm setup
                      await NotificationService().showInstantNotification(
                        "Alerts Enabled",
                        "You will now receive automated financial updates.",
                      );
                    }
                  },
                  activeColor: _accentGreen,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            _buildSettingsGroup("Preferences", [
              _buildSettingItem(
                icon: Icons.language,
                title: "Language",
                subtitle: _selectedLanguage,
                onTap: () => _showSelectionDialog("Select Language", ["English", "Arabic"], 'language'),
              ),
              _buildSettingItem(
                icon: Icons.monetization_on_outlined,
                title: "Default Currency",
                subtitle: _selectedCurrency,
                onTap: () => _showSelectionDialog("Select Currency", ["JOD (JD)", "USD (\$)"], 'currency'),
              ),
            ]),
            const SizedBox(height: 40),
            _buildLogoutButton(),
          ],
        ),
      ),
    );
  }

  /// UI Logic: Shows a generic selection dialog for Language/Currency
  void _showSelectionDialog(String title, List<String> options, String key) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((opt) => ListTile(
            title: Text(opt, style: const TextStyle(color: Colors.white70)),
            onTap: () {
              _updatePreference(key, opt);
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return FutureBuilder<ProfileModel>(
      future: _supabaseService.getProfileData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator(color: _accentGreen);
        final profile = snapshot.data!;
        return InkWell(
          onTap: () => _showProfileDetails(profile),
          borderRadius: BorderRadius.circular(25),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 35,
                  backgroundColor: _accentGreen,
                  child: Icon(Icons.person, size: 40, color: Colors.black),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.fullName,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        profile.phone ?? "No phone number added",
                        style: const TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsGroup(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 0, 10),
          child: Text(
            title,
            style: const TextStyle(color: _accentGreen, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        Container(
          decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(20)),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)) : null,
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right, color: Colors.grey, size: 20) : null),
    );
  }

  Widget _buildLogoutButton() {
    return ElevatedButton.icon(
      onPressed: _handleSignOut,
      icon: const Icon(Icons.logout, color: Colors.black),
      label: const Text("Logout", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }
}
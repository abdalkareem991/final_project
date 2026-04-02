// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_model.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'update_password_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _supabaseService = SupabaseService();

  // Theme Constants
  static const Color _bgColor = Color(0xFF061414);
  static const Color _cardColor = Color(0xFF111D1D);
  static const Color _accentGreen = Color(0xFF34EAB9);

  /// Logic: Sign out from Supabase and clear session
  Future<void> _handleSignOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;

      // Navigate to Login and remove all previous routes
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      debugPrint("Sign Out Error: $e");
    }
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
                  MaterialPageRoute(
                    builder: (context) => const UpdatePasswordScreen(),
                  ),
                ),
              ),
              _buildSettingItem(
                icon: Icons.fingerprint,
                title: "Biometric Authentication",
                trailing: Switch(
                  value: true,
                  onChanged: (val) {},
                  activeThumbColor: _accentGreen,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            _buildSettingsGroup("Preferences", [
              _buildSettingItem(
                icon: Icons.language,
                title: "Language",
                subtitle: "English",
              ),
              _buildSettingItem(
                icon: Icons.monetization_on_outlined,
                title: "Default Currency",
                subtitle: "USD (\$)",
              ),
              _buildSettingItem(
                icon: Icons.notifications_none,
                title: "Push Notifications",
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              ),
            ]),
            const SizedBox(height: 40),
            _buildLogoutButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return FutureBuilder<ProfileModel>(
      future: _supabaseService.getProfileData(),
      builder: (context, snapshot) {
        final name = snapshot.data?.fullName ?? "User";
        final phone = snapshot.data?.phone ?? "No phone added";

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 35,
                backgroundColor: _accentGreen,
                child: Icon(Icons.person, size: 40, color: Colors.black),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    phone,
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ],
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
            style: const TextStyle(
              color: _accentGreen,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
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
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            )
          : null,
      trailing: trailing,
    );
  }

  Widget _buildLogoutButton() {
    return ElevatedButton.icon(
      onPressed: _handleSignOut,
      icon: const Icon(Icons.logout, color: Colors.black),
      label: const Text(
        "Logout",
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }
}

// lib/screens/settings_screen.dart

// ignore_for_file: deprecated_member_use

import 'package:final_project/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:telephony/telephony.dart'; //new

import '../core/app_text.dart';
import '../models/profile_model.dart';
import '../services/sms_listener_service.dart'; //new
import '../services/supabase_service.dart';
import 'bank_selection_screen.dart'; // Your new Privacy feature screen
import 'login_screen.dart';
import 'update_password_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _supabaseService = SupabaseService();
  final _localAuth = LocalAuthentication();
  final _secureStorage = const FlutterSecureStorage();

  // Local Settings State for Persistence
  bool _isBiometricEnabled = false;
  bool _isNotificationsEnabled = true;
  bool _isSmsAutomationEnabled = false;
  String? _busySettingKey;
  String _selectedLanguageCode = "en";
  String _selectedCurrency = "JOD (JD)";
  late final Future<ProfileModel> _profileFuture = _supabaseService
      .getProfileData();

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
    final secureBiometric = await _secureStorage.read(key: 'use_biometrics');
    final biometricEnabled = secureBiometric == 'true';
    if (prefs.getBool('biometric_enabled') != biometricEnabled) {
      await prefs.setBool('biometric_enabled', biometricEnabled);
    }

    if (!mounted) return;
    setState(() {
      _isBiometricEnabled = biometricEnabled;
      _isNotificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _isSmsAutomationEnabled =
          prefs.getBool('sms_automation_enabled') ?? false;
      _selectedLanguageCode = prefs.getString(AppText.languageKey) ?? 'en';
      _selectedCurrency = prefs.getString('currency') ?? "JOD (JD)";
    });
  }

  /// Logic: Updates and Persists user preferences locally
  Future<void> _updatePreference(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
    await _loadUserSettings(); // Refresh UI State
  }

  Future<void> _setLanguage(String code) async {
    await AppText.setLanguageCode(code);
    await _loadUserSettings();
  }

  Future<void> _setBusy(String? key) async {
    if (!mounted) return;
    setState(() => _busySettingKey = key);
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  Future<void> _setBiometricEnabled(bool enabled) async {
    await _setBusy('biometric');

    try {
      if (enabled) {
        final canAuthenticate =
            await _localAuth.canCheckBiometrics ||
            await _localAuth.isDeviceSupported();

        if (!canAuthenticate) {
          _showSnack(
            context.t(
              "Biometric authentication is not available.",
              "المصادقة بالبصمة غير متاحة.",
            ),
            isError: true,
          );
          return;
        }

        final savedEmail = await _secureStorage.read(key: 'email');
        final savedPassword = await _secureStorage.read(key: 'password');

        if (savedEmail == null || savedPassword == null) {
          _showSnack(
            context.t(
              "Log in with your password once before enabling biometrics.",
              "سجل الدخول بكلمة المرور مرة واحدة قبل تفعيل البصمة.",
            ),
            isError: true,
          );
          return;
        }

        final didAuthenticate = await _localAuth.authenticate(
          localizedReason: 'Confirm biometrics to enable quick login',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: true,
          ),
        );

        if (!didAuthenticate) {
          _showSnack(
            context.t(
              "Biometric setup was cancelled.",
              "تم إلغاء إعداد البصمة.",
            ),
            isError: true,
          );
          return;
        }

        await _secureStorage.write(key: 'use_biometrics', value: 'true');
      } else {
        await _secureStorage.write(key: 'use_biometrics', value: 'false');
      }

      await _updatePreference('biometric_enabled', enabled);
      _showSnack(
        enabled
            ? context.t("Biometric login enabled.", "تم تفعيل الدخول بالبصمة.")
            : context.t(
                "Biometric login disabled.",
                "تم إيقاف الدخول بالبصمة.",
              ),
      );
    } catch (e) {
      debugPrint("Biometric setting error: $e");
      _showSnack(
        context.t(
          "Could not update biometric setting.",
          "تعذر تحديث إعداد البصمة.",
        ),
        isError: true,
      );
    } finally {
      await _setBusy(null);
    }
  }

  Future<void> _setSmsAutomationEnabled(bool enabled) async {
    await _setBusy('sms');

    try {
      if (enabled) {
        final permissionsGranted =
            await Telephony.instance.requestPhoneAndSmsPermissions;

        if (permissionsGranted != true) {
          await _updatePreference('sms_automation_enabled', false);
          _showSnack(
            context.t(
              "SMS permissions denied. Automation was not enabled.",
              "تم رفض صلاحيات الرسائل. لم يتم تفعيل الأتمتة.",
            ),
            isError: true,
          );
          return;
        }

        await _updatePreference('sms_automation_enabled', true);
        final started = await SMSListenerService().startListening(
          syncImmediately: true,
        );
        if (!started) {
          await _updatePreference('sms_automation_enabled', false);
          _showSnack(
            context.t(
              "SMS permissions denied. Automation was not enabled.",
              "تم رفض صلاحيات الرسائل. لم يتم تفعيل الأتمتة.",
            ),
            isError: true,
          );
          return;
        }
        _showSnack(
          context.t(
            "SMS automation is now active.",
            "أتمتة الرسائل مفعلة الآن.",
          ),
        );
      } else {
        SMSListenerService().stopListening();
        await _updatePreference('sms_automation_enabled', false);
        _showSnack(
          context.t("SMS automation stopped.", "تم إيقاف أتمتة الرسائل."),
        );
      }
    } catch (e) {
      debugPrint("SMS automation setting error: $e");
      await _updatePreference('sms_automation_enabled', false);
      _showSnack(
        context.t(
          "Could not update SMS automation.",
          "تعذر تحديث أتمتة الرسائل.",
        ),
        isError: true,
      );
    } finally {
      await _setBusy(null);
    }
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    await _setBusy('notifications');

    try {
      await _updatePreference('notifications_enabled', enabled);

      if (enabled) {
        await NotificationService().initNotification();
        final rescheduledCount = await _supabaseService
            .reschedulePendingTaskReminders();

        await NotificationService().showInstantNotification(
          context.t("Alerts Enabled", "تم تفعيل التنبيهات"),
          rescheduledCount == 0
              ? context.t(
                  "You will now receive automated financial updates.",
                  "ستصلك الآن تحديثات مالية تلقائية.",
                )
              : context.t(
                  "$rescheduledCount task reminders were refreshed.",
                  "تم تحديث $rescheduledCount من تذكيرات المهام.",
                ),
        );

        _showSnack(
          context.t("Push notifications enabled.", "تم تفعيل الإشعارات."),
        );
      } else {
        await NotificationService().cancelAllNotifications();
        _showSnack(
          context.t("Push notifications disabled.", "تم إيقاف الإشعارات."),
        );
      }
    } catch (e) {
      debugPrint("Notification setting error: $e");
      _showSnack(
        context.t(
          "Could not update notification setting.",
          "تعذر تحديث الإشعارات.",
        ),
        isError: true,
      );
    } finally {
      await _setBusy(null);
    }
  }

  Future<void> _enableEverything() async {
    await _setNotificationsEnabled(true);
    try {
      await _supabaseService.setAllAutomatedWalletMonitoring(true);
    } catch (e) {
      debugPrint("Enable all bank monitoring error: $e");
    }
    await _setSmsAutomationEnabled(true);
    await _setBiometricEnabled(true);
  }

  /// Logic: Signs out from Supabase and redirects to Login
  Future<void> _handleSignOut() async {
    try {
      SMSListenerService().stopListening();
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
            Text(
              context.t("User Account Details", "تفاصيل حساب المستخدم"),
              style: const TextStyle(
                color: _accentGreen,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(color: Colors.white10, height: 30),
            _detailRow(
              context.t("Full Name", "الاسم الكامل"),
              profile.fullName,
            ),
            _detailRow(
              context.t("Phone Number", "رقم الهاتف"),
              profile.phone ?? context.t("Not provided", "غير متوفر"),
            ),
            _detailRow(
              context.t("Net Worth", "صافي الثروة"),
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
        title: Text(
          context.t("Settings", "الإعدادات"),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildProfileSection(),
            const SizedBox(height: 18),
            _buildEnableEverythingCard(),
            const SizedBox(height: 30),
            _buildSettingsGroup(context.t("Account Security", "أمان الحساب"), [
              _buildSettingItem(
                icon: Icons.lock_outline,
                title: context.t("Change Password", "تغيير كلمة المرور"),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UpdatePasswordScreen(),
                  ),
                ),
              ),
              _buildSettingItem(
                icon: Icons.fingerprint,
                title: context.t(
                  "Biometric Authentication",
                  "المصادقة بالبصمة",
                ),
                trailing: Switch(
                  value: _isBiometricEnabled,
                  onChanged: _busySettingKey == null
                      ? _setBiometricEnabled
                      : null,
                  activeThumbColor: _accentGreen,
                  activeTrackColor: _accentGreen.withOpacity(0.3),
                  inactiveThumbColor: Colors.grey,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            _buildSettingsGroup(
              context.t("Automation & Privacy", "الأتمتة والخصوصية"),
              [
                _buildSettingItem(
                  icon: Icons.security_outlined,
                  title: context.t("Bank SMS Monitoring", "مراقبة رسائل البنك"),
                  subtitle: context.t(
                    "Select banks to track transactions",
                    "اختر البنوك لتتبع الحركات",
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BankSelectionScreen(),
                    ),
                  ),
                ),
                _buildSettingItem(
                  icon: Icons.message_outlined,
                  title: context.t(
                    "Enable SMS Automation",
                    "تفعيل أتمتة الرسائل",
                  ),
                  subtitle: context.t(
                    "Automatically log bank transactions",
                    "تسجيل حركات البنك تلقائيًا",
                  ),
                  trailing: Switch(
                    value: _isSmsAutomationEnabled,
                    onChanged: _busySettingKey == null
                        ? _setSmsAutomationEnabled
                        : null,
                    activeThumbColor: _accentGreen,
                  ),
                ),
                _buildSettingItem(
                  icon: Icons.notifications_none,
                  title: context.t("Push Notifications", "الإشعارات"),
                  trailing: Switch(
                    value: _isNotificationsEnabled,
                    onChanged: _busySettingKey == null
                        ? _setNotificationsEnabled
                        : null,
                    activeThumbColor: _accentGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSettingsGroup(context.t("Preferences", "التفضيلات"), [
              _buildSettingItem(
                icon: Icons.language,
                title: context.t("Language", "اللغة"),
                subtitle: AppText.languageLabel(_selectedLanguageCode),
                onTap: _showLanguageDialog,
              ),
              _buildSettingItem(
                icon: Icons.monetization_on_outlined,
                title: context.t("Default Currency", "العملة الافتراضية"),
                subtitle: _selectedCurrency,
                onTap: () => _showSelectionDialog(
                  context.t("Select Currency", "اختر العملة"),
                  ["JOD (JD)", "USD (\$)"],
                  'currency',
                ),
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
  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text(
          context.t("Select Language", "اختر اللغة"),
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [_languageOption('en'), _languageOption('ar')],
        ),
      ),
    );
  }

  Widget _languageOption(String code) {
    final isSelected = _selectedLanguageCode == code;

    return ListTile(
      title: Text(
        AppText.languageLabel(code),
        style: TextStyle(
          color: isSelected ? _accentGreen : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check, color: _accentGreen, size: 20)
          : null,
      onTap: () async {
        await _setLanguage(code);
        if (mounted) Navigator.pop(context);
      },
    );
  }

  void _showSelectionDialog(String title, List<String> options, String key) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (opt) => ListTile(
                  title: Text(
                    opt,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  onTap: () {
                    _updatePreference(key, opt);
                    Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return FutureBuilder<ProfileModel>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(color: _accentGreen);
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox();
        }
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        profile.phone ??
                            context.t(
                              "No phone number added",
                              "لا يوجد رقم هاتف",
                            ),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey,
                  size: 16,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEnableEverythingCard() {
    final isBusy = _busySettingKey != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accentGreen.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _accentGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_awesome, color: _accentGreen),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t("Enable All Features", "تفعيل كل الميزات"),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.t(
                    "Turns on notifications, SMS automation, and biometric login where available.",
                    "يشغل الإشعارات وأتمتة الرسائل والدخول بالبصمة عند توفرها.",
                  ),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: isBusy ? null : _enableEverything,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentGreen,
              disabledBackgroundColor: Colors.white12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    context.t("Enable", "تفعيل"),
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
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
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
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
      trailing:
          trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right, color: Colors.grey, size: 20)
              : null),
    );
  }

  Widget _buildLogoutButton() {
    return ElevatedButton.icon(
      onPressed: _handleSignOut,
      icon: const Icon(Icons.logout, color: Colors.black),
      label: Text(
        context.t("Logout", "تسجيل الخروج"),
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }
}

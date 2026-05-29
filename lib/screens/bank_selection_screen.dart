// lib/screens/bank_selection_screen.dart

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_text.dart';
import '../core/app_theme.dart';
import '../models/wallet_model.dart';
import '../services/sms_listener_service.dart';
import '../services/supabase_service.dart';

class BankSelectionScreen extends StatefulWidget {
  const BankSelectionScreen({super.key});

  @override
  State<BankSelectionScreen> createState() => _BankSelectionScreenState();
}

class _BankSelectionScreenState extends State<BankSelectionScreen> {
  final SupabaseService _supabaseService = SupabaseService();

  AppThemeColors get _colors => context.themeColors;
  Color get bgColor => _colors.background;
  Color get cardColor => _colors.surface;
  Color get fieldColor => _colors.field;
  Color get accentGreen => _colors.primary;
  Color get textColor => _colors.textPrimary;
  Color get secondaryTextColor => _colors.textSecondary;
  Color get mutedTextColor => _colors.textMuted;

  @override
  void initState() {
    super.initState();
    // Initialize stream to listen for wallet changes in real-time
    _initWalletsStream();
  }

  void _initWalletsStream() {
    // Note: This maps the dynamic list from Supabase to WalletModel objects
    // For production, ensure SupabaseService has getWalletsStream()
  }

  /// Logic: Toggles the active monitoring status for an automated account
  Future<void> _toggleMonitoring(WalletModel wallet, bool status) async {
    try {
      if (status) {
        final started = await SMSListenerService()
            .startListening(syncImmediately: false)
            .timeout(const Duration(seconds: 25), onTimeout: () => false);
        if (!started) {
          SMSListenerService().stopListening();
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('sms_automation_enabled', started);

        if (!started && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.t(
                  "SMS permissions denied. Automatic sync was not enabled.",
                  "تم رفض صلاحيات الرسائل. لم يتم تفعيل المزامنة التلقائية.",
                ),
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      await _supabaseService.updateWallet(
        wallet.copyWith(isActiveMonitoring: status),
      );

      if (status) {
        await SMSListenerService().syncNow(
          reason: 'monitoring_enabled',
          force: true,
        );
      }

      if (mounted) setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status
                ? context.t("Monitoring Enabled", "تم تفعيل المراقبة")
                : context.t("Monitoring Disabled", "تم إيقاف المراقبة"),
          ),
          backgroundColor: status ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      debugPrint("Toggle Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          context.t("Bank Monitoring", "مراقبة البنك"),
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t("Automated Accounts", "الحسابات الآلية"),
              style: TextStyle(color: mutedTextColor, fontSize: 16),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: FutureBuilder<List<WalletModel>>(
                // Logic: Filter only AUTOMATED accounts as per the plan
                future: _supabaseService.getWallets(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(color: accentGreen),
                    );
                  }

                  final automatedWallets =
                      snapshot.data
                          ?.where((w) => w.accountMode == 'AUTOMATED')
                          .toList() ??
                      [];

                  if (automatedWallets.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.builder(
                    itemCount: automatedWallets.length,
                    itemBuilder: (context, index) {
                      final wallet = automatedWallets[index];
                      final bool isMonitoring = wallet.isActiveMonitoring;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: isMonitoring
                                ? accentGreen
                                : _colors.subtleBorder,
                            width: 1.5,
                          ),
                        ),
                        child: SwitchListTile(
                          title: Text(
                            wallet.name,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            "Sender ID: ${wallet.smsSenderId}",
                            style: TextStyle(
                              color: mutedTextColor,
                              fontSize: 12,
                            ),
                          ),
                          value: isMonitoring,
                          activeThumbColor: accentGreen,
                          onChanged: (val) => _toggleMonitoring(wallet, val),
                          secondary: Icon(
                            Icons.security,
                            color: isMonitoring ? accentGreen : mutedTextColor,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// UI: Shown when no automated accounts are linked
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_fix_off,
            size: 60,
            color: textColor.withOpacity(0.12),
          ),
          const SizedBox(height: 15),
          Text(
            context.t("No automated accounts found.", "لا توجد حسابات آلية."),
            style: TextStyle(color: mutedTextColor),
          ),
          Text(
            context.t(
              "Add an Automated Account from the main screen.",
              "أضف حسابًا آليًا من الشاشة الرئيسية.",
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: mutedTextColor.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

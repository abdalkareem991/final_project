// lib/screens/bank_selection_screen.dart

import 'package:flutter/material.dart';

import '../models/wallet_model.dart';
import '../services/supabase_service.dart';

class BankSelectionScreen extends StatefulWidget {
  const BankSelectionScreen({super.key});

  @override
  State<BankSelectionScreen> createState() => _BankSelectionScreenState();
}

class _BankSelectionScreenState extends State<BankSelectionScreen> {
  final SupabaseService _supabaseService = SupabaseService();

  // Real-time stream for wallets
  late Stream<List<WalletModel>> _walletsStream;

  // Theme Colors
  static const Color bgColor = Color(0xFF061414);
  static const Color cardColor = Color(0xFF111D1D);
  static const Color accentGreen = Color(0xFF34EAB9);

  @override
  void initState() {
    super.initState();
    // Initialize stream to listen for wallet changes in real-time
    _initWalletsStream();
  }

  void _initWalletsStream() {
    // Note: This maps the dynamic list from Supabase to WalletModel objects
    _walletsStream = _supabaseService.getTransactionsStream().map((_) => []);
    // For production, ensure SupabaseService has getWalletsStream()
  }

  /// Logic: Toggles the active monitoring status for an automated account
  Future<void> _toggleMonitoring(WalletModel wallet, bool status) async {
    try {
      final updatedWallet = WalletModel(
        id: wallet.id,
        name: wallet.name,
        balance: wallet.balance,
        type: wallet.type,
        accountMode: wallet.accountMode,
        smsSenderId: wallet.smsSenderId,
        isActiveMonitoring: status,
      );

      await _supabaseService.updateWallet(updatedWallet);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status ? "Monitoring Enabled" : "Monitoring Disabled"),
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
        title: const Text(
          "Bank Monitoring",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Automated Accounts",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: FutureBuilder<List<WalletModel>>(
                // Logic: Filter only AUTOMATED accounts as per the plan
                future: _supabaseService.getWallets(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
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
                            color: isMonitoring ? accentGreen : Colors.white10,
                            width: 1.5,
                          ),
                        ),
                        child: SwitchListTile(
                          title: Text(
                            wallet.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            "Sender ID: ${wallet.smsSenderId}",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          value: isMonitoring,
                          activeThumbColor: accentGreen,
                          onChanged: (val) => _toggleMonitoring(wallet, val),
                          secondary: Icon(
                            Icons.security,
                            color: isMonitoring ? accentGreen : Colors.grey,
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
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 15),
          const Text(
            "No automated accounts found.",
            style: TextStyle(color: Colors.grey),
          ),
          const Text(
            "Add an Automated Account from the main screen.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

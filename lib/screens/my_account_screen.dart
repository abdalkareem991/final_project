// lib/screens/my_account_screen.dart

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:telephony/telephony.dart';

import '../models/wallet_model.dart';
import '../services/ai_service.dart';
import '../services/supabase_service.dart';

class MyAccountScreen extends StatefulWidget {
  const MyAccountScreen({super.key});

  @override
  State<MyAccountScreen> createState() => MyAccountScreenState();
}

class MyAccountScreenState extends State<MyAccountScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  final AIService _aiService = AIService();
  final Telephony telephony = Telephony.instance;

  late Stream<Map<String, double>> _balancesStream;
  late Stream<List<WalletModel>> _walletsStream;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  static const Color _bgColor = Color(0xFF061414);
  static const Color _cardColor = Color(0xFF111D1D);
  static const Color _accentGreen = Color(0xFF34EAB9);
  static const Color _accentBlue = Color(0xFF3B82F6);
  static const Color _expenseRed = Color(0xFFFF5252);

  @override
  void initState() {
    super.initState();
    _initStreams();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutQuad,
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _initStreams() {
    final user = _supabaseService.client.auth.currentUser;

    _balancesStream = _supabaseService.getBalancesStream();

    if (user == null) {
      _walletsStream = Stream.value([]);
      return;
    }

    _walletsStream = _supabaseService.client
        .from('wallets')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .map((data) => data.map((json) => WalletModel.fromJson(json)).toList());
  }

  void refreshAccounts() {
    if (!mounted) return;
    setState(() => _initStreams());
  }

  Future<void> _deleteWallet(String walletId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Delete Account",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "This action will remove the account and its history. Continue?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _expenseRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Delete",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _supabaseService.deleteWallet(walletId);
      refreshAccounts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          "Accounts",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 28,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: _accentGreen,
        onRefresh: () async => refreshAccounts(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLiveTotalNetWorthHeader(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(
                  "Your Wallets",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildAccountsListWithAnimation(),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FloatingActionButton.extended(
          heroTag: 'account_add_btn',
          backgroundColor: _accentGreen,
          icon: const Icon(Icons.add, color: Colors.black),
          label: const Text(
            "Add New Account",
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          onPressed: () => _showWalletModal(context: context),
        ),
      ),
    );
  }

  Widget _buildLiveTotalNetWorthHeader() {
    return StreamBuilder<Map<String, double>>(
      stream: _balancesStream,
      builder: (context, snapshot) {
        final double total = snapshot.data?['Total'] ?? 0.0;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          padding: const EdgeInsets.all(25),
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_accentGreen, _accentBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "CREDIT TOTAL",
                style: TextStyle(
                  color: Colors.black.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "JD ${total.toStringAsFixed(2)}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccountsListWithAnimation() {
    return StreamBuilder<List<WalletModel>>(
      stream: _walletsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _accentGreen),
          );
        }

        final wallets = snapshot.data!;

        if (wallets.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(30),
            child: Center(
              child: Text(
                "No accounts yet.",
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 90),
              itemCount: wallets.length,
              itemBuilder: (context, index) =>
                  _buildAccountCard(wallets[index]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccountCard(WalletModel account) {
    final IconData icon = account.accountMode == 'AUTOMATED'
        ? Icons.auto_awesome
        : Icons.account_balance_wallet;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(15),
        border: account.accountMode == 'AUTOMATED'
            ? Border.all(color: _accentGreen.withOpacity(0.25))
            : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accentGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _accentGreen, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  account.accountMode == 'AUTOMATED'
                      ? "${account.type} • ${account.smsSenderId ?? 'No sender'}"
                      : account.type,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            "JD ${account.balance.toStringAsFixed(2)}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 5),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
            color: _cardColor,
            onSelected: (value) {
              if (value == 'edit') {
                _showWalletModal(context: context, wallet: account);
              }
              if (value == 'delete') {
                _deleteWallet(account.id);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text("Edit", style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text("Delete", style: TextStyle(color: _expenseRed)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showWalletModal({required BuildContext context, WalletModel? wallet}) {
    final bool isEditing = wallet != null;

    final nameController = TextEditingController(
      text: isEditing ? wallet.name : '',
    );

    final balanceController = TextEditingController(
      text: isEditing ? wallet.balance.toString() : '',
    );

    String selectedType = isEditing ? wallet.type : 'Bank';
    String accountMode = isEditing ? wallet.accountMode : 'MANUAL';
    String? selectedSenderId = isEditing ? wallet.smsSenderId : null;
    bool isLoadingBalance = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) {
          return SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              left: 24,
              right: 24,
              top: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  isEditing ? "Edit Account" : "Add New Account",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                if (!isEditing)
                  Row(
                    children: [
                      Radio<String>(
                        value: 'MANUAL',
                        groupValue: accountMode,
                        activeColor: _accentGreen,
                        onChanged: (v) {
                          setModalState(() {
                            accountMode = v!;
                            selectedSenderId = null;
                          });
                        },
                      ),
                      const Text(
                        "Manual",
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(width: 20),
                      Radio<String>(
                        value: 'AUTOMATED',
                        groupValue: accountMode,
                        activeColor: _accentGreen,
                        onChanged: (v) => setModalState(() => accountMode = v!),
                      ),
                      const Text(
                        "Automated",
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),

                const SizedBox(height: 10),

                if (accountMode == 'AUTOMATED' && !isEditing) ...[
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _pickSenderFromInbox((sender) async {
                        setModalState(() {
                          selectedSenderId = sender;
                          nameController.text = sender;
                          isLoadingBalance = true;
                        });

                        await _autoFetchBalance(sender, balanceController);

                        if (mounted) {
                          setModalState(() => isLoadingBalance = false);
                        }
                      });
                    },
                    icon: const Icon(Icons.sms_outlined, size: 18),
                    label: Text(
                      selectedSenderId ?? "Select Bank SMS Source",
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _cardColor,
                      foregroundColor: _accentGreen,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                  if (isLoadingBalance) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(color: _accentGreen),
                  ],
                  const SizedBox(height: 15),
                ],

                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    "Account Name",
                    Icons.account_balance,
                  ),
                ),

                const SizedBox(height: 15),

                TextField(
                  controller: balanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: _inputDecoration(
                    "Current Balance (JD)",
                    Icons.payments,
                  ),
                ),

                const SizedBox(height: 15),

                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  dropdownColor: _cardColor,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration("Account Type", Icons.category),
                  items: ['Bank', 'Cash', 'Mobile Wallet']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (val) => setModalState(() => selectedType = val!),
                ),

                const SizedBox(height: 30),

                ElevatedButton(
                  onPressed: () async {
                    final String name = nameController.text.trim();
                    final double balance =
                        double.tryParse(balanceController.text.trim()) ?? 0.0;

                    if (name.isEmpty) {
                      _showSnack("Account name is required.");
                      return;
                    }

                    if (accountMode == 'AUTOMATED' &&
                        (selectedSenderId == null ||
                            selectedSenderId!.isEmpty)) {
                      _showSnack("Please select an SMS sender first.");
                      return;
                    }

                    final walletData = WalletModel(
                      id: isEditing ? wallet.id : '',
                      name: name,
                      balance: balance,
                      type: selectedType,
                      accountMode: accountMode,
                      smsSenderId: selectedSenderId,
                      isActiveMonitoring: accountMode == 'AUTOMATED',
                    );

                    try {
                      if (isEditing) {
                        await _supabaseService.updateWallet(walletData);
                      } else {
                        await _supabaseService.addWallet(walletData);
                      }

                      debugPrint(
                        "Saved wallet mode: ${walletData.accountMode}",
                      );
                      debugPrint(
                        "Saved wallet sender: ${walletData.smsSenderId}",
                      );
                      debugPrint(
                        "Saved wallet monitoring: ${walletData.isActiveMonitoring}",
                      );

                      if (!mounted) return;
                      Navigator.pop(sheetContext);
                      refreshAccounts();
                    } catch (e) {
                      _showSnack("Save failed: $e");
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGreen,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    isEditing ? "UPDATE ACCOUNT" : "SAVE ACCOUNT",
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),

                const SizedBox(height: 25),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickSenderFromInbox(Function(String) onPicked) async {
    final bool? hasPermission = await telephony.requestPhoneAndSmsPermissions;

    debugPrint("SMS permission: $hasPermission");

    if (hasPermission != true) {
      _showSnack("SMS permission denied.");
      debugPrint("SMS permission denied");
      return;
    }

    final List<SmsMessage> messages = await telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    debugPrint("Inbox messages count: ${messages.length}");

    for (final SmsMessage m in messages.take(20)) {
      debugPrint("Sender: ${m.address}");
      debugPrint("Body: ${m.body}");
    }

    final List<String> senders = [];

    for (final message in messages) {
      final String? address = message.address?.trim();

      if (address == null || address.isEmpty) continue;

      if (!senders.contains(address)) {
        senders.add(address);
      }

      if (senders.length == 10) break;
    }

    debugPrint("Latest 10 senders count: ${senders.length}");
    debugPrint("Latest 10 senders list: $senders");

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.65,
          child: senders.isEmpty
              ? const Center(
                  child: Text(
                    "No SMS senders found",
                    style: TextStyle(color: Colors.white),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: senders.length,
                  itemBuilder: (context, index) {
                    final String sender = senders[index];

                    return ListTile(
                      leading: const Icon(Icons.sms, color: _accentGreen),
                      title: Text(
                        sender,
                        style: const TextStyle(color: Colors.white),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        onPicked(sender);
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  Future<void> _autoFetchBalance(
    String sender,
    TextEditingController balanceController,
  ) async {
    try {
      final List<SmsMessage> messages = await telephony.getInboxSms(
        columns: [SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(SmsColumn.ADDRESS).equals(sender),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      debugPrint("Selected sender: $sender");
      debugPrint("Messages from selected sender: ${messages.length}");

      if (messages.isEmpty) {
        _showSnack("No SMS messages found for this sender.");
        return;
      }

      final String? latestBody = messages.first.body;

      debugPrint("Latest SMS body: $latestBody");

      if (latestBody == null || latestBody.trim().isEmpty) {
        _showSnack("Latest SMS body is empty.");
        return;
      }

      final double? balance = _aiService.extractBalanceLocally(latestBody);

      if (balance != null) {
        balanceController.text = balance.toStringAsFixed(2);
        _showSnack("Balance detected successfully.");
      } else {
        _showSnack("Could not detect balance. Enter it manually.");
      }
    } catch (e) {
      debugPrint("Auto fetch balance error: $e");
      _showSnack("Could not read SMS balance.");
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: _cardColor),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
      prefixIcon: Icon(icon, color: _accentGreen, size: 22),
      filled: true,
      fillColor: _cardColor,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: _accentGreen, width: 2),
      ),
    );
  }
}

// lib/screens/my_account_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/wallet_model.dart';
import '../services/supabase_service.dart';

class MyAccountScreen extends StatefulWidget {
  const MyAccountScreen({super.key});

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();

  // Dynamic Data Futures
  late Future<double> _totalNetWorthFuture = _supabaseService
      .calculateTotalNetWorth();
  late Future<List<WalletModel>> _walletsFuture = _supabaseService.getWallets();

  // --- Animation Controllers ---
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // --- Theme Constants (Matched to your app's design system) ---
  static const Color _bgColor = Color(0xFF061414);
  static const Color _cardColor = Color(0xFF111D1D);
  static const Color _accentGreen = Color(0xFF34EAB9);
  static const Color _accentBlue = Color(0xFF3B82F6);
  static const Color _expenseRed = Color(0xFFFF5252);

  @override
  void initState() {
    super.initState();

    // Initialize futures synchronously to prevent LateInitializationError
    _fetchData();

    // Initialize animations for smooth loading
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

  /// Logic: Fetches dynamically calculated net worth and the list of wallets
  void _fetchData() {
    _walletsFuture = _supabaseService.getWallets();
    _totalNetWorthFuture = _supabaseService.calculateTotalNetWorth();
  }

  /// Logic: Handles wallet deletion with confirmation
  Future<void> _deleteWallet(String walletId) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Delete Account",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Are you sure you want to delete this account? This action cannot be undone.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _expenseRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
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
      setState(() {
        _fetchData(); // Refresh UI after deletion
      });
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
        onRefresh: () async {
          setState(() => _fetchData());
          try {
            await Future.wait([_totalNetWorthFuture, _walletsFuture]);
          } catch (_) {}
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTotalNetWorthHeader(),
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
          backgroundColor: _accentGreen,
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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

  /// UI: Gradient card showing dynamically calculated Total Net Worth in JD
  Widget _buildTotalNetWorthHeader() {
    return FutureBuilder<double>(
      future: _totalNetWorthFuture,
      builder: (context, snapshot) {
        // Updated label name
        const String labelText = "CREDIT TOTAL";

        String netWorth = snapshot.hasData
            ? "JD ${snapshot.data!.toStringAsFixed(2)}"
            : "JD 0.00";

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
            boxShadow: [
              BoxShadow(
                color: _accentGreen.withOpacity(0.2),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                labelText, // Uses the new name
                style: TextStyle(
                  color: Colors.black.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                netWorth,
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

  /// UI: List of individual wallets with loading and animation states
  Widget _buildAccountsListWithAnimation() {
    return FutureBuilder<List<WalletModel>>(
      future: _walletsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.only(top: 40),
              child: CircularProgressIndicator(color: _accentGreen),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 60,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    "No accounts found.",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
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
              padding: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 5,
                bottom: 80,
              ), // Added bottom padding to avoid FAB overlap
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final account = snapshot.data![index];
                return _buildAccountCard(account);
              },
            ),
          ),
        );
      },
    );
  }

  /// UI: Single Wallet Card with Edit/Delete Menu
  Widget _buildAccountCard(WalletModel account) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accentGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.account_balance_wallet,
              color: _accentGreen,
              size: 20,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              account.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Displays JD formatting via WalletModel
          Text(
            account.formattedBalance,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 5),
          // Interactive Edit/Delete Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
            color: _bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            onSelected: (value) {
              if (value == 'edit') {
                _showWalletModal(context: context, wallet: account);
              } else if (value == 'delete') {
                _deleteWallet(account.id);
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, color: Colors.blueAccent, size: 18),
                    SizedBox(width: 10),
                    Text("Edit", style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.redAccent, size: 18),
                    SizedBox(width: 10),
                    Text("Delete", style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// UI & Logic: Reusable Modal for both ADDING and EDITING an account using WalletModel
  void _showWalletModal({required BuildContext context, WalletModel? wallet}) {
    final isEditing = wallet != null;
    final nameController = TextEditingController(
      text: isEditing ? wallet.name : '',
    );
    final balanceController = TextEditingController(
      text: isEditing ? wallet.balance.toString() : '',
    );
    String selectedType = isEditing ? wallet.type : 'Bank';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
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
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  "Account Name (e.g. Arab Bank)",
                  Icons.account_balance,
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
                ],
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                decoration: _inputDecoration("Account Type", Icons.category),
                items: ['Bank', 'Cash', 'Mobile Wallet']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (val) => setModalState(() => selectedType = val!),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isNotEmpty &&
                      balanceController.text.isNotEmpty) {
                    double balance =
                        double.tryParse(balanceController.text) ?? 0.0;

                    // Construct the WalletModel object
                    final walletData = WalletModel(
                      id: isEditing ? wallet.id : '', // Empty string if new
                      name: nameController.text.trim(),
                      balance: balance,
                      type: selectedType,
                      currency: 'JD ', // Set Currency to JOD
                    );

                    // Use the model for database operations
                    if (isEditing) {
                      await _supabaseService.updateWallet(walletData);
                    } else {
                      await _supabaseService.addWallet(walletData);
                    }

                    if (!mounted) return;
                    Navigator.pop(context);
                    setState(() {
                      _fetchData(); // Refresh UI to show new or updated wallet
                    });
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
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 25),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
        prefixIcon: Icon(icon, color: _accentGreen, size: 22),
        filled: true,
        fillColor: _cardColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
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

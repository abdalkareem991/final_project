// lib/screens/dashboard_screen.dart

import 'package:final_project/screens/ai_assistant_screen.dart';
import 'package:final_project/screens/analytics_screen.dart';
import 'package:final_project/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/wallet_model.dart';
import '../services/supabase_service.dart';
import 'my_account_screen.dart';
import 'todo_list_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  static const Color _bgColor = Color(0xFF061414);
  static const Color _accentGreen = Color(0xFF34EAB9);

  // Global key to access the state of the main content for refreshing
  final GlobalKey<_DashboardMainContentState> _mainContentKey = GlobalKey();

  List<Widget> get _screens => [
    _DashboardMainContent(key: _mainContentKey),
    const MyAccountScreen(),
    const AnalyticsScreen(),
    const TodoListScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      // Use IndexedStack to maintain the scroll position of screens
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      backgroundColor: _bgColor,
      selectedItemColor: _accentGreen,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedIndex,
      onTap: (index) {
        setState(() => _selectedIndex = index);
        // Force refresh dashboard data when navigating back to Home
        if (index == 0) {
          _mainContentKey.currentState?.refreshDashboard();
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: "HOME"),
        BottomNavigationBarItem(
          icon: Icon(Icons.account_balance),
          label: "ACCOUNTS",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.analytics_outlined),
          label: "ANALYTICS",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.list_alt),
          label: "TO-DO LIST",
        ),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: "SETTINGS"),
      ],
    );
  }
}

class _DashboardMainContent extends StatefulWidget {
  const _DashboardMainContent({super.key});

  @override
  State<_DashboardMainContent> createState() => _DashboardMainContentState();
}

class _DashboardMainContentState extends State<_DashboardMainContent> {
  final _supabaseService = SupabaseService();

  // Dynamic Data Futures
  late Future<double> _totalBalanceFuture = _supabaseService
      .calculateTotalNetWorth();
  late Future<List<Map<String, dynamic>>> _transactionsFuture = _supabaseService
      .getTransactions();
  late Future<Map<String, double>> _monthlySummaryFuture = _supabaseService
      .getFilteredSummary('Month');

  // Currency Logic State
  String _currencySymbol = "JD";
  double _exchangeRate = 1.0;

  static const Color _bgColor = Color(0xFF061414);
  static const Color _cardColor = Color(0xFF111D1D);
  static const Color _accentGreen = Color(0xFF34EAB9);
  static const Color _expenseRed = Color(0xFFFF6B6B);

  @override
  void initState() {
    super.initState();
    // SOLUTION: Initialize futures synchronously before build() executes
    _totalBalanceFuture = _supabaseService.calculateTotalNetWorth();
    _transactionsFuture = _supabaseService.getTransactions();
    _monthlySummaryFuture = _supabaseService.getFilteredSummary('Month');
    loadCurrencyPreference();
  }

  /// Logic: Refreshes all dashboard components
  void refreshDashboard() {
    loadCurrencyPreference();
    setState(() {
      _totalBalanceFuture = _supabaseService.calculateTotalNetWorth();
      _transactionsFuture = _supabaseService.getTransactions();
      _monthlySummaryFuture = _supabaseService.getFilteredSummary('Month');
    });
  }

  // Fetch saved currency from SharedPreferences
  Future<void> loadCurrencyPreference() async {
    final prefs = await SharedPreferences.getInstance();
    String savedCurrency = prefs.getString('currency') ?? "JOD (JD)";

    setState(() {
      if (savedCurrency.contains("USD")) {
        _currencySymbol = "\$";
        _exchangeRate = 1.41; // Assumption: 1 JOD = 1.41 USD
      } else {
        _currencySymbol = "JD";
        _exchangeRate = 1.0;
      }
    });
  }

  // Utility to format any amount based on the current currency state
  String _formatAmount(double amount) {
    double converted = amount * _exchangeRate;
    return "$_currencySymbol${converted.toStringAsFixed(2)}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        leading: _buildLeadingIcon(),
        title: const Text(
          "FinMind",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [_buildAIChip(context), const SizedBox(width: 15)],
      ),
      body: RefreshIndicator(
        color: _accentGreen,
        onRefresh: () async {
          refreshDashboard();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildTotalBalanceCard(),
              const SizedBox(height: 20),
              _buildAnalyticsSection(),
              const SizedBox(height: 25),
              _buildRecentTransactionsHeader(),
              _buildTransactionsList(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTransactionModal,
        backgroundColor: _accentGreen,
        child: const Icon(Icons.add, color: Colors.black, size: 30),
      ),
    );
  }

  /// UI: Centralized Total Balance Card dynamically linked to Wallets
  Widget _buildTotalBalanceCard() {
    return FutureBuilder<double>(
      future: _totalBalanceFuture,
      builder: (context, snapshot) {
        String balance = snapshot.hasData
            ? _formatAmount(snapshot.data!)
            : _formatAmount(0.0);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _accentGreen,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "TOTAL BALANCE",
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                balance,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// UI & Logic: Dynamic Monthly Analytics Cards
  Widget _buildAnalyticsSection() {
    return FutureBuilder<Map<String, double>>(
      future: _monthlySummaryFuture,
      builder: (context, snapshot) {
        double income = snapshot.data?['Income'] ?? 0.0;
        double expense = snapshot.data?['Expense'] ?? 0.0;

        // Target caps (Can be made dynamic in future updates)

        double incomeProgress = (income).clamp(0.0, 1.0);
        double expenseProgress = (expense).clamp(0.0, 1.0);

        return Column(
          children: [
            _buildProgressCard(
              "Monthly Income",
              "${_formatAmount(income)} ",
              incomeProgress,
              _accentGreen,
            ),
            const SizedBox(height: 12),
            _buildProgressCard(
              "Monthly Expenses",
              _formatAmount(expense),
              expenseProgress,
              _expenseRed,
            ),
          ],
        );
      },
    );
  }

  /// UI: Displays the recent transactions dynamically
  Widget _buildTransactionsList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _transactionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: _accentGreen),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              "No transactions yet.",
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        // Show only the 5 most recent transactions
        final recentTransactions = snapshot.data!.take(5).toList();

        return Column(
          children: recentTransactions.map((tx) {
            final bool isExpense = tx['type'] == 'Expense';
            return _buildTransactionItem(
              tx['description'] ?? "Transaction",
              tx['created_at'].toString().split('T')[0],
              "${isExpense ? '-' : '+'}${_formatAmount((tx['amount'] as num).toDouble())}",
              isExpense ? _expenseRed : _accentGreen,
              isExpense: isExpense,
            );
          }).toList(),
        );
      },
    );
  }

  // --- Reusable UI Components below ---

  Widget _buildLeadingIcon() => Padding(
    padding: const EdgeInsets.all(8.0),
    child: Container(
      decoration: BoxDecoration(
        color: _accentGreen,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.account_balance_wallet, color: Colors.black),
    ),
  );

  Widget _buildAIChip(BuildContext context) => InkWell(
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AIAssistantScreen()),
    ),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _accentGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accentGreen.withValues(alpha: 0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, color: _accentGreen, size: 14),
          SizedBox(width: 5),
          Text(
            "Ask AI",
            style: TextStyle(
              color: _accentGreen,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildRecentTransactionsHeader() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const Text(
        "Recent Transactions",
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      TextButton(
        onPressed: () {
          // Can navigate to a full transaction history screen in the future
        },
        child: const Text("See All", style: TextStyle(color: _accentGreen)),
      ),
    ],
  );

  Widget _buildProgressCard(
    String title,
    String amount,
    double progress,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.grey)),
              Text(
                amount,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white10,
            color: color,
            minHeight: 6,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(
    String title,
    String date,
    String amount,
    Color iconColor, {
    required bool isExpense,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isExpense ? Icons.arrow_downward : Icons.arrow_upward,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  date,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              color: isExpense ? _expenseRed : _accentGreen,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddTransactionModal() {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    String selectedType = 'Expense';
    String? selectedWalletId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: SizedBox(
                      width: 50,
                      child: Divider(thickness: 5, color: Colors.white24),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "New Transaction",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _buildModalToggle(
                        "Expense",
                        selectedType == 'Expense',
                        _expenseRed,
                        () => setModalState(() => selectedType = 'Expense'),
                      ),
                      const SizedBox(width: 10),
                      _buildModalToggle(
                        "Income",
                        selectedType == 'Income',
                        _accentGreen,
                        () => setModalState(() => selectedType = 'Income'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 22),
                    decoration: _inputStyle(
                      "Amount (In JD)",
                      Icons.attach_money,
                    ),
                  ),
                  const SizedBox(height: 15),
                  FutureBuilder<List<WalletModel>>(
                    future: _supabaseService.getWallets(),
                    builder: (context, snapshot) {
                      return DropdownButtonFormField<String>(
                        dropdownColor: _cardColor,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputStyle(
                          "Select Account",
                          Icons.account_balance_wallet,
                        ),
                        items: snapshot.data
                            ?.map(
                              (w) => DropdownMenuItem(
                                value: w.id,
                                child: Text(w.name),
                              ),
                            )
                            .toList(),
                        onChanged: (val) => selectedWalletId = val,
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: descController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputStyle("Description", Icons.edit),
                  ),
                  const SizedBox(height: 25),
                  ElevatedButton(
                    onPressed: () async {
                      if (amountController.text.isNotEmpty &&
                          selectedWalletId != null) {
                        await _supabaseService.createTransaction(
                          walletId: selectedWalletId!,
                          amount: double.parse(amountController.text),
                          type: selectedType,
                          description: descController.text.isEmpty
                              ? selectedType
                              : descController.text,
                        );
                        if (!mounted) return;
                        Navigator.pop(context);
                        refreshDashboard(); // Refresh all data instantly
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentGreen,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                      "SAVE TRANSACTION",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            );
          },
        );
      },
    );
  }

  InputDecoration _inputStyle(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.grey),
    prefixIcon: Icon(icon, color: _accentGreen),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: Colors.white10),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: _accentGreen),
    ),
  );

  Widget _buildModalToggle(
    String label,
    bool isSelected,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? color : Colors.white10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

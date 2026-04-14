// lib/screens/dashboard_screen.dart

import 'package:final_project/screens/ai_assistant_screen.dart';
import 'package:final_project/screens/analytics_screen.dart';
import 'package:final_project/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/category_model.dart';
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

  // Global keys to sync states across tabs
  final GlobalKey<_DashboardMainContentState> _mainContentKey = GlobalKey();
  final GlobalKey<MyAccountScreenState> _accountsKey =
      GlobalKey(); // Added Account Key

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    // Initialize screens using late final to prevent recreation, and inject keys
    _screens = [
      _DashboardMainContent(key: _mainContentKey),
      MyAccountScreen(key: _accountsKey), // Link the key to the screen
      const AnalyticsScreen(),
      const TodoListScreen(),
      const SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
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
        // Sync Data when switching tabs
        if (index == 0) {
          _mainContentKey.currentState?.refreshDashboard();
        } else if (index == 1) {
          _accountsKey.currentState
              ?.refreshAccounts(); // Refresh Accounts Screen Data
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

  late Future<Map<String, double>> _balancesFuture;
  late Future<List<Map<String, dynamic>>> _transactionsFuture;
  late Future<Map<String, double>> _monthlySummaryFuture;

  String _currencySymbol = "JD";
  double _exchangeRate = 1.0;

  static const Color _bgColor = Color(0xFF061414);
  static const Color _cardColor = Color(0xFF111D1D);
  static const Color _accentGreen = Color(0xFF34EAB9);
  static const Color _expenseRed = Color(0xFFFF6B6B);
  static const Color _transferBlue = Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    _balancesFuture = _supabaseService.getBalancesByType();
    _transactionsFuture = _supabaseService.getTransactions();
    _monthlySummaryFuture = _supabaseService.getFilteredSummary('Month');
    loadCurrencyPreference();
  }

  void refreshDashboard() {
    loadCurrencyPreference();
    setState(() {
      _balancesFuture = _supabaseService.getBalancesByType();
      _transactionsFuture = _supabaseService.getTransactions();
      _monthlySummaryFuture = _supabaseService.getFilteredSummary('Month');
    });
  }

  Future<void> loadCurrencyPreference() async {
    final prefs = await SharedPreferences.getInstance();
    String savedCurrency = prefs.getString('currency') ?? "JOD (JD)";

    setState(() {
      if (savedCurrency.contains("USD")) {
        _currencySymbol = "\$";
        _exchangeRate = 1.41;
      } else {
        _currencySymbol = "JD";
        _exchangeRate = 1.0;
      }
    });
  }

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
        heroTag: 'dashboard_add_btn',
        onPressed: _showAddTransactionModal,
        backgroundColor: _accentGreen,
        child: const Icon(Icons.add, color: Colors.black, size: 30),
      ),
    );
  }

  /// UI: Centralized Total Balance Card showing Total and always showing Cash balance
  Widget _buildTotalBalanceCard() {
    return FutureBuilder<Map<String, double>>(
      future: _balancesFuture,
      builder: (context, snapshot) {
        double total = snapshot.data?['Total'] ?? 0.0;
        double cash = snapshot.data?['Cash'] ?? 0.0;

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
                _formatAmount(total),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.money, color: Colors.black54, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      "Cash: ${_formatAmount(cash)}",
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnalyticsSection() {
    return FutureBuilder<Map<String, double>>(
      future: _monthlySummaryFuture,
      builder: (context, snapshot) {
        double income = snapshot.data?['Income'] ?? 0.0;
        double expense = snapshot.data?['Expense'] ?? 0.0;

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

        final recentTransactions = snapshot.data!.take(5).toList();

        return Column(
          children: recentTransactions.map((tx) {
            final bool isExpense = tx['type'] == 'Expense';
            final String walletName = tx['wallets']?['name'] ?? 'Account';

            return _buildTransactionItem(
              tx['description'] ?? "Transaction",
              "${tx['created_at'].toString().split('T')[0]} • $walletName",
              "${isExpense ? '-' : '+'}${_formatAmount((tx['amount'] as num).toDouble())}",
              isExpense ? _expenseRed : _accentGreen,
              isExpense: isExpense,
            );
          }).toList(),
        );
      },
    );
  }

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
        onPressed: () {},
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
    String? targetWalletId;
    int? selectedCategoryId;

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
                      const SizedBox(width: 10),
                      _buildModalToggle(
                        "Transfer",
                        selectedType == 'Transfer',
                        _transferBlue,
                        () => setModalState(() => selectedType = 'Transfer'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
                    ],
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
                      return Column(
                        children: [
                          DropdownButtonFormField<String>(
                            dropdownColor: _cardColor,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputStyle(
                              selectedType == 'Transfer'
                                  ? "From Account"
                                  : "Select Account",
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
                          ),

                          if (selectedType == 'Transfer') ...[
                            const SizedBox(height: 15),
                            DropdownButtonFormField<String>(
                              dropdownColor: _cardColor,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputStyle(
                                "To Account",
                                Icons.account_balance,
                              ),
                              items: snapshot.data
                                  ?.map(
                                    (w) => DropdownMenuItem(
                                      value: w.id,
                                      child: Text(w.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) => targetWalletId = val,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 15),

                  if (selectedType != 'Transfer') ...[
                    Row(
                      children: [
                        Expanded(
                          child: FutureBuilder<List<CategoryModel>>(
                            future: _supabaseService.getCategories(),
                            builder: (context, snapshot) {
                              return DropdownButtonFormField<int>(
                                dropdownColor: _cardColor,
                                style: const TextStyle(color: Colors.white),
                                decoration: _inputStyle(
                                  "Select Category",
                                  Icons.category,
                                ),
                                items: snapshot.data
                                    ?.map(
                                      (cat) => DropdownMenuItem<int>(
                                        value: cat.id,
                                        child: Text(cat.name),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  setModalState(() {
                                    selectedCategoryId = val;
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: _accentGreen.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: _accentGreen),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.add, color: _accentGreen),
                            onPressed: () {
                              _showAddNewCategoryDialog(context, setModalState);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                  ],

                  TextField(
                    controller: descController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputStyle("Description", Icons.edit),
                  ),
                  const SizedBox(height: 25),

                  ElevatedButton(
                    onPressed: () async {
                      double parsedAmount =
                          double.tryParse(amountController.text) ?? 0.0;

                      if (parsedAmount <= 0 || selectedWalletId == null) {
                        _showError(
                          context,
                          "Please fill required fields with valid amounts.",
                        );
                        return;
                      }

                      if (selectedType == 'Transfer') {
                        if (targetWalletId == null ||
                            selectedWalletId == targetWalletId) {
                          _showError(
                            context,
                            "Please select two different accounts for the transfer.",
                          );
                          return;
                        }
                      } else if (selectedCategoryId == null) {
                        _showError(context, "Please select a category.");
                        return;
                      }

                      if (selectedType == 'Expense' ||
                          selectedType == 'Transfer') {
                        final wallets = await _supabaseService.getWallets();
                        final sourceWallet = wallets.firstWhere(
                          (w) => w.id == selectedWalletId,
                        );

                        if (parsedAmount > sourceWallet.balance) {
                          _showError(
                            context,
                            "Insufficient balance in the source account.",
                          );
                          return;
                        }
                      }

                      try {
                        if (selectedType == 'Transfer') {
                          final cats = await _supabaseService.getCategories();
                          final transferCategory = cats.firstWhere(
                            (c) => c.name.toLowerCase() == 'transfer',
                            orElse: () => cats.first,
                          );

                          await _supabaseService.transferFunds(
                            fromWalletId: selectedWalletId!,
                            toWalletId: targetWalletId!,
                            amount: parsedAmount,
                            description: descController.text.isEmpty
                                ? 'Transfer'
                                : descController.text,
                            categoryId: transferCategory.id,
                          );
                        } else {
                          await _supabaseService.createTransaction(
                            walletId: selectedWalletId!,
                            categoryId: selectedCategoryId!,
                            amount: parsedAmount,
                            type: selectedType,
                            description: descController.text.isEmpty
                                ? selectedType
                                : descController.text,
                          );
                        }

                        if (!mounted) return;
                        Navigator.pop(context);
                        refreshDashboard();
                      } catch (e) {
                        _showError(
                          context,
                          "An error occurred while saving the transaction.",
                        );
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

  void _showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.left),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _showAddNewCategoryDialog(
    BuildContext context,
    StateSetter setModalState,
  ) {
    final categoryNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _cardColor,
          title: const Text(
            "Add New Category",
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: categoryNameController,
            style: const TextStyle(color: Colors.white),
            decoration: _inputStyle("Category Name", Icons.edit),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _accentGreen),
              onPressed: () async {
                if (categoryNameController.text.isNotEmpty) {
                  await _supabaseService.addCustomCategory(
                    categoryNameController.text.trim(),
                    'Expense',
                  );

                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                    setModalState(() {});
                  }
                }
              },
              child: const Text(
                "Save",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
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

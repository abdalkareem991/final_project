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

  final GlobalKey<_DashboardMainContentState> _mainContentKey = GlobalKey();
  final GlobalKey<MyAccountScreenState> _accountsKey = GlobalKey();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      _DashboardMainContent(
        key: _mainContentKey,
        onTransactionChanged: () {
          if (_accountsKey.currentState != null) {
            _accountsKey.currentState!.refreshAccounts();
          }
        },
      ),
      MyAccountScreen(key: _accountsKey),
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
        if (index == 0) {
          _mainContentKey.currentState?.refreshDashboard();
        } else if (index == 1) {
          _accountsKey.currentState?.refreshAccounts();
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
  final VoidCallback? onTransactionChanged;

  const _DashboardMainContent({super.key, this.onTransactionChanged});

  @override
  State<_DashboardMainContent> createState() => _DashboardMainContentState();
}

class _DashboardMainContentState extends State<_DashboardMainContent> {
  final _supabaseService = SupabaseService();

  // STREAMS INTEGRATION: Replaced Futures with Streams for real-time reactivity
  late Stream<Map<String, double>> _balancesStream;
  late Stream<List<Map<String, dynamic>>> _transactionsStream;

  final Set<String> _hiddenTransactions = {};
  bool _showHidden = false;

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
    // Logic: Initialize Real-time Data Streams from Supabase[cite: 9]
    _balancesStream = _supabaseService.getBalancesStream();
    _transactionsStream = _supabaseService.getTransactionsStream();
    loadCurrencyPreference();
  }

  void refreshDashboard() {
    loadCurrencyPreference();
    setState(() {
      _balancesStream = _supabaseService.getBalancesStream();
      _transactionsStream = _supabaseService.getTransactionsStream();
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
              _buildLiveTotalBalanceCard(),
              const SizedBox(height: 20),
              _buildAnalyticsSection(),
              const SizedBox(height: 25),
              _buildRecentTransactionsHeader(),
              _buildLiveTransactionsList(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'dashboard_add_btn',
        onPressed: () => _showTransactionModal(),
        backgroundColor: _accentGreen,
        child: const Icon(Icons.add, color: Colors.black, size: 30),
      ),
    );
  }

  // UPDATED: Now uses StreamBuilder for live balance updates[cite: 14]
  Widget _buildLiveTotalBalanceCard() {
    return StreamBuilder<Map<String, double>>(
      stream: _balancesStream,
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
    // Note: Monthly summary still fetches using Future to save bandwidth on every update,
    // but you can refresh it via the pull-to-refresh.
    return FutureBuilder<Map<String, double>>(
      future: _supabaseService.getFilteredSummary('Month'),
      builder: (context, snapshot) {
        double income = snapshot.data?['Income'] ?? 0.0;
        double expense = snapshot.data?['Expense'] ?? 0.0;

        double incomeProgress = (income > 0) ? 1.0 : 0.0;
        double expenseProgress = (expense > 0) ? 1.0 : 0.0;

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

  // UPDATED: StreamBuilder for automatic transaction logging display[cite: 14]
  Widget _buildLiveTransactionsList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _transactionsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: _accentGreen),
            ),
          );
        }

        final visibleTransactions = snapshot.data
            ?.where(
              (tx) =>
                  _showHidden ||
                  !_hiddenTransactions.contains(tx['id'].toString()),
            )
            .toList();

        if (visibleTransactions == null || visibleTransactions.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              "No transactions yet.",
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        final recentTransactions = visibleTransactions.take(5).toList();

        return Column(
          children: recentTransactions.map((tx) {
            final bool isHidden = _hiddenTransactions.contains(
              tx['id'].toString(),
            );
            return _buildTransactionItem(tx, isHidden: isHidden);
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
        color: _accentGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accentGreen.withOpacity(0.3)),
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
      Row(
        children: [
          if (_hiddenTransactions.isNotEmpty)
            IconButton(
              icon: Icon(
                _showHidden ? Icons.visibility : Icons.visibility_off,
                color: Colors.grey,
                size: 20,
              ),
              tooltip: _showHidden ? "Hide invisible" : "Show hidden",
              onPressed: () {
                setState(() {
                  _showHidden = !_showHidden;
                });
              },
            ),
          TextButton(
            onPressed: () {},
            child: const Text("See All", style: TextStyle(color: _accentGreen)),
          ),
        ],
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
    Map<String, dynamic> tx, {
    bool isHidden = false,
  }) {
    final bool isInternalTransfer = tx['is_internal_transfer'] == true;
    final bool isExpense = tx['type'] == 'Expense';

    final String walletName =
        tx['wallet_name']?.toString() ?? 'Unknown Account';
    final String categoryName =
        tx['category_name']?.toString() ?? 'Uncategorized';

    final Color iconColor = isInternalTransfer
        ? _transferBlue
        : isExpense
        ? _expenseRed
        : _accentGreen;

    final IconData transactionIcon = isInternalTransfer
        ? Icons.swap_horiz
        : isExpense
        ? Icons.arrow_upward
        : Icons.arrow_downward;

    final String title = isInternalTransfer
        ? "Internal Transfer"
        : (tx['description'] ?? "Transaction");

    final String date = tx['created_at'].toString().split('T')[0];

    final String amount = isInternalTransfer
        ? _formatAmount((tx['amount'] as num).toDouble())
        : "${isExpense ? '-' : '+'}${_formatAmount((tx['amount'] as num).toDouble())}";

    final String secondaryText = isInternalTransfer
        ? isExpense
              ? "$date • From: $walletName"
              : "$date • To: $walletName"
        : "$date • $walletName • $categoryName";

    return Opacity(
      opacity: isHidden ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(15),
          border: isHidden
              ? Border.all(color: Colors.grey.withOpacity(0.3), width: 1)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () => _showTransactionDetailsDialog(tx),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(transactionIcon, color: iconColor, size: 20),
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
                          secondaryText,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    amount,
                    style: TextStyle(
                      color: iconColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 5),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert,
                      color: Colors.grey,
                      size: 20,
                    ),
                    color: _bgColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    onSelected: (value) async {
                      if (value == 'details') {
                        _showTransactionDetailsDialog(tx);
                      } else if (value == 'edit') {
                        _showTransactionModal(existingTx: tx);
                      } else if (value == 'hide') {
                        setState(() {
                          _hiddenTransactions.add(tx['id'].toString());
                        });
                      } else if (value == 'unhide') {
                        setState(() {
                          _hiddenTransactions.remove(tx['id'].toString());
                        });
                      } else if (value == 'delete') {
                        await _deleteTransactionWithConfirm(tx);
                      }
                    },
                    itemBuilder: (BuildContext context) => [
                      const PopupMenuItem(
                        value: 'details',
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.blueAccent,
                              size: 18,
                            ),
                            SizedBox(width: 10),
                            Text(
                              "Details",
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      if (!isInternalTransfer)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit,
                                color: Colors.orangeAccent,
                                size: 18,
                              ),
                              SizedBox(width: 10),
                              Text(
                                "Edit",
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: isHidden ? 'unhide' : 'hide',
                        child: Row(
                          children: [
                            Icon(
                              isHidden
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.grey,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isHidden ? "Unhide" : "Hide",
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            SizedBox(width: 10),
                            Text(
                              "Delete",
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showTransactionDetailsDialog(Map<String, dynamic> tx) {
    final String walletName =
        tx['wallet_name']?.toString() ??
        (tx['wallets'] is Map && tx['wallets']['name'] != null
            ? tx['wallets']['name'].toString()
            : 'Unknown Account');

    final String categoryName =
        tx['category_name']?.toString() ??
        (tx['categories'] is Map && tx['categories']['name'] != null
            ? tx['categories']['name'].toString()
            : 'Uncategorized');
    final bool isInternalTransfer = tx['is_internal_transfer'] == true;
    final bool isExpense = tx['type'] == 'Expense';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Center(
          child: Text(
            "Transaction Details",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(color: Colors.white10),
            const SizedBox(height: 10),
            _buildDetailRow("Description", tx['description'] ?? 'N/A'),
            _buildDetailRow(
              "Amount",
              _formatAmount((tx['amount'] as num).toDouble()),
              valueColor: isInternalTransfer
                  ? _transferBlue
                  : isExpense
                  ? _expenseRed
                  : _accentGreen,
            ),
            _buildDetailRow(
              "Type",
              isInternalTransfer ? "Internal Transfer" : tx['type'],
            ),
            _buildDetailRow("Account", walletName),
            _buildDetailRow("Category", categoryName),
            _buildDetailRow("Date", tx['created_at'].toString().split('T')[0]),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accentGreen),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Close",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    Color valueColor = Colors.white,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTransactionWithConfirm(Map<String, dynamic> tx) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text(
          "Delete Transaction",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Are you sure? This will reverse the account balance.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabaseService.deleteTransactionSmart(tx);
        refreshDashboard();
        widget.onTransactionChanged?.call();
      } catch (e) {
        _showError(context, "Error deleting: $e");
      }
    }
  }

  void _showTransactionModal({Map<String, dynamic>? existingTx}) {
    final isEditing = existingTx != null;
    final amountController = TextEditingController(
      text: isEditing ? existingTx['amount'].toString() : '',
    );
    final descController = TextEditingController(
      text: isEditing ? existingTx['description'] : '',
    );

    String selectedType = isEditing ? existingTx['type'] : 'Expense';
    String? selectedWalletId = isEditing ? existingTx['wallet_id'] : null;
    String? targetWalletId;
    int? selectedCategoryId = isEditing ? existingTx['category_id'] : null;

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
                  Text(
                    isEditing ? "Edit Transaction" : "New Transaction",
                    style: const TextStyle(
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
                      if (!isEditing) ...[
                        const SizedBox(width: 10),
                        _buildModalToggle(
                          "Transfer",
                          selectedType == 'Transfer',
                          _transferBlue,
                          () => setModalState(() => selectedType = 'Transfer'),
                        ),
                      ],
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
                            initialValue: selectedWalletId,
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
                          if (selectedType == 'Transfer' && !isEditing) ...[
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
                                initialValue: selectedCategoryId,
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
                                onChanged: (val) => setModalState(
                                  () => selectedCategoryId = val,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: _accentGreen.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: _accentGreen),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.add, color: _accentGreen),
                            onPressed: () => _showAddNewCategoryDialog(
                              context,
                              setModalState,
                            ),
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
                          "Fill required fields with valid amounts.",
                        );
                        return;
                      }
                      if (selectedType == 'Transfer' && !isEditing) {
                        if (targetWalletId == null ||
                            selectedWalletId == targetWalletId) {
                          _showError(
                            context,
                            "Select two different accounts for transfer.",
                          );
                          return;
                        }
                      } else if (selectedCategoryId == null) {
                        _showError(context, "Please select a category.");
                        return;
                      }

                      try {
                        if (isEditing) {
                          await _supabaseService.updateTransaction(
                            oldTx: existingTx,
                            newTx: {
                              'wallet_id': selectedWalletId,
                              'category_id': selectedCategoryId,
                              'amount': parsedAmount,
                              'type': selectedType,
                              'description': descController.text.isEmpty
                                  ? selectedType
                                  : descController.text,
                            },
                          );
                        } else {
                          if (selectedType == 'Transfer') {
                            await _supabaseService.transferFunds(
                              fromWalletId: selectedWalletId!,
                              toWalletId: targetWalletId!,
                              amount: parsedAmount,
                              description: descController.text,
                            );
                          } else {
                            await _supabaseService.createTransaction(
                              walletId: selectedWalletId!,
                              categoryId: selectedCategoryId!,
                              amount: parsedAmount,
                              type: selectedType,
                              description: descController.text,
                            );
                          }
                        }
                        Navigator.pop(context);
                        refreshDashboard();
                        widget.onTransactionChanged?.call();
                      } catch (e) {
                        _showError(context, e.toString());
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentGreen,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Text(
                      isEditing ? "UPDATE TRANSACTION" : "SAVE TRANSACTION",
                      style: const TextStyle(
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
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showAddNewCategoryDialog(
    BuildContext context,
    StateSetter setModalState,
  ) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text(
          "Add Category",
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: _inputStyle("Category Name", Icons.edit),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await _supabaseService.addCustomCategory(
                  nameController.text.trim(),
                  'Expense',
                );
                Navigator.pop(dialogContext);
                setModalState(() {});
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
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
            color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
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

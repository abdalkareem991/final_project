// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_text.dart';
import '../core/app_theme.dart';
import '../models/category_model.dart';
import '../models/wallet_model.dart';
import '../services/supabase_service.dart';

/// Full transaction history view with search, filters, and row-level actions.
class TransactionsHistoryScreen extends StatefulWidget {
  const TransactionsHistoryScreen({super.key});

  @override
  State<TransactionsHistoryScreen> createState() =>
      _TransactionsHistoryScreenState();
}

class _TransactionsHistoryScreenState extends State<TransactionsHistoryScreen> {
  // Local UI state for filtering the live transaction stream.
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();

  AppThemeColors get _colors => context.themeColors;
  Color get _bgColor => _colors.background;
  Color get _cardColor => _colors.surface;
  Color get _accentGreen => _colors.primary;
  Color get _textColor => _colors.textPrimary;
  Color get _secondaryTextColor => _colors.textSecondary;
  Color get _mutedTextColor => _colors.textMuted;
  Color get _expenseRed => _colors.expense;
  Color get _transferBlue => _colors.transfer;

  String _searchText = '';
  String _typeFilter = 'All';
  bool _showHidden = false;
  final List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _transactionsError;
  int _page = 0;
  static const int _pageSize = 25;

  @override
  void initState() {
    super.initState();
    _loadTransactions(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions({bool reset = false}) async {
    if (_isLoadingMore) return;

    if (reset) {
      setState(() {
        _page = 0;
        _hasMore = true;
        _transactionsError = null;
        _isLoading = _transactions.isEmpty;
      });
    } else if (!_hasMore) {
      return;
    }

    setState(() => _isLoadingMore = true);

    try {
      final page = reset ? 0 : _page;
      final rows = await _supabaseService.getTransactionsPage(
        page: page,
        pageSize: _pageSize,
        includeHidden: _showHidden,
      );

      if (!mounted) return;
      setState(() {
        if (reset) _transactions.clear();
        _transactions.addAll(rows);
        _page = page + 1;
        _hasMore = rows.length == _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
        _transactionsError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _transactionsError = error.toString();
      });
    }
  }

  Future<void> _refreshTransactions() {
    return _loadTransactions(reset: true);
  }

  /// Applies text search, type filters, and internal transfer filtering.
  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> data) {
    return data.where((tx) {
      final description = (tx['description'] ?? '').toString().toLowerCase();
      final walletName = (tx['wallet_name'] ?? '').toString().toLowerCase();
      final categoryName = (tx['category_name'] ?? '').toString().toLowerCase();
      final merchantName = (tx['merchant_name'] ?? '').toString().toLowerCase();
      final type = (tx['type'] ?? '').toString();

      final search = _searchText.toLowerCase();

      final matchesSearch =
          search.isEmpty ||
          description.contains(search) ||
          walletName.contains(search) ||
          categoryName.contains(search) ||
          merchantName.contains(search);

      final matchesType =
          _typeFilter == 'All' ||
          (_typeFilter == 'Internal Transfer' &&
              tx['is_internal_transfer'] == true) ||
          type == _typeFilter;

      return matchesSearch && matchesType;
    }).toList();
  }

  String _formatAmount(double amount) {
    return "JD ${amount.toStringAsFixed(2)}";
  }

  String _formatDateTime(dynamic rawDate) {
    if (rawDate == null) return '';
    final date = DateTime.tryParse(rawDate.toString());
    if (date == null) return rawDate.toString();

    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} $hour:$minute";
  }

  // ---------------------------------------------------------------------------
  // Transaction rows and row actions
  // ---------------------------------------------------------------------------

  Widget _buildTransactionTile(Map<String, dynamic> tx) {
    final bool isInternalTransfer = tx['is_internal_transfer'] == true;
    final bool isExpense = tx['type'] == 'Expense';
    final bool isHidden = tx['is_hidden'] == true;

    final String walletName =
        tx['wallet_name']?.toString() ?? 'Unknown Account';
    final String categoryName =
        tx['category_name']?.toString() ?? 'Uncategorized';

    final String title = isInternalTransfer
        ? context.t("Internal Transfer", "تحويل داخلي")
        : tx['description'] ?? '';

    final String subtitle = isInternalTransfer
        ? isExpense
              ? "${context.t("From", "من")}: $walletName"
              : "${context.t("To", "إلى")}: $walletName"
        : "$walletName • $categoryName";

    final Color color = isInternalTransfer
        ? _transferBlue
        : isExpense
        ? _expenseRed
        : _accentGreen;

    final IconData icon = isInternalTransfer
        ? Icons.swap_horiz
        : isExpense
        ? Icons.arrow_upward
        : Icons.arrow_downward;

    final String sign = isInternalTransfer
        ? ''
        : isExpense
        ? '-'
        : '+';

    return Opacity(
      opacity: isHidden ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(16),
          border: isHidden ? Border.all(color: _colors.subtleBorder) : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showTransactionDetailsDialog(tx),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withOpacity(0.12),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.isEmpty
                              ? context.t("Transaction", "حركة")
                              : title,
                          style: TextStyle(
                            color: _textColor,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: _secondaryTextColor,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDateTime(tx['date'] ?? tx['created_at']),
                          style: TextStyle(
                            color: _mutedTextColor,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    "$sign${_formatAmount((tx['amount'] as num).toDouble())}",
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: _mutedTextColor,
                      size: 20,
                    ),
                    color: _cardColor,
                    onSelected: (value) async {
                      if (value == 'details') {
                        _showTransactionDetailsDialog(tx);
                      } else if (value == 'edit') {
                        _showTransactionEditModal(tx);
                      } else if (value == 'hide') {
                        await _supabaseService.hideTransaction(
                          tx['id'].toString(),
                        );
                        if (mounted) await _refreshTransactions();
                      } else if (value == 'unhide') {
                        await _supabaseService.unhideTransaction(
                          tx['id'].toString(),
                        );
                        if (mounted) await _refreshTransactions();
                      } else if (value == 'delete') {
                        await _deleteTransactionWithConfirm(tx);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'details',
                        child: _menuRow(
                          Icons.info_outline,
                          _transferBlue,
                          context.t("Details", "التفاصيل"),
                        ),
                      ),
                      if (!isInternalTransfer)
                        PopupMenuItem(
                          value: 'edit',
                          child: _menuRow(
                            Icons.edit,
                            Colors.orangeAccent,
                            context.t("Edit", "تعديل"),
                          ),
                        ),
                      PopupMenuItem(
                        value: isHidden ? 'unhide' : 'hide',
                        child: _menuRow(
                          isHidden ? Icons.visibility : Icons.visibility_off,
                          _mutedTextColor,
                          isHidden
                              ? context.t("Unhide", "إظهار")
                              : context.t("Hide", "إخفاء"),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: _menuRow(
                          Icons.delete,
                          _expenseRed,
                          context.t("Delete", "حذف"),
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

  Widget _menuRow(IconData icon, Color color, String label) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: _textColor)),
      ],
    );
  }

  /// Displays all persisted transaction metadata in a compact dialog.
  void _showTransactionDetailsDialog(Map<String, dynamic> tx) {
    final bool isInternalTransfer = tx['is_internal_transfer'] == true;
    final bool isExpense = tx['type'] == 'Expense';
    final walletName = tx['wallet_name']?.toString() ?? 'Unknown Account';
    final categoryName = tx['category_name']?.toString() ?? 'Uncategorized';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          context.t("Transaction Details", "تفاصيل الحركة"),
          style: TextStyle(color: _textColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _detailRow(
              context.t("Description", "الوصف"),
              tx['description']?.toString() ?? '',
            ),
            _detailRow(
              context.t("Amount", "المبلغ"),
              _formatAmount((tx['amount'] as num).toDouble()),
              valueColor: isInternalTransfer
                  ? _transferBlue
                  : isExpense
                  ? _expenseRed
                  : _accentGreen,
            ),
            _detailRow(
              context.t("Type", "النوع"),
              isInternalTransfer
                  ? context.t("Internal Transfer", "تحويل داخلي")
                  : context.enumText(tx['type']?.toString() ?? ''),
            ),
            _detailRow(context.t("Account", "الحساب"), walletName),
            _detailRow(context.t("Category", "الفئة"), categoryName),
            _detailRow(
              context.t("Date", "التاريخ"),
              _formatDateTime(tx['date'] ?? tx['created_at']),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.t("Close", "إغلاق")),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: _mutedTextColor)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: valueColor ?? _textColor,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Deletes a transaction after confirmation and lets the service reverse it.
  Future<void> _deleteTransactionWithConfirm(Map<String, dynamic> tx) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text(
          context.t("Delete Transaction", "حذف الحركة"),
          style: TextStyle(color: _textColor),
        ),
        content: Text(
          context.t(
            "This will reverse the account balance. Continue?",
            "سيؤدي ذلك إلى عكس رصيد الحساب. هل تريد المتابعة؟",
          ),
          style: TextStyle(color: _secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t("Cancel", "إلغاء")),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _expenseRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t("Delete", "حذف")),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _supabaseService.deleteTransactionSmart(tx);
      if (mounted) await _refreshTransactions();
    } catch (e) {
      _showSnack(context.t("Delete failed: $e", "فشل الحذف: $e"));
    }
  }

  // ---------------------------------------------------------------------------
  // Transaction editing
  // ---------------------------------------------------------------------------

  /// Edits an existing transaction in place; automated SMS hashes are preserved.
  void _showTransactionEditModal(Map<String, dynamic> existingTx) {
    final amountController = TextEditingController(
      text: existingTx['amount'].toString(),
    );
    final descController = TextEditingController(
      text: existingTx['description']?.toString() ?? '',
    );

    String selectedType = existingTx['type']?.toString() ?? 'Expense';
    String? selectedWalletId = existingTx['wallet_id']?.toString();
    int? selectedCategoryId = existingTx['category_id'] is int
        ? existingTx['category_id'] as int
        : int.tryParse(existingTx['category_id']?.toString() ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t("Edit Transaction", "تعديل الحركة"),
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _typeChip(
                          context.t("Expense", "مصروف"),
                          selectedType == 'Expense',
                          _expenseRed,
                          () => setModalState(() => selectedType = 'Expense'),
                        ),
                        const SizedBox(width: 10),
                        _typeChip(
                          context.t("Income", "دخل"),
                          selectedType == 'Income',
                          _accentGreen,
                          () => setModalState(() => selectedType = 'Income'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d*'),
                        ),
                      ],
                      style: TextStyle(color: _textColor),
                      decoration: _inputStyle(
                        context.t("Amount (JD)", "المبلغ بالدينار"),
                        Icons.payments,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FutureBuilder<List<WalletModel>>(
                      future: _supabaseService.getWallets(),
                      builder: (context, snapshot) {
                        final wallets = snapshot.data ?? [];
                        final currentValue =
                            wallets.any(
                              (wallet) => wallet.id == selectedWalletId,
                            )
                            ? selectedWalletId
                            : null;

                        return DropdownButtonFormField<String>(
                          initialValue: currentValue,
                          dropdownColor: _cardColor,
                          style: TextStyle(color: _textColor),
                          decoration: _inputStyle(
                            context.t("Account", "الحساب"),
                            Icons.account_balance_wallet,
                          ),
                          items: wallets
                              .map(
                                (wallet) => DropdownMenuItem(
                                  value: wallet.id,
                                  child: Text(wallet.name),
                                ),
                              )
                              .toList(),
                          onChanged: (val) => selectedWalletId = val,
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    FutureBuilder<List<CategoryModel>>(
                      future: _supabaseService.getCategories(),
                      builder: (context, snapshot) {
                        final categories = snapshot.data ?? [];
                        final currentValue =
                            categories.any(
                              (category) => category.id == selectedCategoryId,
                            )
                            ? selectedCategoryId
                            : null;

                        return DropdownButtonFormField<int>(
                          initialValue: currentValue,
                          dropdownColor: _cardColor,
                          style: TextStyle(color: _textColor),
                          decoration: _inputStyle(
                            context.t("Category", "الفئة"),
                            Icons.category,
                          ),
                          items: categories
                              .map(
                                (category) => DropdownMenuItem<int>(
                                  value: category.id,
                                  child: Text(category.name),
                                ),
                              )
                              .toList(),
                          onChanged: (val) => selectedCategoryId = val,
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: descController,
                      style: TextStyle(color: _textColor),
                      decoration: _inputStyle(
                        context.t("Description", "الوصف"),
                        Icons.edit,
                      ),
                    ),
                    const SizedBox(height: 22),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentGreen,
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        final amount =
                            double.tryParse(amountController.text.trim()) ?? 0;

                        if (amount <= 0 ||
                            selectedWalletId == null ||
                            selectedCategoryId == null) {
                          _showSnack(
                            context.t(
                              "Fill required fields with valid values.",
                              "املأ الحقول المطلوبة بقيم صحيحة.",
                            ),
                          );
                          return;
                        }

                        try {
                          await _supabaseService.updateTransaction(
                            oldTx: existingTx,
                            newTx: {
                              'wallet_id': selectedWalletId,
                              'category_id': selectedCategoryId,
                              'amount': amount,
                              'type': selectedType,
                              'description': descController.text.trim().isEmpty
                                  ? selectedType
                                  : descController.text.trim(),
                            },
                          );

                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                          if (mounted) await _refreshTransactions();
                        } catch (e) {
                          _showSnack(
                            context.t("Update failed: $e", "فشل التحديث: $e"),
                          );
                        }
                      },
                      child: Text(
                        context.t("UPDATE TRANSACTION", "تحديث الحركة"),
                        style: TextStyle(
                          color: _colors.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Shared form widgets
  // ---------------------------------------------------------------------------

  Widget _typeChip(
    String label,
    bool selected,
    Color color,
    VoidCallback onTap,
  ) {
    final selectedTextColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color : _cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? selectedTextColor : _textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputStyle(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _mutedTextColor),
      prefixIcon: Icon(icon, color: _accentGreen),
      filled: true,
      fillColor: _colors.field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _colors.subtleBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _colors.subtleBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _accentGreen, width: 2),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: _expenseRed),
    );
  }

  // ---------------------------------------------------------------------------
  // Filters and screen layout
  // ---------------------------------------------------------------------------

  Widget _buildFilterChip(String value) {
    final selected = _typeFilter == value;

    return ChoiceChip(
      label: Text(_filterLabel(value)),
      selected: selected,
      selectedColor: _accentGreen,
      backgroundColor: _cardColor,
      labelStyle: TextStyle(
        color: selected ? _colors.onPrimary : _textColor,
        fontWeight: FontWeight.bold,
      ),
      onSelected: (_) {
        setState(() => _typeFilter = value);
      },
    );
  }

  String _filterLabel(String value) {
    return switch (value) {
      'Internal Transfer' => context.t("Internal Transfer", "تحويل داخلي"),
      _ => context.enumText(value),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: Text(
          context.t("All Transactions", "كل الحركات"),
          style: TextStyle(color: _textColor, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showHidden ? Icons.visibility : Icons.visibility_off,
              color: _showHidden ? _accentGreen : _mutedTextColor,
            ),
            tooltip: _showHidden
                ? context.t("Hide hidden", "إخفاء المخفية")
                : context.t("Show hidden", "إظهار المخفية"),
            onPressed: () {
              setState(() => _showHidden = !_showHidden);
              _refreshTransactions();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: _textColor),
              decoration: InputDecoration(
                hintText: context.t(
                  "Search by account, category, merchant...",
                  "ابحث حسب الحساب أو الفئة أو المتجر...",
                ),
                hintStyle: TextStyle(color: _mutedTextColor),
                prefixIcon: Icon(Icons.search, color: _accentGreen),
                filled: true,
                fillColor: _cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() => _searchText = value);
              },
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildFilterChip('All'),
                const SizedBox(width: 8),
                _buildFilterChip('Income'),
                const SizedBox(width: 8),
                _buildFilterChip('Expense'),
                const SizedBox(width: 8),
                _buildFilterChip('Internal Transfer'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Stream.value(_transactions),
              builder: (context, snapshot) {
                if (_isLoading) {
                  return Center(
                    child: CircularProgressIndicator(color: _accentGreen),
                  );
                }

                if (_transactionsError != null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.t(
                            "Could not load transactions.",
                            "ØªØ¹Ø°Ø± ØªØ­Ù…ÙŠÙ„ Ø§Ù„Ø­Ø±ÙƒØ§Øª.",
                          ),
                          style: TextStyle(color: _mutedTextColor),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _refreshTransactions,
                          icon: Icon(Icons.refresh, color: _colors.onPrimary),
                          label: Text(
                            context.t("Retry", "Ø¥Ø¹Ø§Ø¯Ø© Ø§Ù„Ù…Ø­Ø§ÙˆÙ„Ø©"),
                            style: TextStyle(color: _colors.onPrimary),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentGreen,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final filtered = _applyFilters(snapshot.data!);

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      context.t(
                        "No transactions found.",
                        "لم يتم العثور على حركات.",
                      ),
                      style: TextStyle(color: _mutedTextColor),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    return _buildTransactionTile(filtered[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: (_hasMore || _isLoadingMore) && !_isLoading
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ElevatedButton.icon(
                  onPressed: _isLoadingMore
                      ? null
                      : () => _loadTransactions(reset: false),
                  icon: _isLoadingMore
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: _colors.onPrimary,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(Icons.expand_more, color: _colors.onPrimary),
                  label: Text(
                    _isLoadingMore
                        ? context.t("Loading...", "Ø¬Ø§Ø±ÙŠ Ø§Ù„ØªØ­Ù…ÙŠÙ„...")
                        : context.t("Load more", "ØªØ­Ù…ÙŠÙ„ Ø§Ù„Ù…Ø²ÙŠØ¯"),
                    style: TextStyle(
                      color: _colors.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGreen,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

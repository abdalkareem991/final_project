// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../core/app_text.dart';
import '../services/supabase_service.dart';

class TransactionsHistoryScreen extends StatefulWidget {
  const TransactionsHistoryScreen({super.key});

  @override
  State<TransactionsHistoryScreen> createState() =>
      _TransactionsHistoryScreenState();
}

class _TransactionsHistoryScreenState extends State<TransactionsHistoryScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();

  static const Color _bgColor = Color(0xFF061414);
  static const Color _cardColor = Color(0xFF111D1D);
  static const Color _accentGreen = Color(0xFF34EAB9);
  static const Color _expenseRed = Color(0xFFFF5252);
  static const Color _transferBlue = Color(0xFF3B82F6);

  String _searchText = '';
  String _typeFilter = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  Widget _buildTransactionTile(Map<String, dynamic> tx) {
    final bool isInternalTransfer = tx['is_internal_transfer'] == true;
    final bool isExpense = tx['type'] == 'Expense';

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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
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
                  title.isEmpty ? context.t("Transaction", "حركة") : title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(tx['created_at']),
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            "$sign${_formatAmount((tx['amount'] as num).toDouble())}",
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value) {
    final selected = _typeFilter == value;

    return ChoiceChip(
      label: Text(_filterLabel(value)),
      selected: selected,
      selectedColor: _accentGreen,
      backgroundColor: _cardColor,
      labelStyle: TextStyle(
        color: selected ? Colors.black : Colors.white,
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
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: context.t(
                  "Search by account, category, merchant...",
                  "ابحث حسب الحساب أو الفئة أو المتجر...",
                ),
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: _accentGreen),
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
              stream: _supabaseService.getTransactionsStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _accentGreen),
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
                      style: const TextStyle(color: Colors.grey),
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
    );
  }
}

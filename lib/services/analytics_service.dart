import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/analytics_model.dart';

class AnalyticsService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<CategoryAnalytics>> getIncomeAnalytics({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
    String? walletId,
  }) async {
    final report = await getAnalyticsReport(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      walletId: walletId,
    );
    return report.incomeCategories;
  }

  Future<List<CategoryAnalytics>> getExpenseAnalytics({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
    String? walletId,
  }) async {
    final report = await getAnalyticsReport(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      walletId: walletId,
    );
    return report.expenseCategories;
  }

  Future<double> getTotalIncome({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
    String? walletId,
  }) async {
    final report = await getAnalyticsReport(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      walletId: walletId,
    );
    return report.summary.totalIncome;
  }

  Future<double> getTotalExpenses({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
    String? walletId,
  }) async {
    final report = await getAnalyticsReport(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      walletId: walletId,
    );
    return report.summary.totalExpenses;
  }

  Future<AnalyticsReport> getAnalyticsReport({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
    String? walletId,
  }) async {
    try {
      final transactions = await _fetchFilteredTransactions(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        walletId: walletId,
      );

      return _buildReport(
        transactions,
        startDate: startDate,
        endDate: endDate,
        walletId: walletId,
      );
    } catch (error) {
      debugPrint('Analytics report error: $error');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchFilteredTransactions({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
    String? walletId,
  }) async {
    var query = _client
        .from('transactions')
        .select(
          'amount, type, category_id, wallet_id, date, is_hidden, '
          'is_internal_transfer, categories(id, name, icon, color)',
        )
        .eq('user_id', userId);

    if (startDate != null) {
      query = query.gte('date', startDate.toUtc().toIso8601String());
    }

    if (endDate != null) {
      query = query.lte('date', endDate.toUtc().toIso8601String());
    }

    if (walletId != null && walletId.isNotEmpty) {
      query = query.eq('wallet_id', walletId);
    }

    final response = await query.order('date', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  AnalyticsReport _buildReport(
    List<Map<String, dynamic>> transactions, {
    DateTime? startDate,
    DateTime? endDate,
    String? walletId,
  }) {
    final incomeTotals = <String, _CategoryBucket>{};
    final expenseTotals = <String, _CategoryBucket>{};
    double totalIncome = 0.0;
    double totalExpenses = 0.0;

    for (final transaction in transactions) {
      if (transaction['is_hidden'] == true ||
          transaction['is_internal_transfer'] == true) {
        continue;
      }

      final rawType = transaction['type']?.toString() ?? '';
      final type = _normalizeType(rawType);
      if (type != 'Income' && type != 'Expense') continue;

      final amount = ((transaction['amount'] as num?)?.toDouble() ?? 0.0).abs();
      if (amount <= 0) continue;

      final categoryId =
          transaction['category_id']?.toString() ?? 'uncategorized';
      final category = transaction['categories'];
      final categoryName = category is Map
          ? category['name']?.toString() ?? 'Uncategorized'
          : 'Uncategorized';
      final icon = category is Map ? category['icon']?.toString() : null;
      final colorHex = category is Map ? category['color']?.toString() : null;

      final targetMap = type == 'Income' ? incomeTotals : expenseTotals;
      final current = targetMap.putIfAbsent(
        categoryId,
        () => _CategoryBucket(
          categoryId: categoryId,
          categoryName: categoryName,
          type: type,
          icon: icon,
          colorHex: colorHex,
        ),
      );
      current.totalAmount += amount;

      if (type == 'Income') {
        totalIncome += amount;
      } else {
        totalExpenses += amount;
      }
    }

    return AnalyticsReport(
      summary: AnalyticsSummary(
        totalIncome: totalIncome,
        totalExpenses: totalExpenses,
      ),
      incomeCategories: _toAnalyticsList(incomeTotals.values, totalIncome),
      expenseCategories: _toAnalyticsList(expenseTotals.values, totalExpenses),
      startDate: startDate,
      endDate: endDate,
      walletId: walletId,
    );
  }

  List<CategoryAnalytics> _toAnalyticsList(
    Iterable<_CategoryBucket> buckets,
    double typeTotal,
  ) {
    final items = buckets.map((bucket) {
      final percentage = typeTotal <= 0
          ? 0.0
          : double.parse(
              ((bucket.totalAmount / typeTotal) * 100).toStringAsFixed(1),
            );

      return CategoryAnalytics(
        categoryId: bucket.categoryId,
        categoryName: bucket.categoryName,
        totalAmount: bucket.totalAmount,
        percentage: percentage,
        type: bucket.type,
        icon: bucket.icon,
        colorHex: bucket.colorHex,
      );
    }).toList();

    items.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    return items;
  }

  String _normalizeType(String type) {
    final lowerType = type.toLowerCase().trim();
    if (lowerType == 'income') return 'Income';
    if (lowerType == 'expense') return 'Expense';
    return type;
  }
}

class _CategoryBucket {
  final String categoryId;
  final String categoryName;
  final String type;
  final String? icon;
  final String? colorHex;
  double totalAmount = 0.0;

  _CategoryBucket({
    required this.categoryId,
    required this.categoryName,
    required this.type,
    this.icon,
    this.colorHex,
  });
}

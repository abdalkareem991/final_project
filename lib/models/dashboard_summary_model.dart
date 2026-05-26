import 'analytics_model.dart';

class DashboardDebtSummary {
  final double totalDebtorAmount;
  final double totalCreditorAmount;
  final double netDebt;

  const DashboardDebtSummary({
    required this.totalDebtorAmount,
    required this.totalCreditorAmount,
    required this.netDebt,
  });

  factory DashboardDebtSummary.fromJson(Map<String, dynamic> json) {
    final debtor = _asDouble(json['total_debtor_amount']);
    final creditor = _asDouble(json['total_creditor_amount']);
    return DashboardDebtSummary(
      totalDebtorAmount: debtor,
      totalCreditorAmount: creditor,
      netDebt: _asDouble(json['net_debt'], fallback: debtor - creditor),
    );
  }

  Map<String, dynamic> toJson() => {
    'total_debtor_amount': totalDebtorAmount,
    'total_creditor_amount': totalCreditorAmount,
    'net_debt': netDebt,
  };
}

class DashboardSummary {
  final double totalBalance;
  final double bankBalance;
  final double cashBalance;
  final double monthlyIncome;
  final double monthlyExpenses;
  final List<Map<String, dynamic>> recentTransactions;
  final List<CategoryAnalytics> incomeCategorySummary;
  final List<CategoryAnalytics> expenseCategorySummary;
  final DashboardDebtSummary debtsSummary;
  final DateTime fetchedAt;

  const DashboardSummary({
    required this.totalBalance,
    required this.bankBalance,
    required this.cashBalance,
    required this.monthlyIncome,
    required this.monthlyExpenses,
    required this.recentTransactions,
    required this.incomeCategorySummary,
    required this.expenseCategorySummary,
    required this.debtsSummary,
    required this.fetchedAt,
  });

  factory DashboardSummary.empty() {
    return DashboardSummary(
      totalBalance: 0,
      bankBalance: 0,
      cashBalance: 0,
      monthlyIncome: 0,
      monthlyExpenses: 0,
      recentTransactions: const [],
      incomeCategorySummary: const [],
      expenseCategorySummary: const [],
      debtsSummary: const DashboardDebtSummary(
        totalDebtorAmount: 0,
        totalCreditorAmount: 0,
        netDebt: 0,
      ),
      fetchedAt: DateTime.now(),
    );
  }

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      totalBalance: _asDouble(json['total_balance']),
      bankBalance: _asDouble(json['bank_balance']),
      cashBalance: _asDouble(json['cash_balance']),
      monthlyIncome: _asDouble(json['monthly_income']),
      monthlyExpenses: _asDouble(json['monthly_expenses']),
      recentTransactions: _asMapList(json['recent_transactions']),
      incomeCategorySummary: _asAnalyticsList(
        json['income_category_summary'],
        fallbackType: 'Income',
      ),
      expenseCategorySummary: _asAnalyticsList(
        json['expense_category_summary'],
        fallbackType: 'Expense',
      ),
      debtsSummary: DashboardDebtSummary.fromJson(
        _asMap(json['debts_summary']),
      ),
      fetchedAt:
          DateTime.tryParse(json['generated_at']?.toString() ?? '') ??
          DateTime.tryParse(json['fetched_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'total_balance': totalBalance,
    'bank_balance': bankBalance,
    'cash_balance': cashBalance,
    'monthly_income': monthlyIncome,
    'monthly_expenses': monthlyExpenses,
    'recent_transactions': recentTransactions,
    'income_category_summary': incomeCategorySummary
        .map(_analyticsToJson)
        .toList(),
    'expense_category_summary': expenseCategorySummary
        .map(_analyticsToJson)
        .toList(),
    'debts_summary': debtsSummary.toJson(),
    'fetched_at': fetchedAt.toUtc().toIso8601String(),
  };
}

double _asDouble(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

// Helper function to convert a dynamic value to a map
Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

// Helper function to convert a dynamic value to a list of maps
List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is! List) return [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

// Helper function to convert a dynamic value to a list of CategoryAnalytics
List<CategoryAnalytics> _asAnalyticsList(
  dynamic value, {
  required String fallbackType,
}) {
  if (value is! List) return [];
  return value.whereType<Map>().map((item) {
    final json = Map<String, dynamic>.from(item);
    return CategoryAnalytics(
      categoryId: json['category_id']?.toString() ?? 'uncategorized',
      categoryName: json['category_name']?.toString() ?? 'Uncategorized',
      totalAmount: _asDouble(json['total_amount']),
      percentage: _asDouble(json['percentage']),
      type: json['type']?.toString() ?? fallbackType,
      icon: json['icon']?.toString(),
      colorHex: json['color']?.toString() ?? json['color_hex']?.toString(),
    );
  }).toList();
}

// Helper function to convert CategoryAnalytics to JSON
Map<String, dynamic> _analyticsToJson(CategoryAnalytics item) => {
  'category_id': item.categoryId,
  'category_name': item.categoryName,
  'total_amount': item.totalAmount,
  'percentage': item.percentage,
  'type': item.type,
  'icon': item.icon,
  'color': item.colorHex,
};

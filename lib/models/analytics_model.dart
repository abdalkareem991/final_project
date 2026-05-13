class CategoryAnalytics {
  final String categoryId;
  final String categoryName;
  final double totalAmount;
  final double percentage;
  final String type;
  final String? icon;
  final String? colorHex;

  const CategoryAnalytics({
    required this.categoryId,
    required this.categoryName,
    required this.totalAmount,
    required this.percentage,
    required this.type,
    this.icon,
    this.colorHex,
  });
}

class AnalyticsSummary {
  final double totalIncome;
  final double totalExpenses;

  const AnalyticsSummary({
    required this.totalIncome,
    required this.totalExpenses,
  });

  double get netBalance => totalIncome - totalExpenses;
}

class AnalyticsReport {
  final AnalyticsSummary summary;
  final List<CategoryAnalytics> incomeCategories;
  final List<CategoryAnalytics> expenseCategories;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? walletId;

  const AnalyticsReport({
    required this.summary,
    required this.incomeCategories,
    required this.expenseCategories,
    this.startDate,
    this.endDate,
    this.walletId,
  });
}

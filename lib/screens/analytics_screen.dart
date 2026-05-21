// lib/screens/analytics_screen.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_text.dart';
import '../core/app_theme.dart';
import '../models/analytics_model.dart';
import '../models/wallet_model.dart';
import '../services/analytics_service.dart';
import '../services/supabase_service.dart';

enum _AnalyticsPeriod { thisMonth, lastMonth, lastThreeMonths, custom }

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _analyticsService = AnalyticsService();
  final _supabaseService = SupabaseService();

  static const String _allWalletsValue = '__all_wallets__';

  late Future<AnalyticsReport> _reportFuture;
  late Future<List<WalletModel>> _walletsFuture;

  _AnalyticsPeriod _selectedPeriod = _AnalyticsPeriod.thisMonth;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String? _selectedWalletId;

  String _currencySymbol = "JD";
  double _exchangeRate = 1.0;

  AppThemeColors get _colors => context.themeColors;
  Color get _bgColor => _colors.background;
  Color get _cardColor => _colors.surface;
  Color get _fieldColor => _colors.field;
  Color get _accentGreen => _colors.primary;
  Color get _expenseRed => _colors.expense;
  Color get _textColor => _colors.textPrimary;
  Color get _secondaryTextColor => _colors.textSecondary;
  Color get _mutedTextColor => _colors.textMuted;
  Color get _infoBlue => _colors.transfer;

  late final List<Color> _incomePalette = [
    _accentGreen,
    Color(0xFF38BDF8),
    Color(0xFFA7F3D0),
    Color(0xFFFBBF24),
    Color(0xFF8B5CF6),
  ];

  late final List<Color> _expensePalette = [
    _expenseRed,
    Color(0xFFF59E0B),
    Color(0xFF3B82F6),
    Color(0xFFEC4899),
    Color(0xFF94A3B8),
    Color(0xFF22C55E),
  ];

  @override
  void initState() {
    super.initState();
    _walletsFuture = _supabaseService.getWallets();
    _reportFuture = _loadReport();
    _loadCurrencyPreference();
  }

  Future<void> _loadCurrencyPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCurrency = prefs.getString('currency') ?? "JOD (JD)";

    if (!mounted) return;
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

  Future<AnalyticsReport> _loadReport() {
    final userId = _supabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      return Future.error(Exception("User not logged in"));
    }

    final range = _effectiveDateRange();
    return _analyticsService.getAnalyticsReport(
      userId: userId,
      startDate: range.start,
      endDate: range.end,
      walletId: _selectedWalletId,
    );
  }

  Future<void> _refreshReport() async {
    final future = _loadReport();
    setState(() {
      _reportFuture = future;
    });

    try {
      await future;
    } catch (_) {
      // The FutureBuilder below owns the visible error state.
    }
  }

  void _reloadReport() {
    setState(() {
      _reportFuture = _loadReport();
    });
  }

  DateTimeRange _effectiveDateRange() {
    final now = DateTime.now();

    switch (_selectedPeriod) {
      case _AnalyticsPeriod.lastMonth:
        final start = DateTime(now.year, now.month - 1, 1);
        final end = DateTime(now.year, now.month, 0, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case _AnalyticsPeriod.lastThreeMonths:
        final start = DateTime(now.year, now.month - 2, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case _AnalyticsPeriod.custom:
        final fallbackStart = DateTime(now.year, now.month, 1);
        final fallbackEnd = DateTime(
          now.year,
          now.month + 1,
          0,
          23,
          59,
          59,
          999,
        );
        return DateTimeRange(
          start: _customStartDate ?? fallbackStart,
          end: _customEndDate ?? fallbackEnd,
        );
      case _AnalyticsPeriod.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
    }
  }

  String _formatAmount(double amount) {
    final converted = amount * _exchangeRate;
    if (_currencySymbol == "JD") {
      return "${converted.toStringAsFixed(2)} JD";
    }
    return "$_currencySymbol${converted.toStringAsFixed(2)}";
  }

  String _formatPercentage(double percentage) {
    if (percentage == percentage.roundToDouble()) {
      return "${percentage.toStringAsFixed(0)}%";
    }
    return "${percentage.toStringAsFixed(1)}%";
  }

  String _formatDateShort(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }

  String _selectedPeriodLabel() {
    switch (_selectedPeriod) {
      case _AnalyticsPeriod.thisMonth:
        return context.t("This Month", "هذا الشهر");
      case _AnalyticsPeriod.lastMonth:
        return context.t("Last Month", "الشهر الماضي");
      case _AnalyticsPeriod.lastThreeMonths:
        return context.t("Last 3 Months", "آخر 3 أشهر");
      case _AnalyticsPeriod.custom:
        final range = _effectiveDateRange();
        return "${_formatDateShort(range.start)} - ${_formatDateShort(range.end)}";
    }
  }

  Future<void> _selectPeriod(_AnalyticsPeriod period) async {
    if (period == _AnalyticsPeriod.custom) {
      final range = _effectiveDateRange();
      final pickedRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(DateTime.now().year + 5),
        initialDateRange: DateTimeRange(
          start: _customStartDate ?? range.start,
          end: _customEndDate ?? range.end,
        ),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: _accentGreen,
                surface: _cardColor,
                onSurface: _textColor,
              ),
            ),
            child: child!,
          );
        },
      );

      if (pickedRange == null || !mounted) return;

      setState(() {
        _selectedPeriod = period;
        _customStartDate = DateTime(
          pickedRange.start.year,
          pickedRange.start.month,
          pickedRange.start.day,
        );
        _customEndDate = DateTime(
          pickedRange.end.year,
          pickedRange.end.month,
          pickedRange.end.day,
          23,
          59,
          59,
          999,
        );
        _reportFuture = _loadReport();
      });
      return;
    }

    if (_selectedPeriod == period) return;
    setState(() {
      _selectedPeriod = period;
      _reportFuture = _loadReport();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          context.t("Analytics & Reports", "التحليلات والتقارير"),
          style: TextStyle(color: _textColor, fontWeight: FontWeight.bold),
        ),
      ),
      body: FutureBuilder<AnalyticsReport>(
        future: _reportFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: _accentGreen),
            );
          }

          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }

          final report = snapshot.data!;
          return RefreshIndicator(
            color: _accentGreen,
            backgroundColor: _cardColor,
            onRefresh: _refreshReport,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryGrid(report),
                  const SizedBox(height: 16),
                  _buildFilterSection(),
                  const SizedBox(height: 16),
                  _buildCategoryAnalyticsCard(
                    title: context.t("Income by Category", "الدخل حسب الفئة"),
                    totalAmount: report.summary.totalIncome,
                    items: report.incomeCategories,
                    baseColor: _accentGreen,
                    emptyTitle: context.t(
                      "No income data",
                      "لا توجد بيانات دخل",
                    ),
                    emptySubtitle: context.t(
                      "Income categories will appear here.",
                      "ستظهر فئات الدخل هنا.",
                    ),
                    palette: _incomePalette,
                  ),
                  const SizedBox(height: 16),
                  _buildCategoryAnalyticsCard(
                    title: context.t(
                      "Expenses by Category",
                      "المصاريف حسب الفئة",
                    ),
                    totalAmount: report.summary.totalExpenses,
                    items: report.expenseCategories,
                    baseColor: _expenseRed,
                    emptyTitle: context.t(
                      "No expense data",
                      "لا توجد بيانات مصاريف",
                    ),
                    emptySubtitle: context.t(
                      "Expense categories will appear here.",
                      "ستظهر فئات المصاريف هنا.",
                    ),
                    palette: _expensePalette,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: _expenseRed, size: 42),
            const SizedBox(height: 12),
            Text(
              context.t("Could not load analytics", "تعذر تحميل التحليلات"),
              style: TextStyle(
                color: _textColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: _secondaryTextColor, fontSize: 13),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _reloadReport,
              icon: Icon(Icons.refresh, color: _colors.onPrimary),
              label: Text(
                context.t("Retry", "إعادة المحاولة"),
                style: TextStyle(
                  color: _colors.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(backgroundColor: _accentGreen),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(AnalyticsReport report) {
    final netBalance = report.summary.netBalance;
    final netColor = netBalance >= 0 ? _accentGreen : _expenseRed;

    final cards = [
      _SummaryItem(
        title: context.t("TOTAL INCOME", "إجمالي الدخل"),
        value: _formatAmount(report.summary.totalIncome),
        icon: Icons.trending_up,
        color: _accentGreen,
      ),
      _SummaryItem(
        title: context.t("TOTAL EXPENSES", "إجمالي المصاريف"),
        value: _formatAmount(report.summary.totalExpenses),
        icon: Icons.trending_down,
        color: _expenseRed,
      ),
      _SummaryItem(
        title: context.t("NET BALANCE", "صافي الرصيد"),
        value: _formatAmount(netBalance),
        icon: Icons.account_balance_wallet_outlined,
        color: netColor,
      ),
      _SummaryItem(
        title: context.t("SELECTED PERIOD", "الفترة المحددة"),
        value: _selectedPeriodLabel(),
        icon: Icons.calendar_month,
        color: _infoBlue,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 680;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 4 : 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: isWide ? 2.05 : 1.55,
          ),
          itemBuilder: (context, index) => _buildSummaryCard(cards[index]),
        );
      },
    );
  }

  Widget _buildSummaryCard(_SummaryItem item) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: item.color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icon, color: item.color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    color: _mutedTextColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              item.value,
              style: TextStyle(
                color: item.color,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _colors.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t("Filters", "الفلاتر"),
            style: TextStyle(
              color: _textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPeriodChip(
                  context.t("This Month", "هذا الشهر"),
                  _AnalyticsPeriod.thisMonth,
                ),
                const SizedBox(width: 10),
                _buildPeriodChip(
                  context.t("Last Month", "الشهر الماضي"),
                  _AnalyticsPeriod.lastMonth,
                ),
                const SizedBox(width: 10),
                _buildPeriodChip(
                  context.t("Last 3 Months", "آخر 3 أشهر"),
                  _AnalyticsPeriod.lastThreeMonths,
                ),
                const SizedBox(width: 10),
                _buildPeriodChip(
                  context.t("Custom", "مخصص"),
                  _AnalyticsPeriod.custom,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildWalletFilter(),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String label, _AnalyticsPeriod period) {
    final isSelected = _selectedPeriod == period;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _selectPeriod(period),
      selectedColor: _accentGreen,
      backgroundColor: _fieldColor,
      labelStyle: TextStyle(
        color: isSelected ? _colors.onPrimary : _secondaryTextColor,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: BorderSide(color: isSelected ? _accentGreen : _colors.subtleBorder),
    );
  }

  Widget _buildWalletFilter() {
    return FutureBuilder<List<WalletModel>>(
      future: _walletsFuture,
      builder: (context, snapshot) {
        final wallets = snapshot.data ?? [];
        final walletExists = wallets.any((w) => w.id == _selectedWalletId);
        final initialValue = walletExists
            ? _selectedWalletId!
            : _allWalletsValue;

        return DropdownButtonFormField<String>(
          key: ValueKey(initialValue),
          initialValue: initialValue,
          isExpanded: true,
          dropdownColor: _cardColor,
          style: TextStyle(color: _textColor),
          decoration: InputDecoration(
            labelText: context.t("Wallet", "المحفظة"),
            labelStyle: TextStyle(color: _mutedTextColor),
            prefixIcon: Icon(Icons.account_balance_wallet, color: _accentGreen),
            filled: true,
            fillColor: _fieldColor,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _colors.subtleBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _accentGreen),
            ),
          ),
          items: [
            DropdownMenuItem(
              value: _allWalletsValue,
              child: Text(context.t("All Wallets", "كل المحافظ")),
            ),
            ...wallets.map(
              (wallet) =>
                  DropdownMenuItem(value: wallet.id, child: Text(wallet.name)),
            ),
          ],
          onChanged: snapshot.connectionState == ConnectionState.waiting
              ? null
              : (value) {
                  setState(() {
                    _selectedWalletId = value == _allWalletsValue
                        ? null
                        : value;
                    _reportFuture = _loadReport();
                  });
                },
        );
      },
    );
  }

  Widget _buildCategoryAnalyticsCard({
    required String title,
    required double totalAmount,
    required List<CategoryAnalytics> items,
    required Color baseColor,
    required String emptyTitle,
    required String emptySubtitle,
    required List<Color> palette,
  }) {
    final hasData = totalAmount > 0 && items.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: baseColor.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: baseColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  title.startsWith("Income")
                      ? Icons.south_west
                      : Icons.north_east,
                  color: baseColor,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                _formatAmount(totalAmount),
                style: TextStyle(
                  color: baseColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (!hasData)
            _buildEmptyAnalyticsState(emptyTitle, emptySubtitle, baseColor)
          else ...[
            _buildDonutChart(items, palette, baseColor),
            const SizedBox(height: 18),
            _buildCategoryDetailsList(items, palette, baseColor),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyAnalyticsState(String title, String subtitle, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      decoration: BoxDecoration(
        color: _fieldColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.pie_chart_outline, color: color, size: 34),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: _textColor,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: _mutedTextColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDonutChart(
    List<CategoryAnalytics> items,
    List<Color> palette,
    Color baseColor,
  ) {
    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              centerSpaceRadius: 56,
              sectionsSpace: 3,
              startDegreeOffset: -90,
              sections: items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final color = _categoryColor(item, index, palette);
                return PieChartSectionData(
                  value: item.totalAmount,
                  color: color,
                  radius: 58,
                  title: item.percentage >= 8
                      ? _formatPercentage(item.percentage)
                      : '',
                  titleStyle: TextStyle(
                    color: _bestTextColor(color),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "${items.length}",
                style: TextStyle(
                  color: baseColor,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Categories",
                style: TextStyle(
                  color: _mutedTextColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryDetailsList(
    List<CategoryAnalytics> items,
    List<Color> palette,
    Color baseColor,
  ) {
    return Column(
      children: items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final color = _categoryColor(item, index, palette);

        return Container(
          margin: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _fieldColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _colors.subtleBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconFromName(item.icon), color: color, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.categoryName,
                  style: TextStyle(
                    color: _textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatAmount(item.totalAmount),
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatPercentage(item.percentage),
                    style: TextStyle(
                      color: baseColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _categoryColor(CategoryAnalytics item, int index, List<Color> palette) {
    final parsedColor = _colorFromHex(item.colorHex);
    if (parsedColor != null) return parsedColor;
    return palette[index % palette.length];
  }

  Color? _colorFromHex(String? value) {
    if (value == null || value.trim().isEmpty) return null;

    final cleaned = value.replaceAll('#', '').trim();
    if (cleaned.length != 6 && cleaned.length != 8) return null;

    final hex = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;

    return Color(parsed);
  }

  Color _bestTextColor(Color color) {
    return color.computeLuminance() > 0.55 ? Colors.black : Colors.white;
  }

  IconData _iconFromName(String? name) {
    switch (name?.toLowerCase().trim()) {
      case 'salary':
      case 'payments':
      case 'work':
        return Icons.payments;
      case 'gift':
      case 'card_giftcard':
        return Icons.card_giftcard;
      case 'food':
      case 'restaurant':
        return Icons.restaurant;
      case 'transport':
      case 'directions_car':
      case 'taxi':
        return Icons.directions_car;
      case 'bills':
      case 'receipt':
        return Icons.receipt_long;
      case 'shopping':
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'credit_card':
      case 'card':
        return Icons.credit_card;
      case 'swap_horiz':
      case 'transfer':
        return Icons.swap_horiz;
      case 'home':
        return Icons.home;
      case 'health':
        return Icons.health_and_safety;
      default:
        return Icons.category;
    }
  }
}

class _SummaryItem {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryItem({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
}

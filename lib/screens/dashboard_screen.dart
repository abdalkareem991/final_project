// lib/screens/dashboard_screen.dart

// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:final_project/screens/ai_assistant_screen.dart';
import 'package:final_project/screens/analytics_screen.dart';
import 'package:final_project/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_text.dart';
import '../core/app_theme.dart';
import '../models/dashboard_summary_model.dart';
import '../models/category_model.dart';
import '../models/wallet_model.dart';
import '../services/notification_service.dart';
import '../services/sms_listener_service.dart';
import '../services/supabase_service.dart';
import 'my_account_screen.dart';
import 'notes_screen.dart';
import 'todo_list_screen.dart';
import 'transactions_history_screen.dart';

/// Root dashboard shell that owns the bottom navigation and page switching.
class DashboardScreen extends StatefulWidget {
  final int initialIndex;

  const DashboardScreen({super.key, this.initialIndex = 0});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Navigation state is kept here so each tab can refresh itself when revisited.
  late int _selectedIndex;
  final PageController _pageController = PageController();

  AppThemeColors get _colors => context.themeColors;
  Color get _bgColor => _colors.background;
  Color get _accentGreen => _colors.primary;

  final GlobalKey<_DashboardMainContentState> _mainContentKey = GlobalKey();
  final GlobalKey<MyAccountScreenState> _accountsKey = GlobalKey();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, 4).toInt();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selectedIndex != 0 && _pageController.hasClients) {
        _pageController.jumpToPage(_selectedIndex);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Refreshes tab-specific data whenever a page becomes visible again.
  void _handlePageVisible(int index) {
    if (index == 0) {
      _mainContentKey.currentState?.refreshDashboard();
    } else if (index == 1) {
      _accountsKey.currentState?.refreshAccounts();
    }
  }

  void _onBottomNavTap(int index) {
    if (index == _selectedIndex) {
      _handlePageVisible(index);
      return;
    }

    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _selectedIndex = index);
    _handlePageVisible(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      backgroundColor: _bgColor,
      selectedItemColor: _accentGreen,
      unselectedItemColor: _colors.textMuted,
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedIndex,
      onTap: _onBottomNavTap,
      items: [
        BottomNavigationBarItem(
          icon: const Icon(Icons.home),
          label: context.t("HOME", "الرئيسية"),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.account_balance),
          label: context.t("ACCOUNTS", "الحسابات"),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.analytics_outlined),
          label: context.t("ANALYTICS", "التحليلات"),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.list_alt),
          label: context.t("TO-DO LIST", "المهام"),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.settings),
          label: context.t("SETTINGS", "الإعدادات"),
        ),
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

class _DashboardMainContentState extends State<_DashboardMainContent>
    with WidgetsBindingObserver {
  // Services and streams are owned by the dashboard content area.
  final _supabaseService = SupabaseService();
  final NotificationService _notificationService = NotificationService();
  DashboardSummary? _dashboardSummary;
  bool _isDashboardLoading = true;
  bool _isDashboardRefreshing = false;
  String? _dashboardError;

  // UI-only preferences for the current dashboard session.
  bool _showHidden = false;
  bool _isSmsSyncButtonLoading = false;

  // Currency preference is applied at render time without changing stored data.
  String _currencySymbol = "JD";
  double _exchangeRate = 1.0;

  AppThemeColors get _colors => context.themeColors;
  Color get _bgColor => _colors.background;
  Color get _cardColor => _colors.surface;
  Color get _fieldColor => _colors.field;
  Color get _accentGreen => _colors.primary;
  Color get _expenseRed => _colors.expense;
  Color get _transferBlue => _colors.transfer;
  Color get _textColor => _colors.textPrimary;
  Color get _secondaryTextColor => _colors.textSecondary;
  Color get _mutedTextColor => _colors.textMuted;
  Stream<Map<String, double>> get _balancesStream => Stream.value({
    'Total': _dashboardSummary?.totalBalance ?? 0.0,
    'Bank': _dashboardSummary?.bankBalance ?? 0.0,
    'Cash': _dashboardSummary?.cashBalance ?? 0.0,
  });
  Stream<List<Map<String, dynamic>>> get _transactionsStream =>
      Stream.value(_dashboardSummary?.recentTransactions ?? const []);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    unawaited(_loadDashboardSummary());
    loadCurrencyPreference();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncSmsAutomationFromSettings());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // debugPrint("App resumed. Running automatic SMS sync.");

      unawaited(_syncSmsAutomationFromSettings());

      if (mounted) {
        setState(() {});
      }
    }
  }

  /// Starts or stops SMS automation according to the persisted settings toggle.
  Future<void> _syncSmsAutomationFromSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool('sms_automation_enabled') ?? false;

    if (isEnabled) {
      final started = await SMSListenerService()
          .startListening(syncImmediately: true)
          .timeout(const Duration(seconds: 25), onTimeout: () => false);
      if (!started) {
        await prefs.setBool('sms_automation_enabled', false);
        SMSListenerService().stopListening();
      }
    } else {
      SMSListenerService().stopListening();
    }
  }

  Future<void> _loadDashboardSummary({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await _supabaseService.getCachedDashboardSummary();
      if (cached != null && mounted) {
        setState(() {
          _dashboardSummary = cached;
          _isDashboardLoading = false;
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _isDashboardRefreshing = true;
      _dashboardError = null;
      _isDashboardLoading = _dashboardSummary == null;
    });

    try {
      final summary = await _supabaseService.getDashboardSummary(
        recentLimit: 10,
        includeHidden: _showHidden,
      );

      if (!mounted) return;
      setState(() {
        _dashboardSummary = summary;
        _dashboardError = null;
        _isDashboardLoading = false;
        _isDashboardRefreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _dashboardError = error.toString();
        _isDashboardLoading = false;
        _isDashboardRefreshing = false;
      });
    }
  }

  /// Rebuilds live streams after a manual refresh or a transaction mutation.
  void refreshDashboard() {
    loadCurrencyPreference();
    unawaited(_loadDashboardSummary(forceRefresh: true));
  }

  /// Loads the preferred display currency used by dashboard totals.
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

  // ---------------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------------

  String _formatAmount(double amount) {
    double converted = amount * _exchangeRate;
    return "$_currencySymbol${converted.toStringAsFixed(2)}";
  }

  String _formatDateTime(dynamic rawDate) {
    if (rawDate == null) return '';

    final parsed = DateTime.tryParse(rawDate.toString());
    if (parsed == null) return rawDate.toString();

    final date = parsed.toLocal();

    final int hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final String minute = date.minute.toString().padLeft(2, '0');
    final String period = date.hour >= 12 ? 'PM' : 'AM';

    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} "
        "$hour12:$minute $period";
  }

  String _formatNotificationTime(DateTime date) {
    final localDate = date.toLocal();

    final int hour12 = localDate.hour % 12 == 0 ? 12 : localDate.hour % 12;
    final String minute = localDate.minute.toString().padLeft(2, '0');
    final String period = localDate.hour >= 12 ? 'PM' : 'AM';

    return "$hour12:$minute $period";
  }

  // ---------------------------------------------------------------------------
  // SMS sync status
  // ---------------------------------------------------------------------------

  Widget _buildSmsSyncStatusLine() {
    return ValueListenableBuilder<int>(
      valueListenable: SMSListenerService.statusVersion,
      builder: (_, __, ____) {
        final status = SMSListenerService.lastSyncStatus;

        final isSyncing = _isSmsSyncButtonLoading || status == "Syncing";

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _isSmsSyncButtonLoading
              ? null
              : () async {
                  setState(() => _isSmsSyncButtonLoading = true);
                  SMSListenerService.instance.markManualSyncStarted();

                  SmsSyncResult result;
                  try {
                    result = await SMSListenerService.instance
                        .syncNow(reason: 'manual', force: true)
                        .timeout(
                          const Duration(seconds: 20),
                          onTimeout: SMSListenerService
                              .instance
                              .markManualSyncTimedOut,
                        );
                  } catch (_) {
                    result = const SmsSyncResult(
                      success: false,
                      skipped: false,
                      reason: 'error',
                      processedCount: 0,
                      duplicateCount: 0,
                      ignoredCount: 0,
                      errorCount: 1,
                      status: 'Error',
                    );
                  }

                  if (!mounted) return;
                  await _loadDashboardSummary(forceRefresh: true);
                  if (!mounted) return;
                  setState(() => _isSmsSyncButtonLoading = false);

                  final hasError =
                      result.errorCount > 0 ||
                      (!result.success && !result.skipped);
                  final message = hasError
                      ? context.t(
                          "SMS sync failed. Please try again",
                          "فشلت مزامنة الرسائل. يرجى المحاولة مرة أخرى",
                        )
                      : result.processedCount > 0
                      ? context.t("SMS sync completed", "اكتملت مزامنة الرسائل")
                      : context.t(
                          "No new SMS transactions found",
                          "لم يتم العثور على معاملات رسائل جديدة",
                        );

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(message),
                      backgroundColor: hasError ? _expenseRed : _accentGreen,
                    ),
                  );
                },
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _accentGreen.withOpacity(0.16)),
            ),
            child: Row(
              children: [
                if (isSyncing)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: _accentGreen,
                      strokeWidth: 2,
                    ),
                  )
                else
                  Icon(Icons.sync_outlined, color: _accentGreen, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.t("SMS Sync", "مزامنة الرسائل"),
                    style: TextStyle(
                      color: _secondaryTextColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.touch_app, color: _mutedTextColor, size: 15),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDashboardStatusLine() {
    if (!_isDashboardLoading &&
        !_isDashboardRefreshing &&
        _dashboardError == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (_dashboardError == null ? _accentGreen : _expenseRed)
              .withOpacity(0.16),
        ),
      ),
      child: Row(
        children: [
          if (_dashboardError == null)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: _accentGreen,
                strokeWidth: 2,
              ),
            )
          else
            Icon(Icons.error_outline, color: _expenseRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _dashboardError == null
                  ? context.t(
                      "Refreshing dashboard...",
                      "Ø¬Ø§Ø±ÙŠ ØªØ­Ø¯ÙŠØ« Ø§Ù„Ù„ÙˆØ­Ø©...",
                    )
                  : context.t(
                      "Could not refresh dashboard. Showing last data.",
                      "ØªØ¹Ø°Ø± ØªØ­Ø¯ÙŠØ« Ø§Ù„Ù„ÙˆØ­Ø©. Ø³ÙŠØªÙ… Ø¹Ø±Ø¶ Ø¢Ø®Ø± Ø¨ÙŠØ§Ù†Ø§Øª.",
                    ),
              style: TextStyle(
                color: _dashboardError == null
                    ? _secondaryTextColor
                    : _expenseRed,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Main layout
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        leading: _buildLeadingIcon(),
        title: Text(
          "FinMind",
          style: TextStyle(fontWeight: FontWeight.bold, color: _textColor),
        ),
        actions: [
          _buildNotificationButton(),
          const SizedBox(width: 8),
          _buildNotesButton(context),
          const SizedBox(width: 8),
          _buildAIChip(context),
          const SizedBox(width: 15),
        ],
      ),
      body: RefreshIndicator(
        color: _accentGreen,
        onRefresh: () async {
          loadCurrencyPreference();
          await _loadDashboardSummary(forceRefresh: true);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildLiveTotalBalanceCard(),
              ValueListenableBuilder<int>(
                valueListenable: SMSListenerService.statusVersion,
                builder: (context, _, __) => _buildSmsSyncStatusLine(),
              ),
              _buildDashboardStatusLine(),
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
        child: Icon(Icons.add, color: _colors.onPrimary, size: 30),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Balance and analytics summaries
  // ---------------------------------------------------------------------------

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
              Text(
                context.t("TOTAL BALANCE", "إجمالي الرصيد"),
                style: TextStyle(
                  color: _colors.onPrimary.withOpacity(0.72),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatAmount(total),
                style: TextStyle(
                  color: _colors.onPrimary,
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
                  color: _colors.onPrimary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.money,
                      color: _colors.onPrimary.withOpacity(0.72),
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      "${context.t("Cash", "نقد")}: ${_formatAmount(cash)}",
                      style: TextStyle(
                        color: _colors.onPrimary,
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
    final remoteSummary = _dashboardSummary;
    if (remoteSummary != null) {
      final income = remoteSummary.monthlyIncome;
      final expense = remoteSummary.monthlyExpenses;

      return Column(
        children: [
          _buildProgressCard(
            context.t("Monthly Income", "Ø§Ù„Ø¯Ø®Ù„ Ø§Ù„Ø´Ù‡Ø±ÙŠ"),
            "$income|$expense",
            1.0,
            _accentGreen,
          ),
          const SizedBox.shrink(),
          _buildProgressCard(
            context.t("Monthly Expenses", "Ø§Ù„Ù…ØµØ§Ø±ÙŠÙ Ø§Ù„Ø´Ù‡Ø±ÙŠØ©"),
            _formatAmount(expense),
            -1.0,
            _expenseRed,
          ),
        ],
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _transactionsStream,
      builder: (context, snapshot) {
        final summary = _monthlySummaryFromTransactions(snapshot.data ?? []);
        final income = summary['Income'] ?? 0.0;
        final expense = summary['Expense'] ?? 0.0;
        final incomeProgress = 1.0;
        final expenseProgress = -1.0;

        return Column(
          children: [
            _buildProgressCard(
              context.t("Monthly Income", "الدخل الشهري"),
              "$income|$expense",
              incomeProgress,
              _accentGreen,
            ),
            const SizedBox.shrink(),
            _buildProgressCard(
              context.t("Monthly Expenses", "المصاريف الشهرية"),
              _formatAmount(expense),
              expenseProgress,
              _expenseRed,
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Transactions list and item actions
  // ---------------------------------------------------------------------------

  Widget _buildLiveTransactionsList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _transactionsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: CircularProgressIndicator(color: _accentGreen),
            ),
          );
        }

        final visibleTransactions = snapshot.data
            ?.where((tx) => _showHidden || tx['is_hidden'] != true)
            .toList();

        if (visibleTransactions == null || visibleTransactions.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              context.t("No transactions yet.", "لا توجد حركات بعد."),
              style: TextStyle(color: _mutedTextColor),
            ),
          );
        }

        final recentTransactions = visibleTransactions.take(10).toList();

        return Column(
          children: recentTransactions.map((tx) {
            final bool isHidden = tx['is_hidden'] == true;
            return _buildTransactionItem(tx, isHidden: isHidden);
          }).toList(),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // App bar actions
  // ---------------------------------------------------------------------------

  Widget _buildLeadingIcon() => Padding(
    padding: const EdgeInsets.all(8.0),
    child: Container(
      decoration: BoxDecoration(
        color: _accentGreen,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.account_balance_wallet, color: _colors.onPrimary),
    ),
  );

  Widget _buildNotesButton(BuildContext context) => InkWell(
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NotesScreen()),
    ),
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _accentGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accentGreen.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.note_alt_outlined, color: _accentGreen, size: 14),
          const SizedBox(width: 5),
          Text(
            context.t("Notes", "الملاحظات"),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, color: _accentGreen, size: 14),
          const SizedBox(width: 5),
          Text(
            context.t("Ask AI", "اسأل الذكاء"),
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
  Widget _buildNotificationButton() {
    return ValueListenableBuilder<int>(
      valueListenable: _notificationService.unreadCount,
      builder: (context, count, _) {
        return PopupMenuButton<String>(
          color: _cardColor,
          offset: const Offset(0, 45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onOpened: () {
            _notificationService.markAllAsRead();
          },
          itemBuilder: (context) {
            final notifications =
                _notificationService.recentNotifications.value;

            if (notifications.isEmpty) {
              return [
                PopupMenuItem<String>(
                  enabled: false,
                  child: SizedBox(
                    width: 280,
                    child: Text(
                      context.t(
                        "No notifications yet.",
                        "لا توجد إشعارات بعد.",
                      ),
                      style: TextStyle(color: _mutedTextColor),
                    ),
                  ),
                ),
              ];
            }

            return [
              PopupMenuItem<String>(
                enabled: false,
                child: SizedBox(
                  width: 300,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.t("Notifications", "الإشعارات"),
                          style: TextStyle(
                            color: _textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _notificationService.clearNotificationCenter();
                        },
                        child: Text(
                          context.t("Clear", "مسح"),
                          style: TextStyle(color: _accentGreen),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ...notifications.map((notification) {
                return PopupMenuItem<String>(
                  enabled: false,
                  child: SizedBox(
                    width: 300,
                    child: _buildNotificationMenuItem(notification),
                  ),
                );
              }),
            ];
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accentGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: _accentGreen.withOpacity(0.3)),
                ),
                child: Icon(
                  Icons.notifications_none,
                  color: _accentGreen,
                  size: 20,
                ),
              ),
              if (count > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      count > 9 ? "9+" : count.toString(),
                      style: TextStyle(
                        color: _colors.onPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotificationMenuItem(AppNotificationItem notification) {
    IconData icon;
    Color color;

    switch (notification.type) {
      case 'transaction':
        icon = Icons.receipt_long;
        color = _accentGreen;
        break;
      case 'transfer':
        icon = Icons.swap_horiz;
        color = _transferBlue;
        break;
      case 'error':
        icon = Icons.error_outline;
        color = Colors.redAccent;
        break;
      default:
        icon = Icons.notifications_none;
        color = _mutedTextColor;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notification.title,
                style: TextStyle(
                  color: _textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                notification.body,
                style: TextStyle(color: _mutedTextColor, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _formatNotificationTime(notification.createdAt),
                style: TextStyle(
                  color: _mutedTextColor.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Recent transaction cards
  // ---------------------------------------------------------------------------

  Widget _buildRecentTransactionsHeader() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        context.t("Recent Transactions", "آخر الحركات"),
        style: TextStyle(
          color: _textColor,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      Row(
        children: [
          IconButton(
            icon: Icon(
              _showHidden ? Icons.visibility : Icons.visibility_off,
              color: _showHidden ? _accentGreen : _mutedTextColor,
              size: 20,
            ),
            tooltip: _showHidden
                ? context.t("Hide hidden", "إخفاء المخفية")
                : context.t("Show hidden", "إظهار المخفية"),
            onPressed: () {
              setState(() {
                _showHidden = !_showHidden;
              });
              refreshDashboard();
            },
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TransactionsHistoryScreen(),
                ),
              );
            },
            child: Text(
              context.t("See All", "عرض الكل"),
              style: TextStyle(color: _accentGreen),
            ),
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
    if (progress < 0) return const SizedBox.shrink();

    final flowParts = amount.split('|');
    if (flowParts.length == 2) {
      return _buildMonthlyFlowCard(
        income: double.tryParse(flowParts[0]) ?? 0.0,
        expense: double.tryParse(flowParts[1]) ?? 0.0,
      );
    }

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
              Text(title, style: TextStyle(color: _mutedTextColor)),
              Text(
                amount,
                style: TextStyle(
                  color: _textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: _fieldColor,
            color: color,
            minHeight: 6,
          ),
        ],
      ),
    );
  }

  Map<String, double> _monthlySummaryFromTransactions(
    List<Map<String, dynamic>> transactions,
  ) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final summary = {'Income': 0.0, 'Expense': 0.0};

    for (final tx in transactions) {
      if (tx['is_hidden'] == true || tx['is_internal_transfer'] == true) {
        continue;
      }

      final date = DateTime.tryParse(
        (tx['date'] ?? tx['created_at'] ?? '').toString(),
      );
      if (date == null || date.toLocal().isBefore(monthStart)) continue;

      final type = tx['type']?.toString() ?? '';
      if (type != 'Income' && type != 'Expense') continue;

      final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
      summary[type] = (summary[type] ?? 0.0) + amount.abs();
    }

    return summary;
  }

  Widget _buildMonthlyFlowCard({
    required double income,
    required double expense,
  }) {
    final totalFlow = income + expense;
    final incomeShare = totalFlow <= 0 ? 0.0 : income / totalFlow;
    final expenseShare = totalFlow <= 0 ? 0.0 : expense / totalFlow;
    final net = income - expense;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t("Monthly Flow", "الحركة الشهرية"),
                  style: TextStyle(
                    color: _textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                "${context.t("Net", "الصافي")}: ${_formatAmount(net)}",
                style: TextStyle(
                  color: net >= 0 ? _accentGreen : _expenseRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildFlowLegend(
                  context.t("Income", "الدخل"),
                  _formatAmount(income),
                  _accentGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFlowLegend(
                  context.t("Expenses", "المصاريف"),
                  _formatAmount(expense),
                  _expenseRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 12,
              color: _fieldColor,
              child: totalFlow <= 0
                  ? const SizedBox.expand()
                  : Row(
                      children: [
                        if (incomeShare > 0)
                          Expanded(
                            flex: (incomeShare * 1000).round().clamp(1, 1000),
                            child: Container(color: _accentGreen),
                          ),
                        if (incomeShare > 0 && expenseShare > 0)
                          Container(width: 2, color: _cardColor),
                        if (expenseShare > 0)
                          Expanded(
                            flex: (expenseShare * 1000).round().clamp(1, 1000),
                            child: Container(color: _expenseRed),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowLegend(String label, String amount, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            "$label: $amount",
            style: TextStyle(
              color: _secondaryTextColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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

    final String date = _formatDateTime(tx['date'] ?? tx['created_at']);

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
              ? Border.all(color: _mutedTextColor.withOpacity(0.3), width: 1)
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
                          style: TextStyle(
                            color: _textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          secondaryText,
                          style: TextStyle(
                            color: _mutedTextColor,
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
                    icon: Icon(
                      Icons.more_vert,
                      color: _mutedTextColor,
                      size: 20,
                    ),
                    color: _cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    onSelected: (value) async {
                      if (value == 'details') {
                        _showTransactionDetailsDialog(tx);
                      } else if (value == 'edit') {
                        _showTransactionModal(existingTx: tx);
                      } else if (value == 'hide') {
                        await _supabaseService.hideTransaction(
                          tx['id'].toString(),
                        );
                        refreshDashboard();
                        widget.onTransactionChanged?.call();
                      } else if (value == 'unhide') {
                        await _supabaseService.unhideTransaction(
                          tx['id'].toString(),
                        );
                        refreshDashboard();
                        widget.onTransactionChanged?.call();
                      } else if (value == 'delete') {
                        await _deleteTransactionWithConfirm(tx);
                      }
                    },
                    itemBuilder: (BuildContext context) => [
                      PopupMenuItem(
                        value: 'details',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.blueAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "Details",
                              style: TextStyle(color: _textColor),
                            ),
                          ],
                        ),
                      ),
                      if (!isInternalTransfer)
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.edit,
                                color: Colors.orangeAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Text("Edit", style: TextStyle(color: _textColor)),
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
                              color: _mutedTextColor,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isHidden ? "Unhide" : "Hide",
                              style: TextStyle(color: _textColor),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text("Delete", style: TextStyle(color: _textColor)),
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

  /// Shows a read-only summary for a transaction without mutating any state.
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
        title: Center(
          child: Text(
            context.t("Transaction Details", "تفاصيل الحركة"),
            style: TextStyle(color: _textColor, fontWeight: FontWeight.bold),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Divider(color: _colors.subtleBorder),
            const SizedBox(height: 10),
            _buildDetailRow(
              context.t("Description", "الوصف"),
              tx['description'] ?? 'N/A',
            ),
            _buildDetailRow(
              context.t("Amount", "المبلغ"),
              _formatAmount((tx['amount'] as num).toDouble()),
              valueColor: isInternalTransfer
                  ? _transferBlue
                  : isExpense
                  ? _expenseRed
                  : _accentGreen,
            ),
            _buildDetailRow(
              context.t("Type", "النوع"),
              isInternalTransfer
                  ? context.t("Internal Transfer", "تحويل داخلي")
                  : context.enumText(tx['type'].toString()),
            ),
            _buildDetailRow(context.t("Account", "الحساب"), walletName),
            _buildDetailRow(context.t("Category", "الفئة"), categoryName),
            _buildDetailRow(
              context.t("Date", "التاريخ"),
              _formatDateTime(tx['date'] ?? tx['created_at']),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accentGreen),
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              context.t("Close", "إغلاق"),
              style: TextStyle(
                color: _colors.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: _mutedTextColor, fontSize: 14)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? _textColor,
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

  /// Confirms deletion before reversing balances and removing the transaction.
  Future<void> _deleteTransactionWithConfirm(Map<String, dynamic> tx) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text(
          context.t("Delete Transaction", "حذف الحركة"),
          style: TextStyle(color: _textColor),
        ),
        content: Text(
          context.t(
            "Are you sure? This will reverse the account balance.",
            "هل أنت متأكد؟ سيؤدي ذلك إلى عكس رصيد الحساب.",
          ),
          style: TextStyle(color: _secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t("Cancel", "إلغاء")),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t("Delete", "حذف")),
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

  // ---------------------------------------------------------------------------
  // Transaction form
  // ---------------------------------------------------------------------------

  /// Handles both new manual transactions and edits to existing records.
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
                  Center(
                    child: SizedBox(
                      width: 50,
                      child: Divider(
                        thickness: 5,
                        color: _mutedTextColor.withOpacity(0.35),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isEditing
                        ? context.t("Edit Transaction", "تعديل الحركة")
                        : context.t("New Transaction", "حركة جديدة"),
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _buildModalToggle(
                        context.t("Expense", "مصروف"),
                        selectedType == 'Expense',
                        _expenseRed,
                        () => setModalState(() => selectedType = 'Expense'),
                      ),
                      const SizedBox(width: 10),
                      _buildModalToggle(
                        context.t("Income", "دخل"),
                        selectedType == 'Income',
                        _accentGreen,
                        () => setModalState(() => selectedType = 'Income'),
                      ),
                      if (!isEditing) ...[
                        const SizedBox(width: 10),
                        _buildModalToggle(
                          context.t("Transfer", "تحويل"),
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
                    style: TextStyle(color: _textColor, fontSize: 22),
                    decoration: _inputStyle(
                      context.t("Amount (In JD)", "المبلغ بالدينار"),
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
                            style: TextStyle(color: _textColor),
                            decoration: _inputStyle(
                              selectedType == 'Transfer'
                                  ? context.t("From Account", "من حساب")
                                  : context.t("Select Account", "اختر الحساب"),
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
                              style: TextStyle(color: _textColor),
                              decoration: _inputStyle(
                                context.t("To Account", "إلى حساب"),
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
                                style: TextStyle(color: _textColor),
                                decoration: _inputStyle(
                                  context.t("Select Category", "اختر الفئة"),
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
                            icon: Icon(Icons.add, color: _accentGreen),
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
                    style: TextStyle(color: _textColor),
                    decoration: _inputStyle(
                      context.t("Description", "الوصف"),
                      Icons.edit,
                    ),
                  ),
                  const SizedBox(height: 25),
                  ElevatedButton(
                    onPressed: () async {
                      double parsedAmount =
                          double.tryParse(amountController.text) ?? 0.0;
                      if (parsedAmount <= 0 || selectedWalletId == null) {
                        _showError(
                          context,
                          context.t(
                            "Fill required fields with valid amounts.",
                            "املأ الحقول المطلوبة بمبالغ صحيحة.",
                          ),
                        );
                        return;
                      }
                      if (selectedType == 'Transfer' && !isEditing) {
                        if (targetWalletId == null ||
                            selectedWalletId == targetWalletId) {
                          _showError(
                            context,
                            context.t(
                              "Select two different accounts for transfer.",
                              "اختر حسابين مختلفين للتحويل.",
                            ),
                          );
                          return;
                        }
                      } else if (selectedCategoryId == null) {
                        _showError(
                          context,
                          context.t(
                            "Please select a category.",
                            "يرجى اختيار الفئة.",
                          ),
                        );
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
                      isEditing
                          ? context.t("UPDATE TRANSACTION", "تحديث الحركة")
                          : context.t("SAVE TRANSACTION", "حفظ الحركة"),
                      style: TextStyle(
                        color: _colors.onPrimary,
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

  // ---------------------------------------------------------------------------
  // Form helpers
  // ---------------------------------------------------------------------------

  void _showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  /// Adds a lightweight custom expense category without leaving the modal.
  void _showAddNewCategoryDialog(
    BuildContext context,
    StateSetter setModalState,
  ) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text(
          context.t("Add Category", "إضافة فئة"),
          style: TextStyle(color: _textColor),
        ),
        content: TextField(
          controller: nameController,
          style: TextStyle(color: _textColor),
          decoration: _inputStyle(
            context.t("Category Name", "اسم الفئة"),
            Icons.edit,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.t("Cancel", "إلغاء")),
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
            child: Text(context.t("Save", "حفظ")),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputStyle(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: _mutedTextColor),
    prefixIcon: Icon(icon, color: _accentGreen),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: _colors.subtleBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: _accentGreen),
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
            border: Border.all(
              color: isSelected ? color : _colors.subtleBorder,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : _mutedTextColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

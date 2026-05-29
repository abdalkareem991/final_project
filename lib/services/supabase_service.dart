// lib/services/supabase_service.dart

// ignore_for_file: empty_catches

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/analytics_model.dart';
import '../models/category_model.dart';
import '../models/dashboard_summary_model.dart';
import '../models/debts_model.dart';
import '../models/profile_model.dart';
import '../models/task_model.dart';
import '../models/wallet_model.dart';
import 'analytics_service.dart';
import 'debts_service.dart';
import 'notification_service.dart';
import 'sms_hash_service.dart';

const String _smsLogTag = 'FinMindSMS';
const String _dbLogTag = 'FinMindDB';
const String _rpcLogTag = 'FinMindRPC';
const String _dashboardLogTag = 'FinMindDashboard';

void _logSupabaseIssue(
  String tag,
  String operation,
  Object error, [
  StackTrace? stackTrace,
]) {
  debugPrint('[$tag] $operation failed: $error');

  final dynamic dynamicError = error;
  try {
    final code = dynamicError.code;
    if (code != null) debugPrint('[$tag] code: $code');
  } catch (_) {}
  try {
    final details = dynamicError.details;
    if (details != null) debugPrint('[$tag] details: $details');
  } catch (_) {}
  try {
    final hint = dynamicError.hint;
    if (hint != null) debugPrint('[$tag] hint: $hint');
  } catch (_) {}
  try {
    final message = dynamicError.message;
    if (message != null) debugPrint('[$tag] message: $message');
  } catch (_) {}

  if (stackTrace != null) {
    debugPrint('[$tag] stackTrace: $stackTrace');
  }
}

class SmsProcessingResult {
  final bool success;
  final String status;
  final bool processed;
  final bool isDuplicate;
  final bool isSkipped;
  final bool isInternalTransfer;
  final String? transactionId;
  final String? walletId;
  final String? walletName;
  final String? type;
  final String? description;
  final String? message;
  final double? amount;
  final double? balanceAfter;

  const SmsProcessingResult({
    this.success = false,
    required this.status,
    required this.processed,
    this.isDuplicate = false,
    this.isSkipped = false,
    this.isInternalTransfer = false,
    this.transactionId,
    this.walletId,
    this.walletName,
    this.type,
    this.description,
    this.message,
    this.amount,
    this.balanceAfter,
  });

  factory SmsProcessingResult.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString() ?? 'unknown';
    final success = json['success'] == true;
    final isDuplicate = status == 'duplicate';
    final isSkipped = status == 'skipped';
    return SmsProcessingResult(
      success: success,
      status: status,
      processed:
          status == 'processed' ||
          status == 'created' ||
          json['processed'] == true ||
          (success && status != 'duplicate' && status != 'skipped'),
      isDuplicate: isDuplicate,
      isSkipped: isSkipped,
      isInternalTransfer: json['is_internal_transfer'] == true,
      transactionId: json['transaction_id']?.toString(),
      walletId: json['wallet_id']?.toString(),
      walletName: json['wallet_name']?.toString(),
      type: json['type']?.toString(),
      description: json['description']?.toString(),
      message: json['message']?.toString(),
      amount: (json['amount'] as num?)?.toDouble(),
      balanceAfter: (json['balance_after'] as num?)?.toDouble(),
    );
  }
}

class SupabaseService {
  // Singleton pattern to ensure only one instance of the service exists
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  // Initialize Supabase Client
  final SupabaseClient client = Supabase.instance.client;

  static const String _dashboardSummaryCacheKey =
      'finmind_dashboard_summary_cache_v1';

  String? _transactionLookupUserId;
  String? _transactionLookupRefreshUserId;
  bool _transactionLookupCacheLoaded = false;
  Future<void>? _transactionLookupRefreshFuture;
  Map<String, String> _transactionWalletNameCache = {};
  Map<String, String> _transactionCategoryNameCache = {};

  // ===========================================================================
  // 1. AUTHENTICATION OPERATIONS
  // ===========================================================================

  Future<AuthResponse> signIn(String email, String password) async {
    try {
      return await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (error) {
      debugPrint('Sign In Error: $error');
      rethrow;
    }
  }

  Future<AuthResponse> signUp(String email, String password) async {
    try {
      return await client.auth.signUp(email: email, password: password);
    } catch (error) {
      debugPrint('Sign Up Error: $error');
      rethrow;
    }
  }

  Future<void> ensureUserProfile({
    required String userId,
    String? fullName,
    String? phone,
  }) async {
    try {
      final existing = await client
          .from('users')
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      if (existing != null) return;

      await client.from('users').insert({
        'id': userId,
        'full_name': (fullName == null || fullName.trim().isEmpty)
            ? 'Financial Mind User'
            : fullName.trim(),
        'phone': phone?.trim() ?? '',
        'total_net_worth': 0.0,
      });
    } catch (error) {
      debugPrint('Ensure Profile Error: $error');
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.flutter://reset-callback/',
      );
    } catch (error) {
      debugPrint('Reset Password Error: $error');
      rethrow;
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (error) {
      debugPrint('Update Password Error: $error');
      rethrow;
    }
  }

  // ===========================================================================
  // 2. PROFILE OPERATIONS
  // ===========================================================================

  Future<void> createUserProfile(
    String id,
    String userName,
    String phone,
  ) async {
    try {
      await client.from('users').insert({
        'id': id,
        'full_name': userName,
        'phone': phone,
        'total_net_worth': 0.0,
      });
    } catch (error) {
      debugPrint('Profile Creation Error: $error');
      rethrow;
    }
  }

  Future<ProfileModel> getProfileData() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      final response = await client
          .from('users')
          .select()
          .eq('id', user.id)
          .single();
      return ProfileModel.fromJson(response);
    } catch (error) {
      debugPrint('Get Profile Error: $error');
      rethrow;
    }
  }

  Future<void> updateProfileNetWorth() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return;

      final total = await calculateTotalNetWorth();

      await client
          .from('users')
          .update({'total_net_worth': total})
          .eq('id', user.id);

      debugPrint("Profile net worth updated: $total");
    } catch (e) {
      debugPrint("Update profile net worth error: $e");
    }
  }
  // ===========================================================================
  // 3. WALLET OPERATIONS
  // ===========================================================================

  Future<void> addWallet(WalletModel wallet) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      await client.from('wallets').insert({
        'user_id': user.id,
        'name': wallet.name,
        'balance': wallet.balance,
        'type': wallet.type,
        'currency': wallet.currency,
        'account_mode': wallet.accountMode,
        'sms_sender_id': wallet.smsSenderId,
        'is_active_monitoring': wallet.isActiveMonitoring,
      });

      debugPrint("Wallet added: ${wallet.name}");
      debugPrint("Mode: ${wallet.accountMode}");
      debugPrint("SMS Sender: ${wallet.smsSenderId}");
      debugPrint("Monitoring: ${wallet.isActiveMonitoring}");
      await updateProfileNetWorth();
    } catch (error) {
      debugPrint('Add Wallet Error: $error');
      rethrow;
    }
  }

  Future<double> calculateTotalNetWorth() async {
    try {
      final wallets = await getWallets();
      if (wallets.isEmpty) return 0.0;
      return wallets.fold<double>(0.0, (sum, wallet) => sum + wallet.balance);
    } catch (e) {
      debugPrint('Calculate Net Worth Error: $e');
      return 0.0;
    }
  }

  Future<Map<String, double>> getBalancesByType() async {
    try {
      final wallets = await getWallets();
      double bankBalance = 0.0;
      double cashBalance = 0.0;

      for (var w in wallets) {
        if (w.type.toLowerCase() == 'cash') {
          cashBalance += w.balance;
        } else {
          bankBalance += w.balance;
        }
      }
      return {
        'Total': bankBalance + cashBalance,
        'Bank': bankBalance,
        'Cash': cashBalance,
      };
    } catch (e) {
      debugPrint('Calculate Balances Error: $e');
      return {'Total': 0.0, 'Bank': 0.0, 'Cash': 0.0};
    }
  }

  Future<List<WalletModel>> getWallets() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return [];

      final response = await client
          .from('wallets')
          .select()
          .eq('user_id', user.id);
      return (response as List)
          .map((json) => WalletModel.fromJson(json))
          .toList();
    } catch (error) {
      debugPrint('Fetch Wallets Error: $error');
      rethrow;
    }
  }

  Future<void> deleteWallet(String walletId) async {
    try {
      await client.from('wallets').delete().eq('id', walletId);
    } catch (error) {
      debugPrint('Delete Wallet Error: $error');
      rethrow;
    }
  }

  Future<void> updateWallet(WalletModel wallet) async {
    try {
      final Map<String, dynamic> updateData = {
        'name': wallet.name,
        'balance': wallet.balance,
        'type': wallet.type,
        'currency': wallet.currency,
        'account_mode': wallet.accountMode,
        'sms_sender_id': wallet.smsSenderId,
        'is_active_monitoring': wallet.isActiveMonitoring,
      };

      await client.from('wallets').update(updateData).eq('id', wallet.id);

      await updateProfileNetWorth();
      debugPrint("Wallet updated: ${wallet.name}");
      debugPrint("Mode: ${wallet.accountMode}");
      debugPrint("SMS Sender: ${wallet.smsSenderId}");
      debugPrint("Monitoring: ${wallet.isActiveMonitoring}");
    } catch (error) {
      debugPrint('Update Wallet Error: $error');
      rethrow;
    }
  }

  Future<void> setAllAutomatedWalletMonitoring(bool enabled) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return;

      await client
          .from('wallets')
          .update({'is_active_monitoring': enabled})
          .eq('user_id', user.id)
          .eq('account_mode', 'AUTOMATED');
    } catch (error) {
      debugPrint('Bulk monitoring update error: $error');
      rethrow;
    }
  }

  // ===========================================================================
  // 4. CATEGORY OPERATIONS
  // ===========================================================================

  Future<List<CategoryModel>> getCategories() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return [];

      final response = await client
          .from('categories')
          .select()
          .eq('user_id', user.id);
      return (response as List)
          .map((json) => CategoryModel.fromJson(json))
          .toList();
    } catch (error) {
      debugPrint('Fetch Categories Error: $error');
      return [];
    }
  }

  Future<CategoryModel> addCustomCategory(String name, String type) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      final response = await client
          .from('categories')
          .insert({
            'user_id': user.id,
            'name': name,
            'type': type,
            'icon': 'category',
            'color': '#34EAB9',
          })
          .select()
          .single();

      return CategoryModel.fromJson(response);
    } catch (error) {
      debugPrint('Add Category Error: $error');
      rethrow;
    }
  }

  Future<int> getOrCreateCategoryByName({
    required String name,
    required String type,
    String icon = 'category',
    String color = '#34EAB9',
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    final existing = await client
        .from('categories')
        .select('id')
        .eq('user_id', user.id)
        .eq('name', name)
        .maybeSingle();

    if (existing != null) {
      return existing['id'] as int;
    }

    final inserted = await client
        .from('categories')
        .insert({
          'user_id': user.id,
          'name': name,
          'type': type,
          'icon': icon,
          'color': color,
        })
        .select('id')
        .single();

    return inserted['id'] as int;
  }

  Future<int> getAutoCategoryIdForSms({
    required String smsKind,
    String? merchantName,
  }) async {
    final text =
        "${smsKind.toLowerCase()} ${(merchantName ?? '').toLowerCase()}";

    if (text.contains('cliq') || text.contains('transfer')) {
      return getOrCreateCategoryByName(
        name: 'تحويل',
        type: 'Transfer',
        icon: 'swap_horiz',
        color: '#3B82F6',
      );
    }

    if (text.contains('bill') ||
        text.contains('biller') ||
        text.contains('efawateercom') ||
        text.contains('فاتورة') ||
        text.contains('orange') ||
        text.contains('zain') ||
        text.contains('umniah')) {
      return getOrCreateCategoryByName(
        name: 'Bills',
        type: 'Expense',
        icon: 'receipt',
        color: '#F59E0B',
      );
    }

    if (text.contains('carrefour') ||
        text.contains('market') ||
        text.contains('supermarket') ||
        text.contains('grocery')) {
      return getOrCreateCategoryByName(
        name: 'Groceries',
        type: 'Expense',
        icon: 'shopping_cart',
        color: '#22C55E',
      );
    }

    if (text.contains('restaurant') ||
        text.contains('cafe') ||
        text.contains('food') ||
        text.contains('meal')) {
      return getOrCreateCategoryByName(
        name: 'Food',
        type: 'Expense',
        icon: 'restaurant',
        color: '#EF4444',
      );
    }

    if (text.contains('careem') ||
        text.contains('uber') ||
        text.contains('taxi') ||
        text.contains('transport')) {
      return getOrCreateCategoryByName(
        name: 'Transport',
        type: 'Expense',
        icon: 'directions_car',
        color: '#06B6D4',
      );
    }

    if (text.contains('card') ||
        text.contains('visa') ||
        text.contains('pos') ||
        text.contains('purchase')) {
      return getOrCreateCategoryByName(
        name: 'Card Payment',
        type: 'Expense',
        icon: 'credit_card',
        color: '#8B5CF6',
      );
    }

    return getOrCreateCategoryByName(
      name: 'General',
      type: 'Expense',
      icon: 'category',
      color: '#94A3B8',
    );
  }

  // ===========================================================================
  // 5. TRANSACTION LOGIC & ANALYTICS
  // ===========================================================================

  Future<DashboardSummary?> getCachedDashboardSummary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_dashboardSummaryCacheKey);
      if (raw == null || raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      return DashboardSummary.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('Dashboard cache read error: $error');
      return null;
    }
  }

  Future<void> _cacheDashboardSummary(DashboardSummary summary) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _dashboardSummaryCacheKey,
        jsonEncode(summary.toJson()),
      );
    } catch (error) {
      debugPrint('Dashboard cache write error: $error');
    }
  }

  Future<DashboardSummary> getDashboardSummary({
    int recentLimit = 10,
    bool includeHidden = false,
    bool allowLocalFallback = true,
  }) async {
    try {
      final response = await client.rpc(
        'get_dashboard_summary',
        params: {
          'p_recent_limit': recentLimit,
          'p_include_hidden': includeHidden,
        },
      );

      final summary = DashboardSummary.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
      await _cacheDashboardSummary(summary);
      return summary;
    } catch (error, stackTrace) {
      _logSupabaseIssue(
        _dashboardLogTag,
        'get_dashboard_summary RPC',
        error,
        stackTrace,
      );
      if (!allowLocalFallback) rethrow;
      return _buildDashboardSummaryFallback(
        recentLimit: recentLimit,
        includeHidden: includeHidden,
      );
    }
  }

  Future<DashboardSummary> _buildDashboardSummaryFallback({
    required int recentLimit,
    required bool includeHidden,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) return DashboardSummary.empty();

    final balances = await getBalancesByType();
    final transactions = await getTransactionsPage(
      page: 0,
      pageSize: recentLimit,
      includeHidden: includeHidden,
    );

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    final analytics = await AnalyticsService().getAnalyticsReport(
      userId: user.id,
      startDate: monthStart,
      endDate: monthEnd,
    );

    DashboardDebtSummary debtSummary = const DashboardDebtSummary(
      totalDebtorAmount: 0,
      totalCreditorAmount: 0,
      netDebt: 0,
    );
    try {
      final activeDebts = await DebtsService().getActiveDebts(user.id);
      final summary = DebtsService().buildSummary(activeDebts);
      debtSummary = DashboardDebtSummary(
        totalDebtorAmount: summary.totalDebtorAmount,
        totalCreditorAmount: summary.totalCreditorAmount,
        netDebt: summary.netDebt,
      );
    } catch (error) {
      debugPrint('Dashboard debt fallback error: $error');
    }

    final summary = DashboardSummary(
      totalBalance: balances['Total'] ?? 0,
      bankBalance: balances['Bank'] ?? 0,
      cashBalance: balances['Cash'] ?? 0,
      monthlyIncome: analytics.summary.totalIncome,
      monthlyExpenses: analytics.summary.totalExpenses,
      recentTransactions: transactions,
      incomeCategorySummary: analytics.incomeCategories,
      expenseCategorySummary: analytics.expenseCategories,
      debtsSummary: debtSummary,
      fetchedAt: DateTime.now(),
    );
    await _cacheDashboardSummary(summary);
    return summary;
  }

  Future<List<Map<String, dynamic>>> getTransactionsPage({
    int page = 0,
    int pageSize = 25,
    bool includeHidden = false,
  }) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return [];

      final safePage = page < 0 ? 0 : page;
      final safePageSize = pageSize.clamp(1, 100).toInt();
      final from = safePage * safePageSize;
      final to = from + safePageSize - 1;

      var query = client
          .from('transactions')
          .select('*, wallets(name), categories(name)')
          .eq('user_id', user.id);

      if (!includeHidden) {
        query = query.or('is_hidden.is.null,is_hidden.eq.false');
      }

      final response = await query
          .order('date', ascending: false)
          .range(from, to);

      final rows = List<Map<String, dynamic>>.from(response);
      return rows.map((tx) {
        final walletName = tx['wallets'] is Map
            ? tx['wallets']['name']?.toString()
            : null;
        final categoryName = tx['categories'] is Map
            ? tx['categories']['name']?.toString()
            : null;

        return {
          ...tx,
          'wallet_name': walletName ?? 'Unknown Account',
          'category_name': categoryName ?? 'Uncategorized',
        };
      }).toList();
    } catch (error, stackTrace) {
      _logSupabaseIssue(
        _dbLogTag,
        'fetch transactions page',
        error,
        stackTrace,
      );
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTransactions() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return [];

      final response = await client
          .from('transactions')
          .select('*, wallets(name), categories(name)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      debugPrint('Fetch Transactions Error: $error');
      return [];
    }
  }

  Future<String?> createTransaction({
    required String walletId,
    required double amount,
    required String type,
    required String description,
    required int categoryId,
    String? smsHash,
    bool isInternalTransfer = false,
    String? transferGroupId,
    double? balanceAfter,
    String? merchantName,
    String? smsKind,
    DateTime? transactionDate,
  }) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      if (smsHash != null && await isSmsAlreadyProcessed(smsHash)) {
        debugPrint("Create transaction skipped: SMS hash already exists.");
        return null;
      }

      final DateTime effectiveDate = transactionDate ?? DateTime.now();
      late final String transactionId;

      try {
        final inserted = await client
            .from('transactions')
            .insert({
              'user_id': user.id,
              'wallet_id': walletId,
              'amount': amount,
              'type': type,
              'description': description,
              'category_id': categoryId,
              'sms_hash': smsHash,
              'is_internal_transfer': isInternalTransfer,
              'transfer_group_id': transferGroupId,
              'merchant_name': merchantName,
              'sms_kind': smsKind,
              'date': effectiveDate.toUtc().toIso8601String(),
            })
            .select('id')
            .single();

        transactionId = inserted['id'] as String;
      } catch (insertError) {
        debugPrint('Create Transaction Insert Error: $insertError');
        return null;
      }

      double? newBalance;

      try {
        final walletData = await client
            .from('wallets')
            .select('balance')
            .eq('id', walletId)
            .single();

        final double currentBalance = (walletData['balance'] as num).toDouble();

        final double calculatedBalance = type.toLowerCase() == 'income'
            ? currentBalance + amount
            : currentBalance - amount;

        newBalance = calculatedBalance;

        if (balanceAfter != null) {
          final newerTransactions = await client
              .from('transactions')
              .select('id')
              .eq('wallet_id', walletId)
              .gt('date', effectiveDate.toUtc().toIso8601String())
              .limit(1);

          if (newerTransactions.isEmpty) {
            newBalance = balanceAfter;
          }
        }

        await client
            .from('wallets')
            .update({'balance': newBalance})
            .eq('id', walletId);
      } catch (walletError) {
        debugPrint(
          'Wallet update after transaction insert failed: $walletError',
        );
        return null;
      }

      // 5. Try to detect internal transfer after successful insertion
      if (!isInternalTransfer) {
        await detectAndMarkInternalTransfer(
          newTransactionId: transactionId,
          walletId: walletId,
          amount: amount,
          type: type,
          transactionDate: effectiveDate,
        );
      }

      await updateProfileNetWorth();

      unawaited(_refreshTransactionLookups(user.id));

      debugPrint("Transaction created successfully: $transactionId");
      debugPrint("Wallet balance updated: $newBalance");

      return transactionId;
    } catch (error) {
      debugPrint('Create Transaction Error: $error');
      return null;
    }
  }

  Future<void> updateTransaction({
    required Map<String, dynamic> oldTx,
    required Map<String, dynamic> newTx,
  }) async {
    try {
      final oldWalletId = oldTx['wallet_id'];
      final oldAmount = (oldTx['amount'] as num).toDouble();
      final oldType = oldTx['type'];

      final oldWalletData = await client
          .from('wallets')
          .select('balance')
          .eq('id', oldWalletId)
          .single();
      double oldWalletBalance = (oldWalletData['balance'] as num).toDouble();

      double restoredBalance = oldType.toLowerCase() == 'expense'
          ? oldWalletBalance + oldAmount
          : oldWalletBalance - oldAmount;

      await client
          .from('wallets')
          .update({'balance': restoredBalance})
          .eq('id', oldWalletId);

      final newWalletId = newTx['wallet_id'];
      final newAmount = (newTx['amount'] as num).toDouble();
      final newType = newTx['type'];

      final newWalletData = await client
          .from('wallets')
          .select('balance')
          .eq('id', newWalletId)
          .single();
      double currentNewWalletBalance = (newWalletData['balance'] as num)
          .toDouble();

      double finalBalance = newType.toLowerCase() == 'income'
          ? currentNewWalletBalance + newAmount
          : currentNewWalletBalance - newAmount;

      await client
          .from('wallets')
          .update({'balance': finalBalance})
          .eq('id', newWalletId);

      await client
          .from('transactions')
          .update({
            'wallet_id': newWalletId,
            'category_id': newTx['category_id'],
            'amount': newAmount,
            'type': newType,
            'description': newTx['description'],
          })
          .eq('id', oldTx['id']);

      await updateProfileNetWorth();

      debugPrint('Transaction successfully updated and balanced restored.');
    } catch (error) {
      debugPrint('Update Transaction Error: $error');
      rethrow;
    }
  }

  Future<int> getOrCreateTransferCategoryId() async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    final existing = await client
        .from('categories')
        .select('id')
        .eq('user_id', user.id)
        .eq('name', 'تحويل')
        .maybeSingle();

    if (existing != null) {
      return existing['id'] as int;
    }

    final inserted = await client
        .from('categories')
        .insert({
          'user_id': user.id,
          'name': 'تحويل',
          'type': 'Transfer',
          'icon': 'swap_horiz',
          'color': '#3B82F6',
        })
        .select('id')
        .single();

    return inserted['id'] as int;
  }

  Future<void> hideTransaction(String transactionId) async {
    try {
      await client
          .from('transactions')
          .update({'is_hidden': true})
          .eq('id', transactionId);

      debugPrint("Transaction hidden: $transactionId");
    } catch (e) {
      debugPrint("Hide transaction error: $e");
      rethrow;
    }
  }

  Future<void> transferFunds({
    required String fromWalletId,
    required String toWalletId,
    required double amount,
    String description = 'Internal Transfer',
  }) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      if (fromWalletId == toWalletId) {
        throw Exception("Cannot transfer to the same account");
      }

      if (amount <= 0) {
        throw Exception("Transfer amount must be greater than zero");
      }

      final transferGroupId =
          "manual_transfer_${DateTime.now().millisecondsSinceEpoch}";

      final int categoryId =
          await getOrCreateTransferCategoryId(); // Ensure the transfer category exists

      await createTransaction(
        walletId: fromWalletId,
        amount: amount,
        type: 'Expense',
        description: description,
        categoryId: categoryId,
        isInternalTransfer: true,
        transferGroupId: transferGroupId,
      );

      await createTransaction(
        walletId: toWalletId,
        amount: amount,
        type: 'Income',
        description: description,
        categoryId: categoryId,
        isInternalTransfer: true,
        transferGroupId: transferGroupId,
      );

      debugPrint("Manual internal transfer completed: $transferGroupId");
    } catch (error) {
      debugPrint("Transfer Funds Error: $error");
      rethrow;
    }
  }

  Future<void> deleteTransaction(Map<String, dynamic> transaction) async {
    try {
      final String walletId = transaction['wallet_id'];
      final double amount = (transaction['amount'] as num).toDouble();
      final String type = transaction['type'];

      await client.from('transactions').delete().eq('id', transaction['id']);

      final walletData = await client
          .from('wallets')
          .select('balance')
          .eq('id', walletId)
          .single();
      double currentBalance = (walletData['balance'] as num).toDouble();

      double correctedBalance = type.toLowerCase() == 'expense'
          ? currentBalance + amount
          : currentBalance - amount;

      await client
          .from('wallets')
          .update({'balance': correctedBalance})
          .eq('id', walletId);

      await updateProfileNetWorth();
    } catch (error) {
      debugPrint('Delete Transaction Error: $error');
      rethrow;
    }
  }

  Future<void> deleteTransactionSmart(Map<String, dynamic> tx) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      final bool isInternalTransfer = tx['is_internal_transfer'] == true;
      final String? transferGroupId = tx['transfer_group_id']?.toString();

      debugPrint("Delete Smart TX:");
      debugPrint("ID: ${tx['id']}");
      debugPrint("isInternalTransfer: $isInternalTransfer");
      debugPrint("transferGroupId: $transferGroupId");
      debugPrint("walletId: ${tx['wallet_id']}");
      debugPrint("amount: ${tx['amount']}");
      debugPrint("type: ${tx['type']}");

      if (isInternalTransfer &&
          transferGroupId != null &&
          transferGroupId.isNotEmpty) {
        final groupTransactions = await client
            .from('transactions')
            .select('id, wallet_id, amount, type')
            .eq('user_id', user.id)
            .eq('transfer_group_id', transferGroupId);

        for (final item in groupTransactions) {
          await _reverseWalletBalance(
            walletId: item['wallet_id'].toString(),
            amount: (item['amount'] as num).toDouble(),
            type: item['type'].toString(),
          );
        }

        await client
            .from('transactions')
            .delete()
            .eq('user_id', user.id)
            .eq('transfer_group_id', transferGroupId);

        debugPrint("Deleted internal transfer group: $transferGroupId");
        return;
      }

      await _reverseWalletBalance(
        walletId: tx['wallet_id'].toString(),
        amount: (tx['amount'] as num).toDouble(),
        type: tx['type'].toString(),
      );

      await client.from('transactions').delete().eq('id', tx['id']);

      debugPrint("Deleted single transaction: ${tx['id']}");
    } catch (e) {
      debugPrint("Smart delete transaction error: $e");
      rethrow;
    }
  }

  Future<void> _reverseWalletBalance({
    required String walletId,
    required double amount,
    required String type,
  }) async {
    final walletData = await client
        .from('wallets')
        .select('balance')
        .eq('id', walletId)
        .single();

    final double currentBalance = (walletData['balance'] as num).toDouble();

    final double newBalance = type.toLowerCase() == 'income'
        ? currentBalance - amount
        : currentBalance + amount;

    await client
        .from('wallets')
        .update({'balance': newBalance})
        .eq('id', walletId);

    await updateProfileNetWorth();

    debugPrint("Wallet reversed: $walletId => $newBalance");
  }

  Future<void> unhideTransaction(String transactionId) async {
    try {
      await client
          .from('transactions')
          .update({'is_hidden': false})
          .eq('id', transactionId);

      debugPrint("Transaction unhidden: $transactionId");
    } catch (e) {
      debugPrint("Unhide transaction error: $e");
      rethrow;
    }
  }

  Future<void> detectAndMarkInternalTransfer({
    required String newTransactionId,
    required String walletId,
    required double amount,
    required String type,
    required DateTime transactionDate,
  }) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return;

      final oppositeType = type.toLowerCase() == 'income'
          ? 'Expense'
          : 'Income';

      final windowStart = transactionDate.subtract(
        const Duration(minutes: 10),
      ); // 20-minute window to find matching transaction
      final windowEnd = transactionDate.add(
        const Duration(minutes: 10),
      ); // This accounts for slight delays in transaction recording and ensures we capture the correct match even if timestamps aren't perfectly aligned.
      // Debugging logs for internal transfer detection
      final matches = await client
          .from('transactions')
          .select('id, wallet_id, amount, type, date')
          .eq('user_id', user.id)
          .eq('type', oppositeType)
          .eq('amount', amount)
          .eq('is_internal_transfer', false)
          .neq('wallet_id', walletId)
          .gte('date', windowStart.toUtc().toIso8601String())
          .lte('date', windowEnd.toUtc().toIso8601String())
          .order('date', ascending: false)
          .limit(1);

      if (matches.isEmpty) {
        debugPrint("No internal transfer match found.");
        return;
      }

      final matchedTransaction = matches.first;
      final matchedId = matchedTransaction['id'] as String;

      final transferGroupId =
          "transfer_${DateTime.now().millisecondsSinceEpoch}";
      final int transferCategoryId = await getOrCreateTransferCategoryId();

      final currentWallet = await client
          .from('wallets')
          .select('name')
          .eq('id', walletId)
          .single();

      final matchedWallet = await client
          .from('wallets')
          .select('name')
          .eq('id', matchedTransaction['wallet_id'])
          .single();

      final String currentWalletName = currentWallet['name'].toString();
      final String matchedWalletName = matchedWallet['name'].toString();

      final bool newTransactionIsIncome = type.toLowerCase() == 'income';

      final String fromWalletName = newTransactionIsIncome
          ? matchedWalletName
          : currentWalletName;

      final String toWalletName = newTransactionIsIncome
          ? currentWalletName
          : matchedWalletName;

      final String transferDescription =
          "تحويل من $fromWalletName إلى $toWalletName";

      final String normalizedTransferDescription = transferDescription
          .replaceFirst(
            transferDescription,
            "Transfer from $fromWalletName to $toWalletName",
          );

      await client
          .from('transactions')
          .update({
            'type': 'Transfer',
            'is_internal_transfer': true,
            'transfer_group_id': transferGroupId,
            'category_id': transferCategoryId,
            'description': normalizedTransferDescription,
          })
          .inFilter('id', [newTransactionId, matchedId]);

      try {
        await NotificationService().showInternalTransferNotification(
          fromWallet: fromWalletName,
          toWallet: toWalletName,
          amount: amount,
        );
      } catch (notificationError) {
        debugPrint("Internal transfer notification error: $notificationError");
      }

      debugPrint("Internal transfer detected: $normalizedTransferDescription");
      debugPrint("Internal transfer detected and linked.");
    } catch (e) {
      debugPrint("Internal transfer detection error: $e");
    }
  }

  // ===========================================================================
  // 6. TASK OPERATIONS (TODO LIST)
  // ===========================================================================

  Future<List<TaskModel>> getTasks(DateTime date) async {
    try {
      return await _getTaskOccurrencesForRange(date, date);
    } catch (error) {
      return [];
    }
  }

  Future<List<TaskModel>> _getTaskOccurrencesForRange(
    DateTime start,
    DateTime end,
  ) async {
    final user = client.auth.currentUser;
    if (user == null) return [];

    final rangeStart = _dateOnly(start);
    final rangeEnd = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

    final response = await client
        .from('tasks')
        .select()
        .eq('user_id', user.id)
        .lte('due_date', rangeEnd.toIso8601String())
        .order('due_date');

    final tasks = (response as List)
        .map((task) => TaskModel.fromJson(task))
        .where((task) => !_dateOnly(task.endDate).isBefore(rangeStart))
        .toList();

    final occurrences = <TaskModel>[];

    for (final task in tasks) {
      for (
        var day = rangeStart;
        !day.isAfter(rangeEnd);
        day = day.add(const Duration(days: 1))
      ) {
        final occurrence = _taskOccurrenceOnDate(task, day);
        if (occurrence != null) {
          occurrences.add(occurrence);
        }
      }
    }

    occurrences.sort(
      (a, b) => (a.occurrenceDate ?? a.dueDate).compareTo(
        b.occurrenceDate ?? b.dueDate,
      ),
    );
    return occurrences;
  }

  TaskModel? _taskOccurrenceOnDate(TaskModel task, DateTime date) {
    final day = _dateOnly(date);
    final startDay = _dateOnly(task.dueDate);
    final endDay = _dateOnly(task.endDate);

    if (day.isBefore(startDay) || day.isAfter(endDay)) return null;

    final occursToday = switch (task.recurrenceType) {
      TaskModel.recurrenceDaily => true,
      TaskModel.recurrenceMonthly => day.day == task.dueDate.day,
      _ => _isSameDay(day, task.dueDate),
    };

    if (!occursToday) return null;

    return task.copyWith(
      occurrenceDate: DateTime(
        day.year,
        day.month,
        day.day,
        task.dueDate.hour,
        task.dueDate.minute,
      ),
    );
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _isSameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  Future<TaskModel> addTask(TaskModel task) async {
    try {
      final response = await client
          .from('tasks')
          .insert(task.toJson())
          .select()
          .single()
          .timeout(const Duration(seconds: 20));
      return TaskModel.fromJson(response);
    } catch (error) {
      debugPrint("Add task error: $error");
      rethrow;
    }
  }

  Future<bool> updateTask(
    TaskModel task, {
    bool rescheduleAlert = false,
    DateTime? newAlertTime,
  }) async {
    try {
      await client
          .from('tasks')
          .update(task.toJson())
          .eq('id', task.id)
          .timeout(const Duration(seconds: 20));
      await NotificationService().cancelTaskReminder(task.id);

      var reminderScheduled = false;
      if (rescheduleAlert && newAlertTime != null && !task.isCompleted) {
        reminderScheduled = await _scheduleTaskReminder(
          task.copyWith(reminderTime: newAlertTime),
          newAlertTime,
        );
      }

      if (rescheduleAlert || !task.hasNotification) {
        await updateTaskNotificationStatus(
          task.id,
          reminderScheduled,
          reminderTime: reminderScheduled ? newAlertTime : null,
          notificationId: reminderScheduled
              ? NotificationService.taskReminderId(task.id)
              : null,
        );
      }

      return reminderScheduled;
    } catch (error) {
      rethrow;
    }
  }

  Future<void> toggleTaskStatus(String taskId, bool currentStatus) async {
    try {
      final nextStatus = !currentStatus;
      await client
          .from('tasks')
          .update({
            'is_completed': nextStatus,
            if (nextStatus) ..._taskReminderStatusPayload(false),
          })
          .eq('id', taskId)
          .timeout(const Duration(seconds: 15));

      if (nextStatus) {
        await NotificationService().cancelTaskReminder(taskId);
      }
    } catch (error) {
      debugPrint("Toggle task status error: $error");
      rethrow;
    }
  }

  Future<void> updateTaskNotificationStatus(
    String taskId,
    bool hasNotification, {
    DateTime? reminderTime,
    int? notificationId,
  }) async {
    try {
      await client
          .from('tasks')
          .update(
            _taskReminderStatusPayload(
              hasNotification,
              reminderTime: reminderTime,
              notificationId: notificationId,
            ),
          )
          .eq('id', taskId)
          .timeout(const Duration(seconds: 15));
    } catch (error) {
      debugPrint("Update task notification status error: $error");
    }
  }

  Future<int> reschedulePendingTaskReminders() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return 0;

      final response = await client
          .from('tasks')
          .select()
          .eq('user_id', user.id)
          .eq('reminder_enabled', true)
          .eq('is_completed', false);

      var scheduledCount = 0;

      for (final row in response as List) {
        final task = TaskModel.fromJson(row);
        await NotificationService().cancelTaskReminder(task.id);

        if (!_shouldScheduleTaskReminder(task)) {
          debugPrint(
            "[FinMindNotifications] Skipped task reminder restore: task=${task.id}, reminderTime=${task.reminderTime}, completed=${task.isCompleted}",
          );
          await updateTaskNotificationStatus(task.id, false);
          continue;
        }

        final reminderTime = task.effectiveReminderTime!;
        final scheduled = await _scheduleTaskReminder(task, reminderTime);

        if (scheduled) {
          scheduledCount++;
          await updateTaskNotificationStatus(
            task.id,
            true,
            reminderTime: reminderTime,
            notificationId:
                task.notificationId ??
                NotificationService.taskReminderId(task.id),
          );
        } else {
          await updateTaskNotificationStatus(task.id, false);
        }
      }

      return scheduledCount;
    } catch (error) {
      debugPrint("Reschedule task reminders error: $error");
      return 0;
    }
  }

  Future<void> deleteTask(String taskId) async {
    try {
      await client
          .from('tasks')
          .delete()
          .eq('id', taskId)
          .timeout(const Duration(seconds: 15));
      await NotificationService().cancelTaskReminder(taskId);
    } catch (error) {
      debugPrint("Delete task error: $error");
      rethrow;
    }
  }

  Future<bool> scheduleTaskReminderForTask(
    TaskModel task,
    DateTime reminderTime,
  ) async {
    try {
      await NotificationService().cancelTaskReminder(task.id);
      final taskToSchedule = task.copyWith(
        hasNotification: true,
        reminderTime: reminderTime,
        notificationId:
            task.notificationId ?? NotificationService.taskReminderId(task.id),
      );
      final shouldSchedule = _shouldScheduleTaskReminder(taskToSchedule);

      if (!shouldSchedule) {
        debugPrint(
          "[FinMindNotifications] Task reminder not scheduled because reminder_time is missing, completed, or past.",
        );
        await updateTaskNotificationStatus(task.id, false);
        return false;
      }

      final scheduled = await _scheduleTaskReminder(
        taskToSchedule,
        reminderTime,
      );
      await updateTaskNotificationStatus(
        task.id,
        scheduled,
        reminderTime: scheduled ? reminderTime : null,
        notificationId: scheduled ? taskToSchedule.notificationId : null,
      );
      return scheduled;
    } catch (error) {
      debugPrint("Schedule task reminder error: $error");
      return false;
    }
  }

  Future<void> cancelTaskReminderForTask(String taskId) async {
    await NotificationService().cancelTaskReminder(taskId);
    await updateTaskNotificationStatus(taskId, false);
  }

  Future<bool> _scheduleTaskReminder(
    TaskModel task,
    DateTime reminderTime,
  ) async {
    final notificationId =
        task.notificationId ?? NotificationService.taskReminderId(task.id);
    final dueTime = _formatTaskTime(reminderTime);
    debugPrint("[FinMindNotifications] Selected due_date: ${task.dueDate}");
    debugPrint("[FinMindNotifications] Selected due_time: $dueTime");
    debugPrint(
      "[FinMindNotifications] Calculated reminder_time: $reminderTime",
    );
    debugPrint(
      "[FinMindNotifications] Current DateTime.now(): ${DateTime.now()}",
    );

    if (!reminderTime.isAfter(DateTime.now())) {
      debugPrint(
        "[FinMindNotifications] Schedule skipped: reminder_time is in the past.",
      );
      return false;
    }

    final scheduled = await NotificationService().scheduleTaskReminder(
      id: notificationId,
      title: task.title,
      body: _taskReminderBody(task, reminderTime),
      firstDateTime: reminderTime,
      recurrenceType: task.recurrenceType,
      payload: NotificationService.taskReminderPayload(task.id),
    );

    if (scheduled) {
      debugPrint(
        "[FinMindNotifications] Task reminder scheduled: id=$notificationId",
      );
    } else {
      debugPrint(
        "[FinMindNotifications] Task reminder schedule failed: ${NotificationService().lastReminderScheduleFailure ?? 'unknown reason'}",
      );
    }

    return scheduled;
  }

  bool _shouldScheduleTaskReminder(TaskModel task) {
    if (!task.hasNotification || task.isCompleted) return false;

    final now = DateTime.now();
    final reminderTime = task.effectiveReminderTime;
    if (reminderTime == null) return false;

    if (task.recurrenceType == TaskModel.recurrenceNone) {
      return reminderTime.isAfter(now);
    }

    final endOfEndDate = DateTime(
      task.endDate.year,
      task.endDate.month,
      task.endDate.day,
      23,
      59,
      59,
      999,
    );
    return endOfEndDate.isAfter(now);
  }

  Map<String, dynamic> _taskReminderStatusPayload(
    bool enabled, {
    DateTime? reminderTime,
    int? notificationId,
  }) {
    final payload = <String, dynamic>{
      'has_notification': enabled,
      'reminder_enabled': enabled,
      'reminder_time': enabled ? reminderTime?.toIso8601String() : null,
      'notification_id': enabled ? notificationId : null,
    };

    if (reminderTime != null) {
      payload['due_time'] = _formatTaskTime(reminderTime);
    }

    return payload;
  }

  String _taskReminderBody(TaskModel task, DateTime reminderTime) {
    final description = task.description.trim();
    if (description.isNotEmpty) return description;
    return "Due at ${_formatTaskTime(reminderTime)}";
  }

  String _formatTaskTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> executeTaskTransaction(TaskModel task) async {
    try {
      if (task.linkedWalletId == null || task.amount <= 0) return;

      final walletData = await client
          .from('wallets')
          .select('balance')
          .eq('id', task.linkedWalletId!)
          .single();
      double currentBalance = (walletData['balance'] as num).toDouble();
      double newBalance = currentBalance - task.amount;

      await client
          .from('wallets')
          .update({'balance': newBalance})
          .eq('id', task.linkedWalletId!);

      await updateProfileNetWorth();

      await client.from('transactions').insert({
        'user_id': task.userId,
        'wallet_id': task.linkedWalletId,
        'amount': task.amount,
        'type': 'Expense',
        'description': 'Linked Task Payment: ${task.title}',
      });
    } catch (e) {
      rethrow;
    }
  }

  // ===========================================================================
  // 7. ANALYTICS LOGIC
  // ===========================================================================

  Future<Map<String, double>> getFilteredSummary(String filter) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return {'Income': 0.0, 'Expense': 0.0};

      DateTime now = DateTime.now();
      DateTime startDate;

      switch (filter) {
        case 'Day':
          startDate = DateTime(now.year, now.month, now.day);
          break;
        case 'Week':
          startDate = now.subtract(Duration(days: now.weekday - 1));
          break;
        case 'Year':
          startDate = DateTime(now.year, 1, 1);
          break;
        case 'Month':
        default:
          startDate = DateTime(now.year, now.month, 1);
          break;
      }

      var query = client
          .from('transactions')
          .select('amount, type, sms_kind')
          .eq('user_id', user.id)
          .gte('date', startDate.toUtc().toIso8601String());

      query = query.or('is_hidden.is.null,is_hidden.eq.false');
      query = query.or(
        'is_internal_transfer.is.null,is_internal_transfer.eq.false',
      );

      final response = await query;

      Map<String, double> summary = {'Income': 0.0, 'Expense': 0.0};

      for (var item in response as List) {
        String type = item['type']?.toString() ?? '';
        final smsKind = item['sms_kind']?.toString().toLowerCase().trim();
        if (type.toLowerCase().trim() == 'transfer' ||
            smsKind == 'possible transfer') {
          continue;
        }
        if (type != 'Income' && type != 'Expense') continue;
        double amount = (item['amount'] as num).toDouble();
        if (summary.containsKey(type)) {
          summary[type] = (summary[type] ?? 0) + amount;
        }
      }
      return summary;
    } catch (error, stackTrace) {
      _logSupabaseIssue(_dbLogTag, 'get filtered summary', error, stackTrace);
      return {'Income': 0.0, 'Expense': 0.0};
    }
  }

  Future<Map<String, int>> getDailyTaskStats(DateTime date) async {
    try {
      final tasks = await getTasks(date);
      int total = tasks.length;
      int completed = tasks.where((task) => task.isCompleted).length;
      return {
        'total': total,
        'completed': completed,
        'pending': total - completed,
      };
    } catch (e) {
      return {'total': 0, 'completed': 0, 'pending': 0};
    }
  }

  Future<Map<String, int>> getMonthlyTaskStats(DateTime month) async {
    try {
      final firstDay = DateTime(month.year, month.month, 1);
      final lastDay = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
      final tasks = await _getTaskOccurrencesForRange(firstDay, lastDay);
      int total = tasks.length;
      int completed = tasks.where((task) => task.isCompleted).length;
      return {
        'total': total,
        'completed': completed,
        'pending': total - completed,
      };
    } catch (e) {
      return {'total': 0, 'completed': 0, 'pending': 0};
    }
  }

  Future<Map<DateTime, int>> getTasksCountForMonth(DateTime month) async {
    try {
      final firstDay = DateTime(month.year, month.month, 1);
      final lastDay = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
      final tasks = await _getTaskOccurrencesForRange(firstDay, lastDay);

      Map<DateTime, int> counts = {};
      for (final task in tasks) {
        DateTime normalizedDate = _dateOnly(
          task.occurrenceDate ?? task.dueDate,
        );
        counts[normalizedDate] = (counts[normalizedDate] ?? 0) + 1;
      }
      return counts;
    } catch (e) {
      return {};
    }
  }

  Future<Map<String, double>> getCategorySummary() async {
    return await getFilteredSummary('Month');
  }

  // ===========================================================================
  // 8. AUTOMATION & AI LOGIC (NEW SECTION)
  // ===========================================================================

  Future<String?> findWalletBySmsSender(String senderId) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return null;

      final response = await client
          .from('wallets')
          .select('id, name, sms_sender_id, account_mode, is_active_monitoring')
          .eq('user_id', user.id)
          .eq('account_mode', 'AUTOMATED')
          .eq('is_active_monitoring', true);

      debugPrint("Matching automated wallet by SMS sender.");
      debugPrint("[$_smsLogTag] Raw sender: $senderId");
      debugPrint(
        "[$_smsLogTag] Normalized sender: ${SmsHashService.normalizeSender(senderId)}",
      );
      final wallets = List<Map<String, dynamic>>.from(response as List);
      debugPrint(
        "[$_smsLogTag] Monitored senders: ${wallets.map((wallet) {
          final raw = wallet['sms_sender_id']?.toString() ?? '';
          return '$raw=>${SmsHashService.normalizeSender(raw)}';
        }).join(', ')}",
      );
      final matched = wallets.cast<Map<String, dynamic>?>().firstWhere((
        wallet,
      ) {
        final savedSender = wallet?['sms_sender_id']?.toString();
        return savedSender != null &&
            SmsHashService.senderMatches(savedSender, senderId);
      }, orElse: () => null);

      debugPrint("Automated wallet match found: ${matched != null}");
      debugPrint(
        "[$_smsLogTag] Matched wallet or ignored sender: ${matched == null ? 'ignored $senderId' : matched['name']}",
      );

      return matched != null ? matched['id'] as String : null;
    } catch (e, stackTrace) {
      _logSupabaseIssue(_dbLogTag, 'find wallet by SMS sender', e, stackTrace);
      return null;
    }
  }

  Future<String> getWalletNameById(String walletId) async {
    try {
      final wallet = await client
          .from('wallets')
          .select('name')
          .eq('id', walletId)
          .maybeSingle();

      return wallet?['name']?.toString() ?? 'Unknown Account';
    } catch (e) {
      debugPrint("Get wallet name error: $e");
      return 'Unknown Account';
    }
  }

  Future<SmsProcessingResult> processSmsTransactionRemotely({
    required String smsHash,
    required String senderId,
    required String smsBody,
    required DateTime receivedAt,
    String? walletId,
  }) async {
    try {
      debugPrint("[$_smsLogTag] Calling process_sms_transaction");
      final response = await client.functions.invoke(
        'process_sms_transaction',
        body: {
          'sms_hash': smsHash,
          'sender_id': senderId,
          'sms_body': smsBody,
          'received_at': receivedAt.toUtc().toIso8601String(),
          if (walletId != null) 'wallet_id': walletId,
        },
      );

      final data = response.data;
      if (data is Map) {
        return SmsProcessingResult.fromJson(Map<String, dynamic>.from(data));
      }

      return const SmsProcessingResult(
        status: 'invalid_response',
        processed: false,
      );
    } catch (error, stackTrace) {
      _logSupabaseIssue(
        _rpcLogTag,
        'process_sms_transaction edge function',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  Future<SmsProcessingResult> processParsedSmsTransactionAtomically({
    required String smsHash,
    required String senderId,
    required String smsBody,
    required DateTime receivedAt,
    String? walletId,
    Map<String, dynamic>? parsedData,
  }) async {
    try {
      DateTime transactionDate = receivedAt;
      final smsTimestamp = parsedData?['sms_timestamp'];
      if (smsTimestamp is int && smsTimestamp > 0) {
        transactionDate = DateTime.fromMillisecondsSinceEpoch(smsTimestamp);
      }

      final response = await client.rpc(
        'process_sms_transaction_atomic',
        params: {
          'p_sms_hash': smsHash,
          'p_sender_id': senderId,
          'p_sms_body': smsBody,
          'p_received_at': receivedAt.toUtc().toIso8601String(),
          'p_wallet_id': walletId,
          'p_amount': parsedData?['amount'],
          'p_type': parsedData?['type'],
          'p_available_balance': parsedData?['available_balance'],
          'p_transaction_date': transactionDate.toUtc().toIso8601String(),
          'p_sms_kind': parsedData?['sms_kind'],
          'p_category_hint': parsedData?['category_hint'],
          'p_merchant_name': parsedData?['merchant_name'],
          'p_counterparty': parsedData?['counterparty'],
          'p_is_cliq': parsedData?['is_cliq'] == true,
        },
      );

      if (response is Map) {
        return SmsProcessingResult.fromJson(
          Map<String, dynamic>.from(response),
        );
      }

      return const SmsProcessingResult(
        status: 'invalid_response',
        processed: false,
      );
    } catch (error, stackTrace) {
      _logSupabaseIssue(
        _rpcLogTag,
        'process_sms_transaction_atomic RPC',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  Future<bool> isSmsAlreadyProcessed(String smsHash) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return true;

      final response = await client
          .from('transactions')
          .select('id')
          .eq('user_id', user.id)
          .eq('sms_hash', smsHash)
          .limit(1);

      if ((response as List).isNotEmpty) {
        debugPrint("[$_smsLogTag] Duplicate skipped using transaction hash.");
        return true;
      }

      try {
        final logged = await client
            .from('sms_processing_logs')
            .select('id, status')
            .eq('user_id', user.id)
            .eq('sms_hash', smsHash)
            .limit(1);

        final logs = List<Map<String, dynamic>>.from(logged as List);
        if (logs.isNotEmpty) {
          final status = logs.first['status']?.toString();
          debugPrint(
            "[$_smsLogTag] Duplicate skipped using log status: ${status ?? 'unknown'}.",
          );
          return true;
        }
      } catch (logError, stackTrace) {
        _logSupabaseIssue(
          _dbLogTag,
          'SMS log duplicate check',
          logError,
          stackTrace,
        );
      }

      return false;
    } catch (e, stackTrace) {
      if (_isTransientNetworkError(e)) {
        debugPrint(
          "[$_smsLogTag] SMS duplicate check temporarily unavailable: $e",
        );
        rethrow;
      }

      _logSupabaseIssue(_dbLogTag, 'SMS duplicate check', e, stackTrace);
      return false;
    }
  }

  bool _isTransientNetworkError(Object error) {
    final text = error.toString();
    return text.contains("Failed host lookup") ||
        text.contains("SocketException") ||
        text.contains("Connection timed out") ||
        text.contains("Software caused connection abort") ||
        text.contains("Connection reset");
  }

  Future<void> recordSmsProcessingStatus({
    required String smsHash,
    required String senderId,
    required String status,
  }) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return;

      await client.from('sms_processing_logs').upsert({
        'user_id': user.id,
        'sms_hash': smsHash,
        'sender_id': senderId,
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,sms_hash');
      debugPrint("[$_smsLogTag] SMS processing status logged: $status.");
    } catch (e, stackTrace) {
      _logSupabaseIssue(
        _dbLogTag,
        'record SMS processing status',
        e,
        stackTrace,
      );
    }
  }

  Future<void> recordSmsProcessingIssue({
    required String smsHash,
    required String senderId,
    required String status,
  }) {
    return recordSmsProcessingStatus(
      smsHash: smsHash,
      senderId: senderId,
      status: status,
    );
  }

  Future<String> buildFinancialContextForAI() async {
    final user = client.auth.currentUser;
    if (user == null) return "No logged-in user.";

    final profile = await getProfileData();
    final wallets = await getWallets();
    final summary = await getFilteredSummary('Month');
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);

    String analyticsText = "Monthly category analytics unavailable.";
    try {
      final analyticsReport = await AnalyticsService().getAnalyticsReport(
        userId: user.id,
        startDate: monthStart,
        endDate: monthEnd,
      );

      analyticsText =
          """
Income by category this month:
${_formatCategoryAnalyticsForAI(analyticsReport.incomeCategories, emptyText: "- No income category data.")}

Expenses by category this month:
${_formatCategoryAnalyticsForAI(analyticsReport.expenseCategories, emptyText: "- No expense category data.")}
""";
    } catch (e) {
      debugPrint("AI analytics context error: $e");
    }

    String debtsText = "Debt tracking unavailable.";
    try {
      final debtsService = DebtsService();
      final activeDebts = await debtsService.getActiveDebts(user.id);
      final debtSummary = debtsService.buildSummary(activeDebts);

      debtsText =
          """
Debt tracking:
- Money owed to user (active debtor debts): ${debtSummary.totalDebtorAmount.toStringAsFixed(2)} JOD
- Money user owes (active creditor debts): ${debtSummary.totalCreditorAmount.toStringAsFixed(2)} JOD
- Net debt position: ${debtSummary.netDebt.toStringAsFixed(2)} JOD
- Important: debts are separate from wallet/account balances and are not transactions.

Active debt list:
${_formatDebtsForAI(activeDebts)}
""";
    } catch (e) {
      debugPrint("AI debts context error: $e");
    }

    final transactions = await client
        .from('transactions')
        .select(
          'amount, type, description, date, is_internal_transfer, wallets(name), categories(name)',
        )
        .eq('user_id', user.id)
        .eq('is_hidden', false)
        .order('date', ascending: false)
        .limit(10);

    final walletsText = wallets
        .map((w) {
          return "- ${w.name}: ${w.balance.toStringAsFixed(2)} ${w.currency}, type: ${w.type}";
        })
        .join("\n");

    final walletsContext = walletsText.isEmpty
        ? "- No wallets/accounts found."
        : walletsText;

    final txText = (transactions as List)
        .map((tx) {
          final walletName = tx['wallets'] is Map
              ? tx['wallets']['name']
              : 'Unknown';
          final categoryName = tx['categories'] is Map
              ? tx['categories']['name']
              : 'Uncategorized';
          final bool isInternalTransfer = tx['is_internal_transfer'] == true;
          final typeLabel = isInternalTransfer
              ? "Internal Transfer (${tx['type']})"
              : tx['type'];

          return "- $typeLabel ${tx['amount']} JOD, wallet: $walletName, category: $categoryName, date: ${tx['date']}, description: ${tx['description']}";
        })
        .join("\n");

    final recentTransactionsText = txText.isEmpty
        ? "- No recent visible transactions found."
        : txText;

    return """
User name: ${profile.fullName}
Current wallet/account net worth: ${profile.totalNetWorth.toStringAsFixed(2)} JOD
Current month period: ${monthStart.toIso8601String().split('T').first} to ${monthEnd.toIso8601String().split('T').first}
Monthly income, excluding internal transfers: ${(summary['Income'] ?? 0).toStringAsFixed(2)} JOD
Monthly expenses, excluding internal transfers: ${(summary['Expense'] ?? 0).toStringAsFixed(2)} JOD

Important interpretation rules:
- Wallet/account balances are separate from debts.
- Debts are not transactions and must not be added to wallet balances.
- Internal transfers are movement between user's accounts, not real income or spending.
- Income category percentages are calculated only from income transactions.
- Expense category percentages are calculated only from expense transactions.

Wallets:
$walletsContext

$analyticsText

$debtsText

Recent transactions:
$recentTransactionsText
""";
  }

  String _formatCategoryAnalyticsForAI(
    List<CategoryAnalytics> categories, {
    required String emptyText,
  }) {
    if (categories.isEmpty) return emptyText;

    return categories
        .take(8)
        .map((category) {
          return "- ${category.categoryName}: ${category.totalAmount.toStringAsFixed(2)} JOD (${category.percentage.toStringAsFixed(1)}%)";
        })
        .join("\n");
  }

  String _formatDebtsForAI(List<DebtModel> debts) {
    if (debts.isEmpty) return "- No active debts.";

    return debts
        .take(10)
        .map((debt) {
          final direction = debt.isDebtor
              ? "Debtor: this person owes the user"
              : "Creditor: the user owes this person";
          final dueDate = debt.dueDate == null
              ? "no due date"
              : debt.dueDate!.toIso8601String().split('T').first;
          final note = debt.note == null || debt.note!.trim().isEmpty
              ? ""
              : ", note: ${debt.note}";

          return "- ${debt.personName}: $direction, ${debt.amount.toStringAsFixed(2)} JOD, due: $dueDate$note";
        })
        .join("\n");
  }
  // ===========================================================================
  // 9. REAL-TIME STREAMS (OPTIONAL ADDITIONS FOR UI UPDATES)
  // ===========================================================================

  /// Real-time stream for account balances
  Stream<Map<String, double>> getBalancesStream() {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      return Stream.value({'Total': 0.0, 'Bank': 0.0, 'Cash': 0.0});
    }

    return client
        .from('wallets')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map((data) {
          double bankBalance = 0.0;
          double cashBalance = 0.0;
          for (var row in data) {
            final double bal = (row['balance'] as num?)?.toDouble() ?? 0.0;
            if (row['type'].toString().toLowerCase() == 'cash') {
              cashBalance += bal;
            } else {
              bankBalance += bal;
            }
          }
          return {
            'Total': bankBalance + cashBalance,
            'Bank': bankBalance,
            'Cash': cashBalance,
          };
        });
  }

  void _ensureTransactionLookupUser(String userId) {
    if (_transactionLookupUserId == userId) return;

    _transactionLookupUserId = userId;
    _transactionLookupRefreshUserId = null;
    _transactionLookupRefreshFuture = null;
    _transactionLookupCacheLoaded = false;
    _transactionWalletNameCache = {};
    _transactionCategoryNameCache = {};
  }

  String? _nestedLookupName(Map<String, dynamic> tx, String key) {
    final nested = tx[key];
    if (nested is Map && nested['name'] != null) {
      return nested['name'].toString();
    }
    return null;
  }

  bool _hasTransactionLookupCache(String userId) {
    _ensureTransactionLookupUser(userId);
    return _transactionLookupCacheLoaded;
  }

  bool _hasMissingTransactionLookups(
    List<Map<String, dynamic>> transactions,
    String userId,
  ) {
    _ensureTransactionLookupUser(userId);

    for (final tx in transactions) {
      final walletId = tx['wallet_id']?.toString();
      final categoryId = tx['category_id']?.toString();

      if (walletId != null &&
          !_transactionWalletNameCache.containsKey(walletId)) {
        return true;
      }

      if (categoryId != null &&
          !_transactionCategoryNameCache.containsKey(categoryId)) {
        return true;
      }
    }

    return false;
  }

  List<Map<String, dynamic>> _attachTransactionLookups(
    List<Map<String, dynamic>> transactions,
    String userId,
  ) {
    _ensureTransactionLookupUser(userId);

    return transactions
        .map((tx) {
          final walletId = tx['wallet_id']?.toString();
          final categoryId = tx['category_id']?.toString();

          return {
            ...tx,
            'wallet_name':
                _transactionWalletNameCache[walletId] ??
                tx['wallet_name']?.toString() ??
                _nestedLookupName(tx, 'wallets') ??
                'Unknown Account',
            'category_name':
                _transactionCategoryNameCache[categoryId] ??
                tx['category_name']?.toString() ??
                _nestedLookupName(tx, 'categories') ??
                'Uncategorized',
          };
        })
        .toList(growable: false);
  }

  Future<void> _refreshTransactionLookups(String userId) {
    _ensureTransactionLookupUser(userId);

    final inFlight = _transactionLookupRefreshFuture;
    if (inFlight != null && _transactionLookupRefreshUserId == userId) {
      return inFlight;
    }

    _transactionLookupRefreshUserId = userId;

    final refreshFuture = () async {
      try {
        final responses = await Future.wait([
          client.from('wallets').select('id, name').eq('user_id', userId),
          client.from('categories').select('id, name').eq('user_id', userId),
        ]);

        final walletsResponse = responses[0] as List;
        final categoriesResponse = responses[1] as List;

        if (_transactionLookupUserId != userId) return;

        _transactionWalletNameCache = {
          for (final wallet in walletsResponse)
            wallet['id'].toString(): wallet['name'].toString(),
        };

        _transactionCategoryNameCache = {
          for (final category in categoriesResponse)
            category['id'].toString(): category['name'].toString(),
        };

        _transactionLookupCacheLoaded = true;
      } catch (error) {
        debugPrint("Realtime lookup refresh failed: $error");
      } finally {
        if (_transactionLookupRefreshUserId == userId) {
          _transactionLookupRefreshUserId = null;
          _transactionLookupRefreshFuture = null;
        }
      }
    }();

    _transactionLookupRefreshFuture = refreshFuture;
    return refreshFuture;
  }

  /// Real-time stream for transactions
  Stream<List<Map<String, dynamic>>> getTransactionsStream({
    bool includeHidden = false,
  }) {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return Stream.value([]);

    return client
        .from('transactions')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('date', ascending: false)
        .asyncExpand((transactions) async* {
          final visibleTransactions = includeHidden
              ? List<Map<String, dynamic>>.from(transactions)
              : transactions
                    .where((tx) => tx['is_hidden'] != true)
                    .map((tx) => Map<String, dynamic>.from(tx))
                    .toList(growable: false);

          final shouldRefreshLookups =
              !_hasTransactionLookupCache(userId) ||
              _hasMissingTransactionLookups(visibleTransactions, userId);

          yield _attachTransactionLookups(visibleTransactions, userId);

          if (shouldRefreshLookups) {
            await _refreshTransactionLookups(userId);
            yield _attachTransactionLookups(visibleTransactions, userId);
          } else {
            unawaited(_refreshTransactionLookups(userId));
          }
        });
  }
  // ===========================================================================
  //  10. AI CHAT HISTORY OPERATIONS
  // ===========================================================================

  Future<String> createAiChat({String title = 'New Chat'}) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    final inserted = await client
        .from('ai_chats')
        .insert({'user_id': user.id, 'title': title})
        .select('id')
        .single();

    return inserted['id'] as String;
  }

  Future<List<Map<String, dynamic>>> getAiChats() async {
    final user = client.auth.currentUser;
    if (user == null) return [];

    final response = await client
        .from('ai_chats')
        .select('id, title, created_at, updated_at')
        .eq('user_id', user.id)
        .order('updated_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getAiMessages(String chatId) async {
    final user = client.auth.currentUser;
    if (user == null) return [];

    final response = await client
        .from('ai_messages')
        .select('id, text, is_ai, created_at')
        .eq('user_id', user.id)
        .eq('chat_id', chatId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> addAiMessage({
    required String chatId,
    required String text,
    required bool isAi,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    await client.from('ai_messages').insert({
      'chat_id': chatId,
      'user_id': user.id,
      'text': text,
      'is_ai': isAi,
    });

    await client
        .from('ai_chats')
        .update({'updated_at': DateTime.now().toIso8601String()})
        .eq('id', chatId)
        .eq('user_id', user.id);
  }

  Future<void> updateAiChatTitle({
    required String chatId,
    required String title,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    await client
        .from('ai_chats')
        .update({
          'title': title,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', chatId)
        .eq('user_id', user.id);
  }

  Future<void> deleteAiChat(String chatId) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    await client
        .from('ai_chats')
        .delete()
        .eq('id', chatId)
        .eq('user_id', user.id);
  }
}

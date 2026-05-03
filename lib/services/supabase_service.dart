// lib/services/supabase_service.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/category_model.dart';
import '../models/profile_model.dart';
import '../models/task_model.dart';
import '../models/wallet_model.dart';
import 'notification_service.dart';

class SupabaseService {
  // Singleton pattern to ensure only one instance of the service exists
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  // Initialize Supabase Client
  final SupabaseClient client = Supabase.instance.client;

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
      await client.from('profiles').insert({
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
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
      return ProfileModel.fromJson(response);
    } catch (error) {
      debugPrint('Get Profile Error: $error');
      rethrow;
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

      debugPrint("Wallet updated: ${wallet.name}");
      debugPrint("Mode: ${wallet.accountMode}");
      debugPrint("SMS Sender: ${wallet.smsSenderId}");
      debugPrint("Monitoring: ${wallet.isActiveMonitoring}");
    } catch (error) {
      debugPrint('Update Wallet Error: $error');
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

  // ===========================================================================
  // 5. TRANSACTION LOGIC & ANALYTICS
  // ===========================================================================

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
  }) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      // 1. Insert transaction and return its ID
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
          })
          .select('id')
          .single();

      final String transactionId = inserted['id'] as String;

      // 2. Read current wallet balance
      final walletData = await client
          .from('wallets')
          .select('balance')
          .eq('id', walletId)
          .single();

      final double currentBalance = (walletData['balance'] as num).toDouble();

      // 3. Calculate new balance
      final double newBalance = type.toLowerCase() == 'income'
          ? currentBalance + amount
          : currentBalance - amount;

      // 4. Update wallet balance
      await client
          .from('wallets')
          .update({'balance': newBalance})
          .eq('id', walletId);

      // 5. Try to detect internal transfer after successful insertion
      if (!isInternalTransfer) {
        await detectAndMarkInternalTransfer(
          newTransactionId: transactionId,
          walletId: walletId,
          amount: amount,
          type: type,
        );
      }

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

      debugPrint('Transaction successfully updated and balanced restored.');
    } catch (error) {
      debugPrint('Update Transaction Error: $error');
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

      final categories = await getCategories();
      final int categoryId = categories.isNotEmpty ? categories.first.id : 1;

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

    debugPrint("Wallet reversed: $walletId => $newBalance");
  }

  Future<void> detectAndMarkInternalTransfer({
    required String newTransactionId,
    required String walletId,
    required double amount,
    required String type,
  }) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return;

      final oppositeType = type.toLowerCase() == 'income'
          ? 'Expense'
          : 'Income';

      final now = DateTime.now();
      final windowStart = now.subtract(const Duration(minutes: 10));

      final matches = await client
          .from('transactions')
          .select('id, wallet_id, amount, type, date')
          .eq('user_id', user.id)
          .eq('type', oppositeType)
          .eq('amount', amount)
          .neq('wallet_id', walletId)
          .gte('date', windowStart.toIso8601String())
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

      await client
          .from('transactions')
          .update({
            'is_internal_transfer': true,
            'transfer_group_id': transferGroupId,
          })
          .inFilter('id', [newTransactionId, matchedId]);

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
      final user = client.auth.currentUser;
      if (user == null) return [];

      final dateStr = date.toIso8601String().split('T')[0];
      final response = await client
          .from('tasks')
          .select()
          .eq('user_id', user.id)
          .gte('due_date', '$dateStr 00:00:00')
          .lte('due_date', '$dateStr 23:59:59');

      return (response as List)
          .map((task) => TaskModel.fromJson(task))
          .toList();
    } catch (error) {
      return [];
    }
  }

  Future<TaskModel> addTask(TaskModel task) async {
    try {
      final response = await client
          .from('tasks')
          .insert(task.toJson())
          .select()
          .single();
      return TaskModel.fromJson(response);
    } catch (error) {
      rethrow;
    }
  }

  Future<void> updateTask(
    TaskModel task, {
    bool rescheduleAlert = false,
    DateTime? newAlertTime,
  }) async {
    try {
      await client.from('tasks').update(task.toJson()).eq('id', task.id);
      await NotificationService().cancelNotification(task.id.hashCode);

      if (rescheduleAlert &&
          newAlertTime != null &&
          newAlertTime.isAfter(DateTime.now())) {
        await NotificationService().scheduleNotification(
          task.id.hashCode,
          "Task Reminder",
          task.title,
          newAlertTime,
        );
      }
    } catch (error) {
      rethrow;
    }
  }

  Future<void> toggleTaskStatus(String taskId, bool currentStatus) async {
    try {
      await client
          .from('tasks')
          .update({'is_completed': !currentStatus})
          .eq('id', taskId);
    } catch (error) {}
  }

  Future<void> updateTaskNotificationStatus(
    String taskId,
    bool hasNotification,
  ) async {
    try {
      await client
          .from('tasks')
          .update({'has_notification': hasNotification})
          .eq('id', taskId);
    } catch (error) {}
  }

  Future<void> deleteTask(String taskId) async {
    try {
      await client.from('tasks').delete().eq('id', taskId);
      await NotificationService().cancelNotification(taskId.hashCode);
    } catch (error) {}
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

      final response = await client
          .from('transactions')
          .select('amount, type')
          .eq('user_id', user.id)
          .eq('is_internal_transfer', false)
          .gte('created_at', startDate.toIso8601String());

      Map<String, double> summary = {'Income': 0.0, 'Expense': 0.0};

      for (var item in response as List) {
        String type = item['type'];
        double amount = (item['amount'] as num).toDouble();
        if (summary.containsKey(type)) {
          summary[type] = (summary[type] ?? 0) + amount;
        }
      }
      return summary;
    } catch (error) {
      return {'Income': 0.0, 'Expense': 0.0};
    }
  }

  Future<Map<String, int>> getDailyTaskStats(DateTime date) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return {'total': 0, 'completed': 0, 'pending': 0};

      final dateStr = date.toIso8601String().split('T')[0];
      final response = await client
          .from('tasks')
          .select('is_completed')
          .eq('user_id', user.id)
          .gte('due_date', '$dateStr 00:00:00')
          .lte('due_date', '$dateStr 23:59:59');

      final List tasks = response as List;
      int total = tasks.length;
      int completed = tasks.where((t) => t['is_completed'] == true).length;
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
      final user = client.auth.currentUser;
      if (user == null) return {'total': 0, 'completed': 0, 'pending': 0};

      final firstDay = DateTime(month.year, month.month, 1);
      final lastDay = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
      final response = await client
          .from('tasks')
          .select('is_completed')
          .eq('user_id', user.id)
          .gte('due_date', firstDay.toIso8601String())
          .lte('due_date', lastDay.toIso8601String());

      final List tasks = response as List;
      int total = tasks.length;
      int completed = tasks.where((t) => t['is_completed'] == true).length;
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
      final user = client.auth.currentUser;
      if (user == null) return {};

      final firstDay = DateTime(month.year, month.month, 1);
      final lastDay = DateTime(month.year, month.month + 1, 0);
      final response = await client
          .from('tasks')
          .select('due_date')
          .eq('user_id', user.id)
          .gte('due_date', firstDay.toIso8601String())
          .lte('due_date', lastDay.toIso8601String());

      Map<DateTime, int> counts = {};
      for (var row in response as List) {
        DateTime date = DateTime.parse(row['due_date']);
        DateTime normalizedDate = DateTime(date.year, date.month, date.day);
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
          .eq('sms_sender_id', senderId)
          .eq('account_mode', 'AUTOMATED')
          .eq('is_active_monitoring', true)
          .maybeSingle();

      debugPrint("Matching sender: $senderId");
      debugPrint("Matched wallet: $response");

      return response != null ? response['id'] as String : null;
    } catch (e) {
      debugPrint("Error finding wallet by sender: $e");
      return null;
    }
  }

  Future<void> processAutomatedTransaction(
    Map<String, dynamic> aiData,
    String senderId, {
    String? smsHash,
  }) async {
    try {
      final String? walletId = await findWalletBySmsSender(senderId);

      if (walletId == null) {
        debugPrint("No linked wallet found for sender: $senderId");
        return;
      }
      if (smsHash != null) {
        final alreadyProcessed = await isSmsAlreadyProcessed(smsHash);
        if (alreadyProcessed) {
          debugPrint("SMS already processed. Skipping.");
          return;
        }
      }

      final categories = await getCategories();
      final int categoryId = categories.isNotEmpty ? categories.first.id : 1;

      final double amount = (aiData['amount'] as num).toDouble();
      final String type = aiData['type'] ?? 'Expense';
      final String bank = aiData['bank'] ?? senderId;

      await createTransaction(
        walletId: walletId,
        amount: amount,
        type: type,
        description: "SMS Auto Transaction - $bank",
        categoryId: categoryId,
        smsHash: smsHash,
      );
      debugPrint("SMS transaction added to dashboard successfully.");
    } catch (e) {
      debugPrint("SMS automation error: $e");
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
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint("SMS duplicate check error: $e");
      return true;
    }
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
            final double bal = (row['balance'] as num).toDouble();
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

  /// Real-time stream for transactions
  Stream<List<Map<String, dynamic>>> getTransactionsStream() {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return Stream.value([]);

    return client
        .from('transactions')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .asyncMap((transactions) async {
          final walletsResponse = await client
              .from('wallets')
              .select('id, name')
              .eq('user_id', userId);

          final categoriesResponse = await client
              .from('categories')
              .select('id, name')
              .eq('user_id', userId);

          final Map<String, String> walletNames = {
            for (final wallet in walletsResponse)
              wallet['id'].toString(): wallet['name'].toString(),
          };

          final Map<String, String> categoryNames = {
            for (final category in categoriesResponse)
              category['id'].toString(): category['name'].toString(),
          };

          return transactions.map((tx) {
            final walletId = tx['wallet_id']?.toString();
            final categoryId = tx['category_id']?.toString();

            return {
              ...tx,
              'wallet_name': walletNames[walletId] ?? 'Unknown Account',
              'category_name': categoryNames[categoryId] ?? 'Uncategorized',
            };
          }).toList();
        });
  }
}

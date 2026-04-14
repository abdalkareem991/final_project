// lib/services/supabase_service.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/category_model.dart';
import '../models/profile_model.dart';
import '../models/task_model.dart';
import '../models/wallet_model.dart';
import 'notification_service.dart';

class SupabaseService {
  // Initialize Supabase Client
  final SupabaseClient client = Supabase.instance.client;

  // ===========================================================================
  // 1. AUTHENTICATION OPERATIONS
  // ===========================================================================

  /// Signs in a user with email and password
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

  /// Registers a new user
  Future<AuthResponse> signUp(String email, String password) async {
    try {
      return await client.auth.signUp(email: email, password: password);
    } catch (error) {
      debugPrint('Sign Up Error: $error');
      rethrow;
    }
  }

  /// Sends a password reset link to the user's email
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

  /// Updates the current user's password
  Future<void> updatePassword(String newPassword) async {
    try {
      await client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (error) {
      debugPrint('Update Password Error: $error');
      rethrow;
    }
  }

  // ===========================================================================
  // 2. PROFILE & USER DATA OPERATIONS
  // ===========================================================================

  /// Creates a new user profile entry in the database
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

  /// Retrieves the current logged-in user's profile
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
  // 3. WALLET / ACCOUNT OPERATIONS
  // ===========================================================================

  /// Adds a new wallet using the WalletModel structure
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
      });
      debugPrint('Wallet added successfully');
    } catch (error) {
      debugPrint('Add Wallet Error: $error');
      rethrow;
    }
  }

  /// Dynamically calculates the total balance from all active wallets
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

  /// Separates Bank balances from Cash balances
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

  /// Fetches all wallets associated with the current user
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

  /// Deletes a specific wallet and its linked data
  Future<void> deleteWallet(String walletId) async {
    try {
      await client.from('wallets').delete().eq('id', walletId);
      debugPrint('Wallet deleted successfully');
    } catch (error) {
      debugPrint('Delete Wallet Error: $error');
      rethrow;
    }
  }

  /// Updates an existing wallet using the WalletModel structure
  Future<void> updateWallet(WalletModel wallet) async {
    try {
      final Map<String, dynamic> updateData = {
        'name': wallet.name,
        'balance': wallet.balance,
        'type': wallet.type,
        'currency': wallet.currency,
      };

      await client.from('wallets').update(updateData).eq('id', wallet.id);
      debugPrint('Wallet updated successfully');
    } catch (error) {
      debugPrint('Update Wallet Error: $error');
      rethrow;
    }
  }

  // ===========================================================================
  // 4. CATEGORY OPERATIONS
  // ===========================================================================

  /// Fetches all categories (Income & Expense) for the user
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

  /// Adds a new custom category for the current user
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

      debugPrint('Custom category added successfully');
      return CategoryModel.fromJson(response);
    } catch (error) {
      debugPrint('Add Category Error: $error');
      rethrow;
    }
  }

  // ===========================================================================
  // 5. TRANSACTION LOGIC & ANALYTICS
  // ===========================================================================

  /// Fetches transactions for account statement
  Future<List<Map<String, dynamic>>> getTransactions() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return [];

      // Join with wallets to get the bank name
      final response = await client
          .from('transactions')
          .select('*, wallets(name)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      debugPrint('Fetch Transactions Error: $error');
      return [];
    }
  }

  /// Records a manual transaction and updates wallet balance
  Future<void> createTransaction({
    required String walletId,
    required double amount,
    required String type,
    required String description,
    required int categoryId,
  }) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      // 1. Insert transaction record
      await client.from('transactions').insert({
        'user_id': user.id,
        'wallet_id': walletId,
        'amount': amount,
        'type': type,
        'description': description,
        'category_id': categoryId,
      });

      // 2. Fetch current wallet balance
      final walletData = await client
          .from('wallets')
          .select('balance')
          .eq('id', walletId)
          .single();

      double currentBalance = (walletData['balance'] as num).toDouble();

      // 3. Calculate new balance
      double newBalance = type.toLowerCase() == 'income'
          ? currentBalance + amount
          : currentBalance - amount;

      // 4. Update the wallet
      await client
          .from('wallets')
          .update({'balance': newBalance})
          .eq('id', walletId);

      debugPrint('Transaction and Balance Update Successful');
    } catch (error) {
      debugPrint('Create Transaction Error: $error');
      rethrow;
    }
  }

  /// Executes a secure transfer between two wallets and logs the transactions
  Future<void> transferFunds({
    required String fromWalletId,
    required String toWalletId,
    required double amount,
    required String description,
    required int categoryId,
  }) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      // 1. Fetch current balances
      final fromWalletData = await client
          .from('wallets')
          .select('balance')
          .eq('id', fromWalletId)
          .single();
      final toWalletData = await client
          .from('wallets')
          .select('balance')
          .eq('id', toWalletId)
          .single();

      double fromBalance = (fromWalletData['balance'] as num).toDouble();
      double toBalance = (toWalletData['balance'] as num).toDouble();

      // 2. Logical Validation
      if (fromBalance < amount) throw Exception("Insufficient funds.");

      // 3. Update balances
      await client
          .from('wallets')
          .update({'balance': fromBalance - amount})
          .eq('id', fromWalletId);
      await client
          .from('wallets')
          .update({'balance': toBalance + amount})
          .eq('id', toWalletId);

      // 4. Log transactions
      await client.from('transactions').insert([
        {
          'user_id': user.id,
          'wallet_id': fromWalletId,
          'amount': amount,
          'type': 'Expense',
          'description': 'Transfer Out: $description',
          'category_id': categoryId,
        },
        {
          'user_id': user.id,
          'wallet_id': toWalletId,
          'amount': amount,
          'type': 'Income',
          'description': 'Transfer In: $description',
          'category_id': categoryId,
        },
      ]);
    } catch (error) {
      debugPrint('Transfer Error: $error');
      rethrow;
    }
  }

  /// Deletes a transaction and REVERSES the balance impact on the wallet
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
      debugPrint('Fetch Tasks Error: $error');
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
}

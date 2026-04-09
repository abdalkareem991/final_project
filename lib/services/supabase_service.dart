// lib/services/supabase_service.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_model.dart';
import '../models/task_model.dart';
import '../models/wallet_model.dart';

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
        'total_net_worth': 0,
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

  /// Adds a new wallet for the current user
  Future<void> addWallet({
    required String name,
    required double balance,
    required String type,
  }) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      await client.from('wallets').insert({
        'user_id': user.id,
        'name': name,
        'balance': balance,
        'type': type,
      });
    } catch (error) {
      debugPrint('Add Wallet Error: $error');
      rethrow;
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

  // ===========================================================================
  // 4. TRANSACTION LOGIC & ANALYTICS
  // ===========================================================================

  /// Fetches transactions for account statement
  Future<List<Map<String, dynamic>>> getTransactions() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return [];

      final response = await client
          .from('transactions')
          .select()
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
      });

      // 2. Update wallet balance
      final walletData = await client
          .from('wallets')
          .select('balance')
          .eq('id', walletId)
          .single();
      double currentBalance = (walletData['balance'] as num).toDouble();
      double newBalance = type.toLowerCase() == 'income'
          ? currentBalance + amount
          : currentBalance - amount;

      await client
          .from('wallets')
          .update({'balance': newBalance})
          .eq('id', walletId);
      debugPrint('Manual transaction successful.');
    } catch (error) {
      debugPrint('Create Transaction Error: $error');
      rethrow;
    }
  }

  // ===========================================================================
  // 5. TASK OPERATIONS (TODO LIST)
  // ===========================================================================

  /// Fetches tasks for a specific day
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

  /// Adds a new task with safety checks
  Future<void> addTask(TaskModel task) async {
    try {
      await client.from('tasks').insert(task.toJson());
      debugPrint('Task saved successfully to cloud database.');
    } on PostgrestException catch (error) {
      debugPrint('Postgrest Error (Code: ${error.code}): ${error.message}');
      rethrow;
    } catch (error) {
      debugPrint('Unexpected Error in addTask: $error');
      rethrow;
    }
  }

  /// Toggles task status in the database
  Future<void> toggleTaskStatus(String taskId, bool currentStatus) async {
    try {
      await client
          .from('tasks')
          .update({'is_completed': !currentStatus})
          .eq('id', taskId);
    } catch (error) {
      debugPrint('Toggle Task Error: $error');
    }
  }

  /// Deletes a specific task
  Future<void> deleteTask(String taskId) async {
    try {
      await client.from('tasks').delete().eq('id', taskId);
    } catch (error) {
      debugPrint('Delete Task Error: $error');
    }
  }

  /// Executes a wallet transaction linked to a specific task completion
  Future<void> executeTaskTransaction(TaskModel task) async {
    try {
      if (task.linkedWalletId == null || task.amount <= 0) return;

      // 1. Fetch linked wallet balance
      final walletData = await client
          .from('wallets')
          .select('balance')
          .eq('id', task.linkedWalletId!)
          .single();
      double currentBalance = (walletData['balance'] as num).toDouble();
      double newBalance = currentBalance - task.amount;

      // 2. Update wallet balance
      await client
          .from('wallets')
          .update({'balance': newBalance})
          .eq('id', task.linkedWalletId!);

      // 3. Log into transactions history
      await client.from('transactions').insert({
        'user_id': task.userId,
        'wallet_id': task.linkedWalletId,
        'amount': task.amount,
        'type': 'Expense',
        'description': 'Linked Task Payment: ${task.title}',
      });

      debugPrint('Financial deduction successful for task: ${task.title}');
    } catch (e) {
      debugPrint('Task Transaction Action Error: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // 6. ANALYTICS LOGIC
  // ===========================================================================

  /// Fetches summary data for analytics
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
      debugPrint('Analytics Filter Error: $error');
      return {'Income': 0.0, 'Expense': 0.0};
    }
  }

  // 1. Get stats for the "Cards" at the top
  Future<Map<String, int>> getTaskStats() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return {'total': 0, 'completed': 0, 'pending': 0};

      final response = await client
          .from('tasks')
          .select('is_completed')
          .eq('user_id', user.id);

      final List tasks = response as List;
      int total = tasks.length;
      int completed = tasks.where((t) => t['is_completed'] == true).length;
      int pending = total - completed;

      return {'total': total, 'completed': completed, 'pending': pending};
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      return {'total': 0, 'completed': 0, 'pending': 0};
    }
  }

  // 2. Get task counts per day for the Calendar
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
      debugPrint('Error fetching calendar counts: $e');
      return {};
    }
  }

  /// Legacy compatibility
  Future<Map<String, double>> getCategorySummary() async {
    return await getFilteredSummary('Month');
  }
}

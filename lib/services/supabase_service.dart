// lib/services/supabase_service.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_model.dart';
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

  /// Adds a new wallet or account for the current user
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

  // ===========================================================================
  // 4. TRANSACTION LOGIC & ANALYTICS
  // ===========================================================================

  /// Records a transaction and updates the corresponding wallet balance
  Future<void> createTransaction({
    required String walletId,
    required double amount,
    required String type, // 'Income' or 'Expense'
    required String description,
  }) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      // Insert transaction record
      await client.from('transactions').insert({
        'user_id': user.id,
        'wallet_id': walletId,
        'amount': amount,
        'type': type,
        'description': description,
      });

      // Fetch current wallet balance
      final walletData = await client
          .from('wallets')
          .select('balance')
          .eq('id', walletId)
          .single();

      double currentBalance = (walletData['balance'] as num).toDouble();

      // Calculate new balance
      double newBalance = type.toLowerCase() == 'income'
          ? currentBalance + amount
          : currentBalance - amount;

      // Update wallet balance in DB
      await client
          .from('wallets')
          .update({'balance': newBalance})
          .eq('id', walletId);

      debugPrint('Transaction Successful. New Balance: $newBalance');
    } catch (error) {
      debugPrint('Create Transaction Error: $error');
      rethrow;
    }
  }

  /// Fetches a filtered summary of transactions for analytics (Day, Week, Month, Year)
  Future<Map<String, double>> getFilteredSummary(String filter) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return {'Income': 0.0, 'Expense': 0.0};

      DateTime now = DateTime.now();
      DateTime startDate;

      // Determine the start date based on the selected filter
      switch (filter) {
        case 'Day':
          startDate = DateTime(now.year, now.month, now.day);
          break;
        case 'Week':
          // Subtract days to get the start of the week (Monday)
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
        String type =
            item['type']; // Ensure your DB values are exactly 'Income' or 'Expense'
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

  /// Legacy compatibility alias for getFilteredSummary
  Future<Map<String, double>> getCategorySummary() async {
    return await getFilteredSummary('Month');
  }
}

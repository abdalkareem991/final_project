import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wallet_model.dart';
import '../models/profile_model.dart';

class SupabaseService {
  // Initialize Supabase Client
  final SupabaseClient client = Supabase.instance.client;

  // ===========================================================================
  // 1. AUTHENTICATION OPERATIONS
  // ===========================================================================

  // Sign in with Email and Password
  Future<AuthResponse> signIn(String email, String password) async {
    try {
      return await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (error) {
      print('Sign In Error: $error');
      rethrow;
    }
  }

  // Register a new user
  Future<AuthResponse> signUp(String email, String password) async {
    try {
      return await client.auth.signUp(email: email, password: password);
    } catch (error) {
      print('Sign Up Error: $error');
      rethrow;
    }
  }

  // Send password reset link to user email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.flutter://reset-callback/',
      );
    } catch (error) {
      print('Reset Error: $error');
      rethrow;
    }
  }

  // Update the user's password in the database
  Future<void> updatePassword(String newPassword) async {
    try {
      await client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (error) {
      print('Update Error: $error');
      rethrow;
    }
  }

  // ===========================================================================
  // 2. PROFILE & USER DATA OPERATIONS
  // ===========================================================================

  // Create user profile
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
      print('Profile Creation Error: $error');
      rethrow;
    }
  }

  // Fetch current user's profile data
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
      print('Get Profile Error: $error');
      rethrow;
    }
  }

  // ===========================================================================
  // 3. WALLET / ACCOUNT OPERATIONS
  // ===========================================================================

  // Requirement: Add a new Wallet/Account to the database
  Future<void> addWallet({
    required String name,
    required double balance,
    required String type, // e.g., 'Bank', 'Cash', 'Saving'
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
      print('Wallet $name added successfully.');
    } catch (error) {
      print('Add Wallet Error: $error');
      rethrow;
    }
  }

  // Fetch all wallets for the current user
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
      print('Fetch Wallets Error: $error');
      rethrow;
    }
  }

  // ===========================================================================
  // 4. TRANSACTION LOGIC (CORE FUNCTIONALITY)
  // ===========================================================================

  // Requirement: Handle transaction entry and automatic wallet balance update
  Future<void> createTransaction({
    required String walletId,
    required double amount,
    required String type, // 'Income' or 'Expense'
    required String description,
  }) async {
    try {
      final user = client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      // Step A: Insert record into transactions table
      await client.from('transactions').insert({
        'user_id': user.id,
        'wallet_id': walletId,
        'amount': amount,
        'type': type,
        'description': description,
      });

      // Step B: Get current wallet balance to calculate new value
      final walletData = await client
          .from('wallets')
          .select('balance')
          .eq('id', walletId)
          .single();

      double currentBalance = (walletData['balance'] as num).toDouble();

      // Step C: Business Logic - Update balance based on type
      double newBalance = type.toLowerCase() == 'income'
          ? currentBalance + amount
          : currentBalance - amount;

      // Step D: Update the wallet balance in the database
      await client
          .from('wallets')
          .update({'balance': newBalance})
          .eq('id', walletId);

      print('Transaction successful. New balance: $newBalance');
    } catch (error) {
      print('Create Transaction Error: $error');
      rethrow;
    }
  }

  // Alias for compatibility
  Future<void> addTransaction({
    required String walletId,
    required double amount,
    required String description,
    String? categoryId,
    required String type,
  }) async {
    await createTransaction(
      walletId: walletId,
      amount: amount,
      type: type,
      description: description,
    );
  }
}

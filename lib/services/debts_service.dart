import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/debts_model.dart';

class DebtsService {
  final SupabaseClient client = Supabase.instance.client;

  String? get currentUserId => client.auth.currentUser?.id;

  Future<List<DebtModel>> getActiveDebts(String userId) async {
    return getDebts(userId: userId, status: 'active');
  }

  Future<List<DebtModel>> getActiveDebtsForCurrentUser() async {
    final userId = currentUserId;
    if (userId == null) throw Exception("User not logged in");
    return getActiveDebts(userId);
  }

  Future<List<DebtModel>> getDebts({
    required String userId,
    String? status,
  }) async {
    try {
      var query = client.from('debts').select().eq('user_id', userId);

      if (status != null) {
        query = query.eq('status', status);
      }

      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(
        response,
      ).map(DebtModel.fromJson).toList();
    } catch (error) {
      debugPrint('Fetch debts error: $error');
      rethrow;
    }
  }

  Future<void> addDebt(DebtModel debt) async {
    try {
      final userId = currentUserId;
      if (userId == null) throw Exception("User not logged in");

      await client
          .from('debts')
          .insert(debt.toInsertJson(fallbackUserId: userId));
    } catch (error) {
      debugPrint('Add debt error: $error');
      rethrow;
    }
  }

  Future<void> updateDebt(DebtModel debt) async {
    try {
      final userId = currentUserId;
      if (userId == null) throw Exception("User not logged in");

      await client
          .from('debts')
          .update(debt.toUpdateJson())
          .eq('id', debt.id)
          .eq('user_id', userId);
    } catch (error) {
      debugPrint('Update debt error: $error');
      rethrow;
    }
  }

  Future<void> deleteDebt(String debtId) async {
    try {
      final userId = currentUserId;
      if (userId == null) throw Exception("User not logged in");

      await client
          .from('debts')
          .delete()
          .eq('id', debtId)
          .eq('user_id', userId);
    } catch (error) {
      debugPrint('Delete debt error: $error');
      rethrow;
    }
  }

  Future<void> markDebtAsPaid(String debtId) async {
    try {
      final userId = currentUserId;
      if (userId == null) throw Exception("User not logged in");

      await client
          .from('debts')
          .update({
            'status': 'paid',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', debtId)
          .eq('user_id', userId);
    } catch (error) {
      debugPrint('Mark debt as paid error: $error');
      rethrow;
    }
  }

  Future<double> getTotalDebtorAmount(String userId) async {
    final debts = await getActiveDebts(userId);
    return debts
        .where((debt) => debt.isDebtor)
        .fold<double>(0.0, (sum, debt) => sum + debt.amount);
  }

  Future<double> getTotalCreditorAmount(String userId) async {
    final debts = await getActiveDebts(userId);
    return debts
        .where((debt) => debt.isCreditor)
        .fold<double>(0.0, (sum, debt) => sum + debt.amount);
  }

  DebtSummary buildSummary(List<DebtModel> debts) {
    double totalDebtorAmount = 0.0;
    double totalCreditorAmount = 0.0;

    for (final debt in debts.where((debt) => debt.isActive)) {
      if (debt.isDebtor) {
        totalDebtorAmount += debt.amount;
      } else if (debt.isCreditor) {
        totalCreditorAmount += debt.amount;
      }
    }

    return DebtSummary(
      totalDebtorAmount: totalDebtorAmount,
      totalCreditorAmount: totalCreditorAmount,
    );
  }
}

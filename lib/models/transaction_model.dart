// lib/models/transaction_model.dart
class TransactionModel {
  final String id;
  final double amount;
  final String description;
  final DateTime date;
  final String type; // income or expense

  TransactionModel({
    required this.id,
    required this.amount,
    required this.description,
    required this.date,
    required this.type,
  });

  // Convert JSON from Supabase to Dart Object
  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'],
      amount: json['amount'].toDouble(),
      description: json['description'],
      date: DateTime.parse(json['date']),
      type: json['type'],
    );
  }
}

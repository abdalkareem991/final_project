// lib/models/transaction_model.dart
class TransactionModel {
  final String id;
  final double amount;
  final String description;
  final DateTime date;
  final String type;
  final String categoryId;
  final String walletId;
  final bool isInternalTransfer;
  final String? transferGroupId;

  TransactionModel({
    required this.id,
    required this.amount,
    required this.description,
    required this.date,
    required this.type,
    required this.categoryId, // Add this
    required this.walletId, // Add this
    this.isInternalTransfer = false,
    this.transferGroupId,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'],
      amount: json['amount'].toDouble(),
      description: json['description'],
      date: DateTime.parse(json['date']),
      type: json['type'],
      categoryId: json['category_id'] ?? '',
      walletId: json['wallet_id'] ?? '',
      isInternalTransfer: json['is_internal_transfer'] ?? false,
      transferGroupId: json['transfer_group_id'],
    );
  }

  // Add a toJson method so you can save it to Supabase
  Map<String, dynamic> toJson() => {
    'amount': amount,
    'description': description,
    'date': date.toUtc().toIso8601String(),
    'type': type,
    'category_id': categoryId,
    'wallet_id': walletId,
    'is_internal_transfer': isInternalTransfer,
    'transfer_group_id': transferGroupId,
  };
}

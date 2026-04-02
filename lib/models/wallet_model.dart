// lib/models/wallet_model.dart

class WalletModel {
  final String id; // Unique identifier (UUID from Supabase)
  final String name; // Wallet or Account name
  final double balance; // Available funds
  final String currency; // Currency symbol (e.g., $, JOD, SAR)

  // Standard Constructor with named parameters
  WalletModel({
    required this.id,
    required this.name,
    required this.balance,
    this.currency = '\$',
  });

  /// Logic: CopyWith Pattern
  /// Creates a new instance of WalletModel with updated fields.
  /// This is essential for immutable state management.
  WalletModel copyWith({
    String? id,
    String? name,
    double? balance,
    String? currency,
  }) {
    return WalletModel(
      id: id ?? this.id,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      currency: currency ?? this.currency,
    );
  }

  /// Factory: Data Transformation (JSON to Object)
  factory WalletModel.fromJson(Map<String, dynamic> json) {
    return WalletModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Account',
      balance: (json['balance'] as num? ?? 0.0).toDouble(),
      currency: json['currency'] as String? ?? '\$',
    );
  }

  /// Transformation: Object to JSON (for Database updates)
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'balance': balance, 'currency': currency};
  }

  /// Logic: Performance/Efficiency Calculation
  double getBalancePercentage(double targetAmount) {
    if (targetAmount <= 0) return 0.0;
    final double ratio = (balance / targetAmount) * 100;
    return double.parse(ratio.toStringAsFixed(2));
  }

  /// UI Utility: Formatted Balance String
  String get formattedBalance => '$currency${balance.toStringAsFixed(2)}';
}

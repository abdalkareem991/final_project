// lib/models/wallet_model.dart

class WalletModel {
  final String id; // Unique identifier (UUID from Supabase)
  final String name; // Wallet or Account name
  final double balance; // Available funds
  final String currency; // Currency symbol (e.g., $, JOD, SAR)
  final String type; // Wallet type (Bank, Cash, Mobile Wallet)
  final String accountMode; // 'MANUAL' or 'AUTOMATED'
  final String? smsSenderId; // e.g., 'ArabBank'
  final bool isActiveMonitoring;

  // Standard Constructor with named parameters
  WalletModel({
    required this.id,
    required this.name,
    required this.balance,
    required this.type,
    this.currency = 'JD',
    this.accountMode = 'MANUAL',
    this.smsSenderId,
    this.isActiveMonitoring = false,
  });

  /// Logic: CopyWith Pattern
  /// Creates a new instance of WalletModel with updated fields.
  /// This is essential for immutable state management.
  WalletModel copyWith({
    String? id,
    String? name,
    double? balance,
    String? currency,
    String? type,
    String? accountMode,
    String? smsSenderId,
    bool? isActiveMonitoring,
  }) {
    return WalletModel(
      id: id ?? this.id,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      accountMode: accountMode ?? this.accountMode,
      smsSenderId: smsSenderId ?? this.smsSenderId,
      isActiveMonitoring: isActiveMonitoring ?? this.isActiveMonitoring,
    );
  }

  /// Factory: Data Transformation (JSON to Object)
  factory WalletModel.fromJson(Map<String, dynamic> json) {
    return WalletModel(
     id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      balance: (json['balance'] as num? ?? 0.0).toDouble(),
      type: json['type'] as String? ?? 'Bank',
      currency: json['currency'] as String? ?? 'JD',
      accountMode: json['account_mode'] as String? ?? 'MANUAL',
      smsSenderId: json['sms_sender_id'],
      isActiveMonitoring: json['is_active_monitoring'] as bool? ?? false,
    );
  }

  /// Transformation: Object to JSON (for Database updates)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'balance': balance,
      'type': type,
      'currency': currency,
      'account_mode': accountMode,
      'sms_sender_id': smsSenderId,
      'is_active_monitoring': isActiveMonitoring,
    };
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

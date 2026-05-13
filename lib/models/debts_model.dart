class DebtModel {
  final String id;
  final String userId;
  final String personName;
  final double amount;
  final String type; // debtor or creditor
  final String? note;
  final DateTime? dueDate;
  final String status; // active, paid, cancelled
  final DateTime createdAt;
  final DateTime? updatedAt;

  const DebtModel({
    required this.id,
    required this.userId,
    required this.personName,
    required this.amount,
    required this.type,
    this.note,
    this.dueDate,
    this.status = 'active',
    required this.createdAt,
    this.updatedAt,
  });

  factory DebtModel.fromJson(Map<String, dynamic> json) {
    return DebtModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      personName: json['person_name']?.toString() ?? '',
      amount: (json['amount'] as num? ?? 0.0).toDouble(),
      type: json['type']?.toString() ?? 'debtor',
      note: json['note']?.toString(),
      dueDate: _parseDate(json['due_date']),
      status: json['status']?.toString() ?? 'active',
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  DebtModel copyWith({
    String? id,
    String? userId,
    String? personName,
    double? amount,
    String? type,
    String? note,
    DateTime? dueDate,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearNote = false,
    bool clearDueDate = false,
  }) {
    return DebtModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      personName: personName ?? this.personName,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      note: clearNote ? null : note ?? this.note,
      dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toInsertJson({required String fallbackUserId}) {
    return {
      'user_id': userId.isNotEmpty ? userId : fallbackUserId,
      'person_name': personName.trim(),
      'amount': amount,
      'type': type,
      'note': _cleanNullableText(note),
      'due_date': _formatDateOnly(dueDate),
      'status': status,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'person_name': personName.trim(),
      'amount': amount,
      'type': type,
      'note': _cleanNullableText(note),
      'due_date': _formatDateOnly(dueDate),
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  bool get isDebtor => type == 'debtor';
  bool get isCreditor => type == 'creditor';
  bool get isActive => status == 'active';

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String? _formatDateOnly(DateTime? value) {
    if (value == null) return null;
    return value.toIso8601String().split('T').first;
  }

  static String? _cleanNullableText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

class DebtSummary {
  final double totalDebtorAmount;
  final double totalCreditorAmount;

  const DebtSummary({
    required this.totalDebtorAmount,
    required this.totalCreditorAmount,
  });

  double get netDebt => totalDebtorAmount - totalCreditorAmount;
}

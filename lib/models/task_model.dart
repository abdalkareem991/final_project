class TaskModel {
  static const String recurrenceNone = 'none';
  static const String recurrenceDaily = 'daily';
  static const String recurrenceMonthly = 'monthly';

  final String id;
  final String title;
  final String description;
  final DateTime dueDate;
  final DateTime endDate;
  final DateTime? occurrenceDate;
  final String priority;
  final bool isCompleted;
  final String userId;
  final String? linkedWalletId;
  final double amount;
  final bool isRecurring;
  final String recurrenceType;
  final bool hasNotification;

  TaskModel({
    required this.id,
    required this.title,
    this.description = '',
    required this.dueDate,
    required this.endDate,
    this.occurrenceDate,
    required this.priority,
    this.isCompleted = false,
    required this.userId,
    this.linkedWalletId,
    this.amount = 0.0,
    bool? isRecurring,
    String? recurrenceType,
    this.hasNotification = false,
  }) : recurrenceType = _normalizeRecurrenceType(
         recurrenceType ?? (isRecurring == true ? recurrenceDaily : null),
       ),
       isRecurring =
           _normalizeRecurrenceType(
             recurrenceType ?? (isRecurring == true ? recurrenceDaily : null),
           ) !=
           recurrenceNone;

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    final legacyIsRecurring = json['is_recurring'] == true;
    final rawRecurrenceType = json['recurrence_type']?.toString().toLowerCase();
    final recurrenceType = _normalizeRecurrenceType(
      rawRecurrenceType ?? (legacyIsRecurring ? recurrenceDaily : null),
    );

    return TaskModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      dueDate: DateTime.parse(json['due_date']),
      endDate: DateTime.parse(json['end_date'] ?? json['due_date']),
      priority: json['priority'] ?? 'Medium',
      isCompleted: json['is_completed'] ?? false,
      userId: json['user_id'] ?? '',
      linkedWalletId: json['linked_wallet_id'],
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      isRecurring: recurrenceType != recurrenceNone,
      recurrenceType: recurrenceType,
      hasNotification: json['has_notification'] ?? false,
    );
  }

  bool get isDailyRecurring => recurrenceType == recurrenceDaily;
  bool get isMonthlyRecurring => recurrenceType == recurrenceMonthly;

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'due_date': dueDate.toIso8601String(),
    'end_date': endDate.toIso8601String(),
    'priority': priority,
    'is_completed': isCompleted,
    'user_id': userId,
    'linked_wallet_id': linkedWalletId,
    'amount': amount,
    'is_recurring': recurrenceType != recurrenceNone,
    'recurrence_type': recurrenceType,
    'has_notification': hasNotification,
  };

  TaskModel copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? dueDate,
    DateTime? endDate,
    DateTime? occurrenceDate,
    String? priority,
    bool? isCompleted,
    String? userId,
    String? linkedWalletId,
    double? amount,
    bool? isRecurring,
    String? recurrenceType,
    bool? hasNotification,
  }) {
    final normalizedRecurrenceType = _normalizeRecurrenceType(
      recurrenceType ?? this.recurrenceType,
    );

    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      endDate: endDate ?? this.endDate,
      occurrenceDate: occurrenceDate ?? this.occurrenceDate,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      userId: userId ?? this.userId,
      linkedWalletId: linkedWalletId ?? this.linkedWalletId,
      amount: amount ?? this.amount,
      isRecurring: isRecurring ?? normalizedRecurrenceType != recurrenceNone,
      recurrenceType: normalizedRecurrenceType,
      hasNotification: hasNotification ?? this.hasNotification,
    );
  }

  static String _normalizeRecurrenceType(String? recurrenceType) {
    switch (recurrenceType) {
      case recurrenceDaily:
      case recurrenceMonthly:
        return recurrenceType!;
      default:
        return recurrenceNone;
    }
  }
}

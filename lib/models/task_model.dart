class TaskModel {
  final String id;
  final String title;
  final String description;
  final DateTime dueDate;
  final DateTime endDate;
  final String priority;
  final bool isCompleted;
  final String userId;
  final String? linkedWalletId;
  final double amount;
  final bool isRecurring; // Added this
  final bool hasNotification;

  TaskModel({
    required this.id,
    required this.title,
    this.description = '',
    required this.dueDate,
    required this.endDate,
    required this.priority,
    this.isCompleted = false,
    required this.userId,
    this.linkedWalletId,
    this.amount = 0.0,
    this.isRecurring = false, // Added this
    this.hasNotification = false,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
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
      isRecurring: json['is_recurring'] ?? false,
      hasNotification: json['has_notification'] ?? false,
    );
  }

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
    'is_recurring': isRecurring,
    'has_notification': hasNotification,
  };
}

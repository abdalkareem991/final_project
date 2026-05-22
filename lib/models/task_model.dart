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
  final DateTime? reminderTime;
  final int? notificationId;

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
    bool? hasNotification,
    bool? reminderEnabled,
    this.reminderTime,
    this.notificationId,
  }) : recurrenceType = _normalizeRecurrenceType(
         recurrenceType ?? (isRecurring == true ? recurrenceDaily : null),
       ),
       hasNotification = hasNotification ?? reminderEnabled ?? false,
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
    final dueDate = _applyTimeString(
      DateTime.parse(json['due_date']),
      json['due_time']?.toString(),
    );
    final reminderEnabled =
        json['reminder_enabled'] == true || json['has_notification'] == true;
    final reminderTime =
        _parseOptionalDateTime(json['reminder_time']) ??
        (reminderEnabled ? dueDate : null);

    return TaskModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      dueDate: dueDate,
      endDate: DateTime.parse(json['end_date'] ?? json['due_date']),
      priority: json['priority'] ?? 'Medium',
      isCompleted: json['is_completed'] ?? false,
      userId: json['user_id'] ?? '',
      linkedWalletId: json['linked_wallet_id'],
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      isRecurring: recurrenceType != recurrenceNone,
      recurrenceType: recurrenceType,
      hasNotification: reminderEnabled,
      reminderTime: reminderTime,
      notificationId: (json['notification_id'] as num?)?.toInt(),
    );
  }

  bool get isDailyRecurring => recurrenceType == recurrenceDaily;
  bool get isMonthlyRecurring => recurrenceType == recurrenceMonthly;
  bool get reminderEnabled => hasNotification;
  DateTime? get effectiveReminderTime => reminderTime;

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'due_date': dueDate.toIso8601String(),
    'due_time': _formatTime(reminderTime ?? dueDate),
    'end_date': endDate.toIso8601String(),
    'priority': priority,
    'is_completed': isCompleted,
    'user_id': userId,
    'linked_wallet_id': linkedWalletId,
    'amount': amount,
    'is_recurring': recurrenceType != recurrenceNone,
    'recurrence_type': recurrenceType,
    'has_notification': hasNotification,
    'reminder_enabled': hasNotification,
    'reminder_time': hasNotification ? reminderTime?.toIso8601String() : null,
    'notification_id': notificationId,
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
    bool? reminderEnabled,
    DateTime? reminderTime,
    int? notificationId,
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
      hasNotification:
          hasNotification ?? reminderEnabled ?? this.hasNotification,
      reminderTime: reminderTime ?? this.reminderTime,
      notificationId: notificationId ?? this.notificationId,
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

  static DateTime? _parseOptionalDateTime(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  static DateTime _applyTimeString(DateTime date, String? timeText) {
    if (timeText == null || timeText.trim().isEmpty) return date;

    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(timeText.trim());
    if (match == null) return date;

    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return date;
    }

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

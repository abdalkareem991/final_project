// lib/services/notification_service.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

const String _notificationLogTag = 'FinMindNotifications';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  try {
    debugPrint(
      "[$_notificationLogTag] Notification tapped while app was in the background.",
    );
    final payload = response.payload;
    if (payload == null || payload.trim().isEmpty) {
      debugPrint("[$_notificationLogTag] Background payload is empty.");
      return;
    }
    final decoded = jsonDecode(payload);
    debugPrint(
      "[$_notificationLogTag] Background payload decoded: ${decoded is Map ? decoded['type'] : 'invalid'}",
    );
  } catch (e, stackTrace) {
    debugPrint(
      "[$_notificationLogTag] Background notification tap handling failed: $e\n$stackTrace",
    );
  }
}

class AppNotificationItem {
  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime createdAt;
  final bool isRead;

  AppNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.isRead = false,
  });

  AppNotificationItem copyWith({bool? isRead}) {
    return AppNotificationItem(
      id: id,
      title: title,
      body: body,
      type: type,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
    );
  }
}

class _NotificationPayload {
  final String? type;
  final String? taskId;
  final String route;

  const _NotificationPayload({this.type, this.taskId, this.route = '/todo'});
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final ValueNotifier<List<AppNotificationItem>> recentNotifications =
      ValueNotifier<List<AppNotificationItem>>([]);

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const int _maxRecentNotifications = 20;
  static const String _localTimeZoneName = 'Asia/Amman';
  static const String _generalChannelId = 'finmind_general_channel';
  static const String _tasksChannelId = 'finmind_tasks_channel';
  static const String _todoRoute = '/todo';
  bool _timeZonesReady = false;
  bool _isInitialized = false;
  bool _channelsReady = false;
  bool _didCheckLaunchDetails = false;
  String? _pendingNavigationPayload;
  String? _lastReminderScheduleFailure;

  static const String notificationPermissionRequiredMessage =
      'Notification permission is required for reminders.';

  String? get lastReminderScheduleFailure => _lastReminderScheduleFailure;

  static int taskReminderId(String taskId) {
    var hash = 0;
    for (final codeUnit in taskId.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static String taskReminderPayload(String taskId) {
    return jsonEncode({
      'type': 'task_reminder',
      'task_id': taskId,
      'route': _todoRoute,
    });
  }

  Future<bool> get isNotificationEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notifications_enabled') ?? true;
  }

  Future<void> initNotification({bool requestPermissions = true}) async {
    _ensureTimeZonesInitialized();
    debugPrint("[$_notificationLogTag] Notification initialization started.");

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    if (!_isInitialized) {
      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );
      _isInitialized = true;
    }

    final androidImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (!_channelsReady) {
      await androidImplementation?.createNotificationChannel(
        const AndroidNotificationChannel(
          _generalChannelId,
          'FinMind Notifications',
          description: 'General FinMind app notifications',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

      await androidImplementation?.createNotificationChannel(
        const AndroidNotificationChannel(
          _tasksChannelId,
          'Task Reminders',
          description: 'Financial task reminders',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      _channelsReady = true;
    }

    if (requestPermissions) {
      final notificationPermission = await androidImplementation
          ?.requestNotificationsPermission();
      debugPrint(
        "[$_notificationLogTag] Notification permission status: ${notificationPermission ?? 'not_applicable'}",
      );

      final canScheduleExact =
          await androidImplementation?.canScheduleExactNotifications() ?? true;
      debugPrint(
        "[$_notificationLogTag] Exact alarm permission status: $canScheduleExact",
      );
      if (!canScheduleExact) {
        await androidImplementation?.requestExactAlarmsPermission();
        debugPrint("[$_notificationLogTag] Exact alarm permission requested.");
      }
    }

    if (!_didCheckLaunchDetails) {
      _didCheckLaunchDetails = true;
      final launchDetails = await flutterLocalNotificationsPlugin
          .getNotificationAppLaunchDetails();
      final response = launchDetails?.notificationResponse;
      if (launchDetails?.didNotificationLaunchApp == true &&
          response?.payload != null) {
        _pendingNavigationPayload = response!.payload;
        debugPrint(
          "[$_notificationLogTag] Notification launch payload captured.",
        );
      }
    }

    debugPrint("[$_notificationLogTag] Notification initialization completed.");
  }

  void handlePendingNotificationNavigation() {
    final payload = _pendingNavigationPayload;
    if (payload == null) return;

    _pendingNavigationPayload = null;
    try {
      _navigateForPayload(payload);
    } catch (e, stackTrace) {
      debugPrint(
        "[$_notificationLogTag] Pending notification navigation failed: $e\n$stackTrace",
      );
      _navigateToTodoList();
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    try {
      debugPrint(
        "[$_notificationLogTag] Notification tapped: ${_safePayloadLabel(response.payload)}",
      );
      _navigateForPayload(response.payload);
    } catch (e, stackTrace) {
      debugPrint(
        "[$_notificationLogTag] Notification tap handling failed: $e\n$stackTrace",
      );
      _navigateToTodoList();
    }
  }

  String _safePayloadLabel(String? payload) {
    if (payload == null || payload.isEmpty) return 'empty';
    final decoded = _decodePayload(payload);
    return decoded.type ?? 'invalid';
  }

  void _navigateForPayload(String? payload) {
    final decoded = _decodePayload(payload);
    debugPrint(
      "[$_notificationLogTag] Payload decoded: type=${decoded.type ?? 'invalid'}, route=${decoded.route}",
    );

    if (decoded.route != _todoRoute && decoded.type != 'task_reminder') {
      _navigateToTodoList();
      return;
    }

    _navigateToTodoList(payload: payload);
  }

  void _navigateToTodoList({String? payload}) {
    try {
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        _pendingNavigationPayload = payload ?? taskReminderPayload('');
        debugPrint(
          "[$_notificationLogTag] Navigation deferred until navigator is ready.",
        );
        return;
      }

      debugPrint("[$_notificationLogTag] Navigation to Todo List.");
      navigator.pushNamed(_todoRoute, arguments: payload);
    } catch (e, stackTrace) {
      debugPrint(
        "[$_notificationLogTag] Navigation to Todo List failed: $e\n$stackTrace",
      );
    }
  }

  _NotificationPayload _decodePayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) {
      return const _NotificationPayload(route: _todoRoute);
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return _NotificationPayload(
          type: decoded['type']?.toString(),
          taskId: decoded['task_id']?.toString(),
          route: decoded['route']?.toString() ?? _todoRoute,
        );
      }
    } catch (e) {
      debugPrint("[$_notificationLogTag] Payload decode failed: $e");
    }

    if (payload.startsWith('todo')) {
      final parts = payload.split(':');
      return _NotificationPayload(
        type: 'task_reminder',
        taskId: parts.length > 1 ? parts[1] : null,
        route: _todoRoute,
      );
    }

    return const _NotificationPayload(route: _todoRoute);
  }

  void _ensureTimeZonesInitialized() {
    if (_timeZonesReady) return;

    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(_localTimeZoneName));
    } catch (e) {
      debugPrint(
        "[$_notificationLogTag] Could not load $_localTimeZoneName timezone; using tz.local fallback: $e",
      );
    }
    _timeZonesReady = true;
    debugPrint("[$_notificationLogTag] Timezone initialized: ${tz.local.name}");
  }

  int _generateNotificationId() {
    return DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
  }

  void _addToNotificationCenter({
    required String title,
    required String body,
    required String type,
  }) {
    final item = AppNotificationItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      body: body,
      type: type,
      createdAt: DateTime.now(),
      isRead: false,
    );

    final updatedList = [
      item,
      ...recentNotifications.value,
    ].take(_maxRecentNotifications).toList();

    recentNotifications.value = updatedList;
    unreadCount.value = updatedList.where((item) => !item.isRead).length;
  }

  void markAllAsRead() {
    final updatedList = recentNotifications.value
        .map((item) => item.copyWith(isRead: true))
        .toList();

    recentNotifications.value = updatedList;
    unreadCount.value = 0;
  }

  void clearNotificationCenter() {
    recentNotifications.value = [];
    unreadCount.value = 0;
  }

  Future<void> cancelNotification(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
      debugPrint("Notification with ID $id cancelled.");
    } catch (e) {
      debugPrint("Cancel notification failed for $id: $e");
    }
  }

  Future<void> cancelTaskReminder(String taskId) async {
    await cancelNotification(taskReminderId(taskId));
    await cancelNotification(taskId.hashCode);
    debugPrint(
      "[$_notificationLogTag] Task reminder cancelled: ${taskReminderId(taskId)}",
    );
  }

  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
    debugPrint("All notifications cancelled.");
  }

  Future<void> showInstantNotification(
    String title,
    String body, {
    String type = 'general',
    String? payload,
  }) async {
    _addToNotificationCenter(title: title, body: body, type: type);

    final isEnabled = await isNotificationEnabled;
    if (!isEnabled) return;

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _generalChannelId,
          'FinMind Notifications',
          channelDescription: 'General FinMind app notifications',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
          styleInformation: BigTextStyleInformation(body),
        );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
      ),
    );

    try {
      await flutterLocalNotificationsPlugin.show(
        _generateNotificationId(),
        title,
        body,
        platformDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint("Show notification failed: $e");
    }
  }

  Future<void> showTransactionNotification({
    required String type,
    required double amount,
    required String walletName,
    String? description,
    double? balanceAfter,
  }) async {
    final bool isIncome = type.toLowerCase() == 'income';

    final String title = isIncome
        ? "Income transaction recorded"
        : "Expense transaction recorded";

    final String amountText = "JOD ${amount.toStringAsFixed(3)}";

    final String body = balanceAfter == null
        ? "$walletName • $amountText"
        : "$walletName • $amountText • Balance: ${balanceAfter.toStringAsFixed(3)} JD";

    await showInstantNotification(
      title,
      description == null || description.isEmpty ? body : "$description\n$body",
      type: 'transaction',
    );
  }

  Future<void> showInternalTransferNotification({
    required String fromWallet,
    required String toWallet,
    required double amount,
  }) async {
    await showInstantNotification(
      "Transfer recorded successfully",
      "$fromWallet → $toWallet\nJOD ${amount.toStringAsFixed(3)} • Category: Transfer • Balance updated",
      type: 'transfer',
    );
  }

  Future<void> showSyncErrorNotification(String message) async {
    await showInstantNotification("SMS sync issue", message, type: 'error');
  }

  Future<void> showTaskReminderNotification({
    required String title,
    required String body,
    String? taskId,
  }) async {
    await showInstantNotification(
      title,
      body,
      type: 'task',
      payload: taskReminderPayload(taskId ?? ''),
    );
  }

  Future<bool> scheduleNotification(
    int id,
    String title,
    String body,
    DateTime scheduledDate,
  ) {
    return scheduleTaskReminder(
      id: id,
      title: title,
      body: body,
      firstDateTime: scheduledDate,
    );
  }

  Future<bool> scheduleTaskReminder({
    required int id,
    required String title,
    required String body,
    required DateTime firstDateTime,
    String recurrenceType = 'none',
    String? payload,
  }) async {
    _lastReminderScheduleFailure = null;
    await initNotification(requestPermissions: false);
    _ensureTimeZonesInitialized();

    final internalAppNotificationsEnabled = await isNotificationEnabled;
    final normalizedRecurrenceType = recurrenceType.toLowerCase();

    debugPrint(
      "[$_notificationLogTag] Internal app notification setting: $internalAppNotificationsEnabled (ignored for task reminders).",
    );
    debugPrint("[$_notificationLogTag] firstDateTime: $firstDateTime");
    debugPrint(
      "[$_notificationLogTag] Recurrence type: $normalizedRecurrenceType",
    );
    debugPrint(
      "[$_notificationLogTag] Current DateTime.now(): ${DateTime.now()}",
    );

    final hasNotificationPermission = await _ensureNotificationPermission();
    if (!hasNotificationPermission) {
      _lastReminderScheduleFailure = notificationPermissionRequiredMessage;
      debugPrint(
        "[$_notificationLogTag] Notification permission denied; reminder not scheduled.",
      );
      return false;
    }

    final nextDateTime = _nextReminderDateTime(
      firstDateTime,
      normalizedRecurrenceType,
    );
    debugPrint("[$_notificationLogTag] nextDateTime: $nextDateTime");

    if (nextDateTime == null) {
      _lastReminderScheduleFailure = 'Selected reminder time is in the past.';
      debugPrint(
        "Notification not scheduled because selected time is in the past.",
      );
      return false;
    }

    final scheduledTzDate = tz.TZDateTime.from(nextDateTime, tz.local);
    final matchComponents = switch (normalizedRecurrenceType) {
      'daily' => DateTimeComponents.time,
      'monthly' => DateTimeComponents.dayOfMonthAndTime,
      _ => null,
    };

    debugPrint(
      "[$_notificationLogTag] Notification scheduled TZ time: $scheduledTzDate",
    );

    final scheduleMode = await _bestAndroidScheduleMode();
    debugPrint("[$_notificationLogTag] Schedule mode: $scheduleMode");

    try {
      await _scheduleZonedTaskReminder(
        id,
        title,
        body,
        scheduledTzDate,
        androidScheduleMode: scheduleMode,
        matchComponents: matchComponents,
        payload: payload,
      );

      debugPrint(
        "[$_notificationLogTag] Task reminder scheduled: id=$id mode=$scheduleMode.",
      );
      return true;
    } on PlatformException catch (e, stackTrace) {
      if (scheduleMode != AndroidScheduleMode.inexactAllowWhileIdle) {
        debugPrint(
          "[$_notificationLogTag] Exact task notification failed, retrying with inexact alarm: $e\n$stackTrace",
        );

        try {
          await _scheduleZonedTaskReminder(
            id,
            title,
            body,
            scheduledTzDate,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchComponents: matchComponents,
            payload: payload,
          );
          debugPrint(
            "[$_notificationLogTag] Task notification scheduled with inexact fallback.",
          );
          return true;
        } catch (retryError, retryStackTrace) {
          _lastReminderScheduleFailure =
              'Exact scheduling failed: ${e.message ?? e.toString()}; inexact retry failed: $retryError';
          debugPrint(
            "[$_notificationLogTag] Inexact task notification schedule failed: $retryError\n$retryStackTrace",
          );
          return false;
        }
      }

      _lastReminderScheduleFailure = e.message ?? e.toString();
      debugPrint(
        "[$_notificationLogTag] Task notification schedule failed: $e\n$stackTrace",
      );
      return false;
    } catch (e, stackTrace) {
      _lastReminderScheduleFailure = e.toString();
      debugPrint(
        "[$_notificationLogTag] Task notification schedule failed: $e\n$stackTrace",
      );
      return false;
    }
  }

  Future<bool> _ensureNotificationPermission() async {
    final androidImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImplementation == null) return true;

    try {
      final currentlyEnabled =
          await androidImplementation.areNotificationsEnabled() ?? true;
      debugPrint(
        "[$_notificationLogTag] Notification permission status before scheduling: $currentlyEnabled",
      );
      if (currentlyEnabled) return true;

      final requested =
          await androidImplementation.requestNotificationsPermission() ?? false;
      debugPrint(
        "[$_notificationLogTag] Notification permission request result: $requested",
      );
      return requested;
    } catch (e, stackTrace) {
      debugPrint(
        "[$_notificationLogTag] Notification permission check failed: $e\n$stackTrace",
      );
      return true;
    }
  }

  Future<AndroidScheduleMode> _bestAndroidScheduleMode() async {
    final androidImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    try {
      final canScheduleExact = await androidImplementation
          ?.canScheduleExactNotifications();
      debugPrint(
        "[$_notificationLogTag] Exact alarm permission status before scheduling: ${canScheduleExact ?? 'not_applicable'}",
      );
      if (canScheduleExact == false) {
        final requested = await androidImplementation
            ?.requestExactAlarmsPermission();
        debugPrint(
          "[$_notificationLogTag] Exact alarm permission request result: ${requested ?? 'not_applicable'}",
        );
        if (requested == true) {
          return AndroidScheduleMode.exactAllowWhileIdle;
        }
        return AndroidScheduleMode.inexactAllowWhileIdle;
      }
    } catch (e) {
      debugPrint(
        "[$_notificationLogTag] Could not check exact alarm availability: $e",
      );
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }

    return AndroidScheduleMode.exactAllowWhileIdle;
  }

  Future<void> _scheduleZonedTaskReminder(
    int id,
    String title,
    String body,
    tz.TZDateTime scheduledDate, {
    required AndroidScheduleMode androidScheduleMode,
    DateTimeComponents? matchComponents,
    String? payload,
  }) {
    return flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _tasksChannelId,
          'Task Reminders',
          channelDescription: 'Financial task reminders',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        ),
      ),
      androidScheduleMode: androidScheduleMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchComponents,
      payload: payload,
    );
  }

  DateTime? _nextReminderDateTime(
    DateTime firstDateTime,
    String recurrenceType,
  ) {
    final now = DateTime.now();

    if (firstDateTime.isAfter(now)) {
      return firstDateTime;
    }

    if (recurrenceType == 'daily') {
      var next = DateTime(
        now.year,
        now.month,
        now.day,
        firstDateTime.hour,
        firstDateTime.minute,
      );
      if (!next.isAfter(now)) {
        next = next.add(const Duration(days: 1));
      }
      return next;
    }

    if (recurrenceType == 'monthly') {
      return _nextMonthlyDateTime(firstDateTime, now);
    }

    return null;
  }

  DateTime _nextMonthlyDateTime(DateTime firstDateTime, DateTime now) {
    var year = now.year;
    var month = now.month;

    for (var i = 0; i < 24; i++) {
      final lastDay = DateTime(year, month + 1, 0).day;
      if (firstDateTime.day <= lastDay) {
        final candidate = DateTime(
          year,
          month,
          firstDateTime.day,
          firstDateTime.hour,
          firstDateTime.minute,
        );

        if (candidate.isAfter(now)) {
          return candidate;
        }
      }

      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
    }

    return now.add(const Duration(days: 1));
  }
}

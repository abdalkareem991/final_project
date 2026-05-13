// lib/services/notification_service.dart

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final ValueNotifier<List<AppNotificationItem>> recentNotifications =
      ValueNotifier<List<AppNotificationItem>>([]);

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static const int _maxRecentNotifications = 20;

  Future<bool> get isNotificationEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notifications_enabled') ?? true;
  }

  Future<void> initNotification() async {
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

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    final androidImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Amman'));
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
    await flutterLocalNotificationsPlugin.cancel(id);
    debugPrint("Notification with ID $id cancelled.");
  }

  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
    debugPrint("All notifications cancelled.");
  }

  Future<void> showInstantNotification(
    String title,
    String body, {
    String type = 'general',
  }) async {
    _addToNotificationCenter(title: title, body: body, type: type);

    final isEnabled = await isNotificationEnabled;
    if (!isEnabled) return;

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'finmind_general_channel',
          'FinMind Notifications',
          channelDescription: 'General FinMind app notifications',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          styleInformation: BigTextStyleInformation(body),
        );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      _generateNotificationId(),
      title,
      body,
      platformDetails,
    );
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
  }) async {
    await showInstantNotification(title, body, type: 'task');
  }

  Future<void> scheduleNotification(
    int id,
    String title,
    String body,
    DateTime scheduledDate,
  ) async {
    final isEnabled = await isNotificationEnabled;

    debugPrint("Notifications enabled: $isEnabled");
    debugPrint("Requested schedule time: $scheduledDate");
    debugPrint("Current time: ${DateTime.now()}");

    if (!isEnabled) {
      debugPrint(
        "Notification not scheduled because notifications are disabled.",
      );
      return;
    }

    if (!scheduledDate.isAfter(DateTime.now())) {
      debugPrint(
        "Notification not scheduled because selected time is in the past.",
      );
      return;
    }

    final scheduledTzDate = tz.TZDateTime.from(scheduledDate, tz.local);

    debugPrint("Notification scheduled TZ time: $scheduledTzDate");

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledTzDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'finmind_tasks_channel',
          'Task Reminders',
          channelDescription: 'Financial task reminders',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    debugPrint("Task notification scheduled successfully.");
  }
}

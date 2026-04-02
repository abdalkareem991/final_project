import 'package:easy_date_timeline/easy_date_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class TodoListScreen extends StatefulWidget {
  const TodoListScreen({super.key});

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  DateTime _selectedDate = DateTime.now();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Theme Constants
  static const Color _bgColor = Color(0xFF061414);
  static const Color _cardColor = Color(0xFF111D1D);
  static const Color _accentGreen = Color(0xFF34EAB9);

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  // --- Notification Logic ---
  Future<void> _initNotifications() async {
    tz_data.initializeTimeZones();
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );
    await _notificationsPlugin.initialize(settings);
  }

  Future<void> _scheduleNotification(
    String title,
    DateTime scheduledTime,
  ) async {
    await _notificationsPlugin.zonedSchedule(
      0,
      'Task Reminder',
      title,
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_channel',
          'Task Reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          "My Tasks",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // 1. Horizontal Timeline Calendar (Similar to your image)
          _buildHorizontalCalendar(),

          const SizedBox(height: 20),

          // 2. Tasks List Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Today's Schedule",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text(
                    "View All",
                    style: TextStyle(color: _accentGreen),
                  ),
                ),
              ],
            ),
          ),

          // 3. Dynamic Tasks List
          Expanded(child: _buildTasksList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _accentGreen,
        onPressed: _showAddTaskSheet,
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }

  Widget _buildHorizontalCalendar() {
    return EasyDateTimeLine(
      initialDate: DateTime.now(),
      onDateChange: (selectedDate) {
        setState(() => _selectedDate = selectedDate);
      },
      headerProps: const EasyHeaderProps(
        monthPickerType: MonthPickerType.switcher,
      ),
      dayProps: const EasyDayProps(
        dayStructure: DayStructure.dayStrDayNum,
        activeDayStyle: DayStyle(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_accentGreen, Color(0xFF1D9778)],
            ),
          ),
        ),
        inactiveDayStyle: DayStyle(
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          dayNumStyle: TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }

  Widget _buildTasksList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 4,
      itemBuilder: (context, index) => _buildTaskItem(
        "Financial Review",
        "10:30 AM",
        index == 0, // First one active
      ),
    );
  }

  Widget _buildTaskItem(String title, String time, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        // ignore: deprecated_member_use
        border: isActive
            ? Border.all(color: _accentGreen.withOpacity(0.5))
            : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive ? _accentGreen : Colors.white10,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check,
              color: isActive ? Colors.black : Colors.white24,
              size: 18,
            ),
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                time,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
          const Spacer(),
          const Icon(
            Icons.notifications_active_outlined,
            color: Colors.grey,
            size: 20,
          ),
        ],
      ),
    );
  }

  void _showAddTaskSheet() {
    // Logic to show BottomSheet, Save to Supabase, and call _scheduleNotification
    // Example: _scheduleNotification('Task Title', DateTime.now().add(const Duration(hours: 1)));
  }
}

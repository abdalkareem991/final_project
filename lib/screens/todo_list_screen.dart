// lib/screens/todo_list_screen.dart

import 'package:easy_date_timeline/easy_date_timeline.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_text.dart';
import '../core/app_theme.dart';
import '../models/task_model.dart';
import '../models/wallet_model.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';

class TodoListScreen extends StatefulWidget {
  const TodoListScreen({super.key});

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  final _supabaseService = SupabaseService();

  // Normalize date to midnight to avoid time-matching bugs in DB queries
  late DateTime _selectedDate;
  String _filterStatus = "All";

  // Data storage
  late Future<List<TaskModel>> _tasksFuture;

  // Specific Stats Maps
  Map<String, int> _dailyTaskStats = {'total': 0, 'completed': 0, 'pending': 0};
  Map<String, int> _monthlyTaskStats = {
    'total': 0,
    'completed': 0,
    'pending': 0,
  };
  Map<DateTime, int> _tasksCountMap = {};

  // Multi-Selection Logic
  bool _isDeleteMode = false;
  final List<String> _selectedTaskIds = [];

  // Theme constants
  AppThemeColors get _colors => context.themeColors;
  Color get _bgColor => _colors.background;
  Color get _cardColor => _colors.surface;
  Color get _accentGreen => _colors.primary;
  Color get _accentBlue => _colors.transfer;
  Color get _accentRed => _colors.expense;
  Color get _textColor => _colors.textPrimary;
  Color get _secondaryTextColor => _colors.textSecondary;
  Color get _mutedTextColor => _colors.textMuted;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _refresh();
  }

  // CORE FUNCTION: Fetches all dynamic data cleanly and specifically
  Future<void> _loadAllData() async {
    try {
      // 1. Get stats specifically for the selected DAY (For the Cards)
      final dailyStats = await _supabaseService.getDailyTaskStats(
        _selectedDate,
      );

      // 2. Get stats specifically for the selected MONTH (For the Progress Bar)
      final monthlyStats = await _supabaseService.getMonthlyTaskStats(
        _selectedDate,
      );

      // 3. Get calendar bubble indicators
      final counts = await _supabaseService.getTasksCountForMonth(
        _selectedDate,
      );

      if (mounted) {
        setState(() {
          _dailyTaskStats = dailyStats;
          _monthlyTaskStats = monthlyStats;
          _tasksCountMap = counts;
        });
      }
    } catch (e) {
      debugPrint("Error loading dashboard data: $e");
    }
  }

  // Refresh UI and fetch new tasks for the selected date
  void _refresh() {
    setState(() {
      _tasksFuture = _supabaseService.getTasks(_selectedDate);
    });
    _loadAllData();
  }

  // FUNCTION: Executes bulk delete and cleans up notifications
  Future<void> _handleBulkDelete() async {
    if (_selectedTaskIds.isEmpty) return;

    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "Confirm Delete",
          style: TextStyle(color: _textColor, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Are you sure you want to delete ${_selectedTaskIds.length} tasks?",
          style: TextStyle(color: _secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("Cancel", style: TextStyle(color: _mutedTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              "Delete",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        for (String id in _selectedTaskIds) {
          await _supabaseService.deleteTask(id);
        }
        if (!mounted) return;
        setState(() {
          _selectedTaskIds.clear();
          _isDeleteMode = false;
        });
        _refresh();
      } catch (e) {
        debugPrint("Bulk delete error: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        centerTitle: false,
        title: Text(
          _isDeleteMode
              ? context.t(
                  "${_selectedTaskIds.length} Selected",
                  "تم تحديد ${_selectedTaskIds.length}",
                )
              : context.t("My Agenda", "مهامي"),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _textColor,
            fontSize: 24,
            letterSpacing: 0.5,
          ),
        ),
        leading: _isDeleteMode
            ? IconButton(
                icon: Icon(Icons.close, color: _textColor),
                onPressed: () => setState(() {
                  _isDeleteMode = false;
                  _selectedTaskIds.clear();
                }),
              )
            : null,
        actions: [
          IconButton(
            icon: Icon(
              _isDeleteMode
                  ? Icons.delete_forever
                  : Icons.delete_sweep_outlined,
              color: _isDeleteMode ? _accentRed : _textColor,
            ),
            onPressed: () => setState(() {
              _isDeleteMode = !_isDeleteMode;
              _selectedTaskIds.clear();
            }),
          ),
          if (!_isDeleteMode)
            IconButton(
              icon: Icon(Icons.sync, color: _textColor),
              onPressed: _refresh,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildMonthlyProgress(), // Tied specifically to the selected month
          _buildStatsSummary(), // Tied specifically to the selected day
          const SizedBox(height: 10),
          _buildCalendarTimeline(),
          _buildFilterChips(),
          Expanded(child: _buildTasksList()),
        ],
      ),
      bottomNavigationBar: _isDeleteMode && _selectedTaskIds.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(20),
              color: _accentRed,
              child: InkWell(
                onTap: _handleBulkDelete,
                child: Text(
                  "CONFIRM BATCH DELETE",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1,
                  ),
                ),
              ),
            )
          : null,
      floatingActionButton: _isDeleteMode
          ? null
          : FloatingActionButton(
              backgroundColor: _accentGreen,
              elevation: 8,
              onPressed: () => _showAddTaskModal(context),
              child: Icon(Icons.add, color: _colors.onPrimary, size: 32),
            ),
    );
  }

  /// UI: Monthly Progress Bar (Accurate visual feedback for the month)
  Widget _buildMonthlyProgress() {
    int total = _monthlyTaskStats['total'] ?? 0;
    int completed = _monthlyTaskStats['completed'] ?? 0;
    double progress = total > 0 ? (completed / total) : 0.0;

    // Get the dynamic name of the selected month
    String monthName = DateFormat.MMMM().format(_selectedDate);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "$monthName Progress",
                style: TextStyle(
                  color: _secondaryTextColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                "${(progress * 100).toInt()}%",
                style: TextStyle(
                  color: _accentGreen,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: _colors.subtleBorder.withValues(alpha: 0.6),
              valueColor: AlwaysStoppedAnimation<Color>(_accentGreen),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  /// UI: Daily Stats Summary (Cards accurately reflect the chosen day)
  Widget _buildStatsSummary() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _statItem(
            "Pending",
            "${_dailyTaskStats['pending']}",
            const Color(0xFFF59E0B),
            Icons.pending_actions,
          ),
          _statItem(
            "Done",
            "${_dailyTaskStats['completed']}",
            _accentGreen,
            Icons.check_circle_outline,
          ),
          _statItem(
            "Total",
            "${_dailyTaskStats['total']}",
            _accentBlue,
            Icons.list_alt,
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color, IconData icon) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.28,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _colors.subtleBorder.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: _mutedTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarTimeline() {
    return EasyDateTimeLine(
      initialDate: _selectedDate,
      onDateChange: (date) {
        setState(() => _selectedDate = date);
        _refresh();
      },
      headerProps: EasyHeaderProps(
        monthPickerType: MonthPickerType.switcher,
        dateFormatter: DateFormatter.monthOnly(),
        monthStyle: TextStyle(
          color: _textColor,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      dayProps: const EasyDayProps(
        dayStructure: DayStructure.dayStrDayNum,
        height: 85,
        width: 85,
      ),
      itemBuilder: (context, date, isSelected, onTap) {
        DateTime normalized = DateTime(date.year, date.month, date.day);
        int count = _tasksCountMap[normalized] ?? 0;

        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected ? _accentGreen : _cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? _accentGreen : _colors.subtleBorder,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat.E().format(date),
                  style: TextStyle(
                    color: isSelected ? _colors.onPrimary : _mutedTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  date.day.toString(),
                  style: TextStyle(
                    color: isSelected ? _colors.onPrimary : _textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _colors.onPrimary.withValues(alpha: 0.18)
                          : _accentGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "$count",
                      style: TextStyle(
                        color: isSelected ? _colors.onPrimary : _accentGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: ["All", "Pending", "Completed"].map((status) {
          final isSelected = _filterStatus == status;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Center(child: Text(context.enumText(status))),
                selected: isSelected,
                onSelected: (val) {
                  setState(() => _filterStatus = status);
                },
                selectedColor: _accentGreen,
                backgroundColor: _cardColor,
                labelStyle: TextStyle(
                  color: isSelected ? _colors.onPrimary : _secondaryTextColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                showCheckmark: false,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTasksList() {
    return FutureBuilder<List<TaskModel>>(
      future: _tasksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: _accentGreen));
        }

        if (snapshot.hasError) {
          return _buildErrorState();
        }

        var tasks = snapshot.data ?? [];

        // Filter logic
        if (_filterStatus == "Pending") {
          tasks = tasks.where((t) => !t.isCompleted).toList();
        }
        if (_filterStatus == "Completed") {
          tasks = tasks.where((t) => t.isCompleted).toList();
        }

        // Sort logic: High > Medium > Low
        tasks.sort((a, b) {
          int weightA = _getPriorityWeight(a.priority);
          int weightB = _getPriorityWeight(b.priority);
          return weightB.compareTo(weightA);
        });

        // Use AnimatedSwitcher for smooth transitions
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: tasks.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  key: ValueKey<int>(tasks.length),
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: 80,
                  ),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) => _buildTaskCard(tasks[index]),
                ),
        );
      },
    );
  }

  /// UI: Beautiful Empty State
  Widget _buildEmptyState() {
    return Center(
      key: const ValueKey('empty'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.task_alt,
            size: 80,
            color: _colors.subtleBorder.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 20),
          Text(
            _filterStatus == "Completed"
                ? context.t("No completed tasks yet", "لا توجد مهام مكتملة بعد")
                : context.t("You're all caught up!", "كل شيء منجز!"),
            style: TextStyle(
              color: _textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.t(
              "Tap the + button to add a new task.",
              "اضغط زر + لإضافة مهمة جديدة.",
            ),
            style: TextStyle(color: _mutedTextColor, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      key: const ValueKey('error'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 72,
              color: _accentRed.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 18),
            Text(
              "Could not load tasks",
              style: TextStyle(
                color: _textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Pull the latest data again in a moment.",
              textAlign: TextAlign.center,
              style: TextStyle(color: _mutedTextColor, fontSize: 14),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text("Retry"),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accentGreen,
                side: BorderSide(color: _accentGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(TaskModel task) {
    bool isSelectedForDelete = _selectedTaskIds.contains(task.id);

    // The actual card content
    Widget cardContent = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: isSelectedForDelete
            ? Border.all(color: _accentRed, width: 2)
            : Border.all(color: _colors.subtleBorder),
        boxShadow: [
          BoxShadow(
            color: _colors.subtleBorder.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_isDeleteMode)
            Checkbox(
              value: isSelectedForDelete,
              activeColor: _accentRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedTaskIds.add(task.id);
                  } else {
                    _selectedTaskIds.remove(task.id);
                  }
                });
              },
            )
          else
            GestureDetector(
              onTap: () async {
                await _supabaseService.toggleTaskStatus(
                  task.id,
                  task.isCompleted,
                );
                _refresh();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: task.isCompleted ? _accentGreen : Colors.transparent,
                  border: Border.all(
                    color: task.isCompleted ? _accentGreen : _mutedTextColor,
                    width: 2,
                  ),
                ),
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.check,
                  size: 16,
                  color: task.isCompleted
                      ? _colors.onPrimary
                      : Colors.transparent,
                ),
              ),
            ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    color: task.isCompleted ? _mutedTextColor : _textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildTaskMetaPill(
                      icon: Icons.calendar_today,
                      label: DateFormat.MMMd().format(_displayDate(task)),
                      color: _mutedTextColor,
                    ),
                    _buildTaskMetaPill(
                      icon: Icons.flag,
                      label: task.priority,
                      color: _getPriorityColor(task.priority),
                    ),
                    if (task.isRecurring)
                      _buildTaskMetaPill(
                        icon: _getRecurrenceIcon(task.recurrenceType),
                        label: _getRecurrenceLabel(task.recurrenceType),
                        color: _accentGreen,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (!_isDeleteMode)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (task.linkedWalletId != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _accentGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          "\$${task.amount.toStringAsFixed(0)}",
                          style: TextStyle(
                            color: _accentGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.account_balance_wallet,
                          color: _accentGreen,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _showEditTaskModal(context, task),
                      child: Icon(
                        Icons.edit_note,
                        color: _accentBlue,
                        size: 22,
                      ),
                    ),

                    const SizedBox(width: 15),
                    // Visual Notification Badge
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: task.hasNotification
                            ? Colors.amberAccent.withValues(alpha: 0.15)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Icon(
                      task.hasNotification
                          ? Icons.notifications_active
                          : Icons.notifications_off_outlined,
                      color: task.hasNotification
                          ? Colors.amberAccent
                          : _mutedTextColor.withValues(alpha: 0.45),
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );

    // Wrap with Dismissible only if NOT in delete mode (Swipe Gestures)
    if (_isDeleteMode) {
      return GestureDetector(
        onTap: () {
          setState(() {
            if (isSelectedForDelete) {
              _selectedTaskIds.remove(task.id);
            } else {
              _selectedTaskIds.add(task.id);
            }
          });
        },
        child: cardContent,
      );
    }

    return Dismissible(
      key: Key(task.id),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _accentGreen,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.check_circle, color: _colors.onPrimary, size: 30),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _accentRed,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white, size: 30),
      ),
      onDismissed: (direction) async {
        if (direction == DismissDirection.endToStart) {
          // Swipe Left -> Delete
          await _supabaseService.deleteTask(task.id);
        } else if (direction == DismissDirection.startToEnd) {
          // Swipe Right -> Toggle Status
          await _supabaseService.toggleTaskStatus(task.id, task.isCompleted);
        }
        _refresh();
      },
      child: cardContent,
    );
  }

  // Add Task Modal
  void _showAddTaskModal(BuildContext context) {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    DateTime startDate = _selectedDate;
    DateTime endDate = _selectedDate;
    String priority = 'Medium';
    String recurrenceType = TaskModel.recurrenceNone;
    String? selectedWalletId;
    bool enableNotification = false;
    TimeOfDay? notificationTime;

    final walletsFuture = _supabaseService.getWallets();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 15,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _mutedTextColor.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                context.t("Create New Task", "إنشاء مهمة جديدة"),
                style: TextStyle(
                  color: _textColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: titleController,
                style: TextStyle(color: _textColor),
                decoration: _inputStyle(
                  context.t("What do you need to do?", "ماذا تريد أن تفعل؟"),
                  Icons.title,
                ),
              ),
              const SizedBox(height: 15),
              GestureDetector(
                onTap: () async {
                  final DateTimeRange? range = await showDateRangePicker(
                    context: context,
                    initialDateRange: DateTimeRange(
                      start: startDate,
                      end: endDate,
                    ),
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (context, child) => Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: ColorScheme.dark(
                          primary: _accentGreen,
                          onPrimary: _colors.onPrimary,
                          surface: _cardColor,
                          onSurface: _textColor,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (range != null) {
                    setModalState(() {
                      startDate = range.start;
                      endDate = range.end;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: _colors.subtleBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month, color: _accentGreen, size: 22),
                      const SizedBox(width: 15),
                      Text(
                        "${DateFormat.yMMMd().format(startDate)} - ${DateFormat.yMMMd().format(endDate)}",
                        style: TextStyle(
                          color: _textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Column(
                children: [
                  _buildRecurrenceSelector(
                    recurrenceType,
                    (value) => setModalState(() => recurrenceType = value),
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    initialValue: priority,
                    dropdownColor: _cardColor,
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: _inputStyle("Priority", Icons.flag),
                    items: ['Low', 'Medium', 'High']
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (val) => setModalState(() => priority = val!),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _colors.subtleBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.notifications_active,
                          color: enableNotification
                              ? Colors.amberAccent
                              : _mutedTextColor,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          enableNotification && notificationTime != null
                              ? "Alert at ${notificationTime!.format(context)}"
                              : "Reminder",
                          style: TextStyle(
                            color: enableNotification
                                ? _textColor
                                : _mutedTextColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: enableNotification,
                      activeThumbColor: Colors.amberAccent,
                      onChanged: (val) async {
                        if (val) {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                            builder: (context, child) => Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: ColorScheme.dark(
                                  primary: Colors.amberAccent,
                                  onPrimary: _colors.onPrimary,
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (time != null) {
                            setModalState(() {
                              enableNotification = true;
                              notificationTime = time;
                            });
                          }
                        } else {
                          setModalState(() {
                            enableNotification = false;
                            notificationTime = null;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(color: _colors.subtleBorder),
              ),
              Text(
                context.t("Link to Wallet (Optional)", "ربط بمحفظة (اختياري)"),
                style: TextStyle(color: _secondaryTextColor, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: TextStyle(
                        color: _textColor,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: _inputStyle("Amount", Icons.attach_money),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: FutureBuilder<List<WalletModel>>(
                      future: walletsFuture,
                      builder: (context, snapshot) =>
                          DropdownButtonFormField<String>(
                            dropdownColor: _cardColor,
                            isExpanded: true,
                            style: TextStyle(color: _textColor, fontSize: 14),
                            decoration: _inputStyle(
                              "Select Wallet",
                              Icons.account_balance_wallet,
                            ),
                            items: snapshot.data
                                ?.map(
                                  (w) => DropdownMenuItem(
                                    value: w.id,
                                    child: Text(
                                      w.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) => selectedWalletId = val,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  if (titleController.text.isNotEmpty) {
                    final user = _supabaseService.client.auth.currentUser;
                    if (user == null) return;

                    DateTime taskDueDate = startDate;

                    if (enableNotification && notificationTime != null) {
                      taskDueDate = DateTime(
                        startDate.year,
                        startDate.month,
                        startDate.day,
                        notificationTime!.hour,
                        notificationTime!.minute,
                      );
                    }

                    final newTask = TaskModel(
                      id: '',
                      title: titleController.text.trim(),
                      description: '',
                      dueDate: taskDueDate,
                      endDate: endDate,
                      priority: priority,
                      userId: user.id,
                      isRecurring: recurrenceType != TaskModel.recurrenceNone,
                      recurrenceType: recurrenceType,
                      linkedWalletId: selectedWalletId,
                      amount: double.tryParse(amountController.text) ?? 0.0,
                      hasNotification:
                          enableNotification && notificationTime != null,
                    );

                    final insertedTask = await _supabaseService.addTask(
                      newTask,
                    );

                    if (enableNotification && notificationTime != null) {
                      final scheduled = await NotificationService()
                          .scheduleTaskReminder(
                            id: NotificationService.taskReminderId(
                              insertedTask.id,
                            ),
                            title: 'FinMind Task Reminder',
                            body: insertedTask.title,
                            firstDateTime: taskDueDate,
                            recurrenceType: recurrenceType,
                          );

                      debugPrint("Task notification scheduled: $scheduled");

                      await _supabaseService.updateTaskNotificationStatus(
                        insertedTask.id,
                        scheduled,
                      );
                    }

                    if (!mounted) return;
                    Navigator.pop(context);
                    _refresh();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGreen,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 5,
                  shadowColor: _accentGreen.withValues(alpha: 0.5),
                ),
                child: Text(
                  context.t("CREATE TASK", "إنشاء المهمة"),
                  style: TextStyle(
                    color: _colors.onPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 25),
            ],
          ),
        ),
      ),
    );
  }

  /// UI: Shows a modal pre-filled with task data for editing
  void _showEditTaskModal(BuildContext context, TaskModel existingTask) {
    final titleController = TextEditingController(text: existingTask.title);
    final amountController = TextEditingController(
      text: existingTask.amount > 0 ? existingTask.amount.toString() : '',
    );
    DateTime startDate = DateTime(
      existingTask.dueDate.year,
      existingTask.dueDate.month,
      existingTask.dueDate.day,
    );
    DateTime endDate = DateTime(
      existingTask.endDate.year,
      existingTask.endDate.month,
      existingTask.endDate.day,
    );
    String priority = existingTask.priority;
    String recurrenceType = existingTask.recurrenceType;
    String? selectedWalletId = existingTask.linkedWalletId;

    bool enableNotification = existingTask.hasNotification;
    TimeOfDay? notificationTime = existingTask.hasNotification
        ? TimeOfDay.fromDateTime(existingTask.dueDate)
        : null;

    final walletsFuture = _supabaseService.getWallets();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 15,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _mutedTextColor.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                context.t("Edit Task", "تعديل المهمة"),
                style: TextStyle(
                  color: _textColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: titleController,
                style: TextStyle(color: _textColor),
                decoration: _inputStyle(
                  context.t("Task Title", "عنوان المهمة"),
                  Icons.edit,
                ),
              ),
              const SizedBox(height: 15),
              GestureDetector(
                onTap: () async {
                  final DateTimeRange? range = await showDateRangePicker(
                    context: context,
                    initialDateRange: DateTimeRange(
                      start: startDate,
                      end: endDate,
                    ),
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (range != null) {
                    setModalState(() {
                      startDate = range.start;
                      endDate = range.end;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: _colors.subtleBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.date_range, color: _accentGreen),
                      const SizedBox(width: 15),
                      Text(
                        "${DateFormat.yMMMd().format(startDate)} - ${DateFormat.yMMMd().format(endDate)}",
                        style: TextStyle(
                          color: _textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Column(
                children: [
                  _buildRecurrenceSelector(
                    recurrenceType,
                    (value) => setModalState(() => recurrenceType = value),
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    initialValue: priority,
                    dropdownColor: _cardColor,
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: _inputStyle("Priority", Icons.flag),
                    items: ['Low', 'Medium', 'High']
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (val) => setModalState(() => priority = val!),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _colors.subtleBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.notifications_active,
                          color: enableNotification
                              ? Colors.amberAccent
                              : _mutedTextColor,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          enableNotification && notificationTime != null
                              ? "Alert at ${notificationTime!.format(context)}"
                              : "Reset Alert",
                          style: TextStyle(
                            color: enableNotification
                                ? _textColor
                                : _mutedTextColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: enableNotification,
                      activeThumbColor: Colors.amberAccent,
                      onChanged: (val) async {
                        if (val) {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (time != null) {
                            setModalState(() {
                              enableNotification = true;
                              notificationTime = time;
                            });
                          }
                        } else {
                          setModalState(() {
                            enableNotification = false;
                            notificationTime = null;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(color: _colors.subtleBorder),
              ),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: TextStyle(
                        color: _textColor,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: _inputStyle("Amount", Icons.attach_money),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: FutureBuilder<List<WalletModel>>(
                      future: walletsFuture,
                      builder: (context, snapshot) =>
                          DropdownButtonFormField<String>(
                            initialValue: selectedWalletId,
                            dropdownColor: _cardColor,
                            isExpanded: true,
                            style: TextStyle(color: _textColor, fontSize: 14),
                            decoration: _inputStyle(
                              "Select Wallet",
                              Icons.account_balance_wallet,
                            ),
                            items: snapshot.data
                                ?.map(
                                  (w) => DropdownMenuItem(
                                    value: w.id,
                                    child: Text(
                                      w.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) => selectedWalletId = val,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  if (titleController.text.isNotEmpty) {
                    DateTime updatedDueDate = startDate;

                    if (enableNotification && notificationTime != null) {
                      updatedDueDate = DateTime(
                        startDate.year,
                        startDate.month,
                        startDate.day,
                        notificationTime!.hour,
                        notificationTime!.minute,
                      );
                    }

                    final updatedTask = TaskModel(
                      id: existingTask.id,
                      title: titleController.text.trim(),
                      description: existingTask.description,
                      dueDate: updatedDueDate,
                      endDate: endDate,
                      priority: priority,
                      isCompleted: existingTask.isCompleted,
                      userId: existingTask.userId,
                      isRecurring: recurrenceType != TaskModel.recurrenceNone,
                      recurrenceType: recurrenceType,
                      linkedWalletId: selectedWalletId,
                      amount: double.tryParse(amountController.text) ?? 0.0,
                      hasNotification:
                          enableNotification && notificationTime != null,
                    );

                    await _supabaseService.updateTask(
                      updatedTask,
                      rescheduleAlert:
                          enableNotification && notificationTime != null,
                      newAlertTime:
                          enableNotification && notificationTime != null
                          ? updatedDueDate
                          : null,
                    );

                    if (!mounted) return;
                    Navigator.pop(context);
                    _refresh();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentBlue,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Text(
                  context.t("UPDATE TASK", "تحديث المهمة"),
                  style: TextStyle(
                    color: _colors.onPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 25),
            ],
          ),
        ),
      ),
    );
  }

  DateTime _displayDate(TaskModel task) => task.occurrenceDate ?? task.dueDate;

  Widget _buildTaskMetaPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecurrenceSelector(
    String selectedValue,
    ValueChanged<String> onChanged,
  ) {
    final options = [
      (
        value: TaskModel.recurrenceNone,
        label: context.t('None', 'بدون'),
        icon: Icons.event_available,
      ),
      (
        value: TaskModel.recurrenceDaily,
        label: context.t('Daily', 'يومي'),
        icon: Icons.repeat,
      ),
      (
        value: TaskModel.recurrenceMonthly,
        label: context.t('Monthly', 'شهري'),
        icon: Icons.calendar_month,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _colors.subtleBorder),
      ),
      child: Row(
        children: options.map((option) {
          final isSelected = selectedValue == option.value;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onChanged(option.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: isSelected ? _accentGreen : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        option.icon,
                        size: 18,
                        color: isSelected ? _colors.onPrimary : _mutedTextColor,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected
                              ? _colors.onPrimary
                              : _secondaryTextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _getRecurrenceLabel(String recurrenceType) {
    return switch (recurrenceType) {
      TaskModel.recurrenceDaily => context.t('Daily', 'يومي'),
      TaskModel.recurrenceMonthly => context.t('Monthly', 'شهري'),
      _ => context.t('Once', 'مرة واحدة'),
    };
  }

  IconData _getRecurrenceIcon(String recurrenceType) {
    return switch (recurrenceType) {
      TaskModel.recurrenceDaily => Icons.repeat,
      TaskModel.recurrenceMonthly => Icons.calendar_month,
      _ => Icons.event_available,
    };
  }

  InputDecoration _inputStyle(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: _mutedTextColor, fontSize: 14),
    prefixIcon: Icon(icon, color: _accentGreen, size: 22),
    filled: true,
    fillColor: _cardColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: _colors.subtleBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: _accentGreen, width: 2),
    ),
  );

  Color _getPriorityColor(String priority) {
    if (priority == 'High') return _accentRed;
    if (priority == 'Medium') return Colors.orangeAccent;
    return _accentBlue;
  }

  int _getPriorityWeight(String priority) {
    if (priority == 'High') return 3;
    if (priority == 'Medium') return 2;
    if (priority == 'Low') return 1;
    return 0;
  }
}

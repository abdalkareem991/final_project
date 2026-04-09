// lib/screens/todo_list_screen.dart

import 'package:easy_date_timeline/easy_date_timeline.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task_model.dart';
import '../models/wallet_model.dart';
import '../services/supabase_service.dart';

class TodoListScreen extends StatefulWidget {
  const TodoListScreen({super.key});

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  final _supabaseService = SupabaseService();
  DateTime _selectedDate = DateTime.now();
  String _filterStatus = "All";

  // Data storage
  Map<String, int> _taskStats = {'total': 0, 'completed': 0, 'pending': 0};
  // ignore: unused_field
  Map<DateTime, int> _tasksCountMap = {};

  // Multi-Selection Logic
  bool _isDeleteMode = false;
  final List<String> _selectedTaskIds = [];

  // Theme constants
  static const Color _bgColor = Color(0xFF061414);
  static const Color _cardColor = Color(0xFF111D1D);
  static const Color _accentGreen = Color(0xFF34EAB9);

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  // CORE FUNCTION: Fetches all dynamic data
  Future<void> _loadAllData() async {
    try {
      final stats = await _supabaseService.getTaskStats();
      final counts = await _supabaseService.getTasksCountForMonth(
        _selectedDate,
      );
      if (mounted) {
        setState(() {
          _taskStats = stats;
          _tasksCountMap = counts;
        });
      }
    } catch (e) {
      debugPrint("Error loading dashboard data: $e");
    }
  }

  void _refresh() => _loadAllData();

  // FUNCTION: Executes bulk delete and resets UI
  Future<void> _handleBulkDelete() async {
    if (_selectedTaskIds.isEmpty) return;

    // Show confirmation dialog
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text(
          "Confirm Delete",
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          "Are you sure you want to delete ${_selectedTaskIds.length} tasks?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        for (String id in _selectedTaskIds) {
          await _supabaseService.deleteTask(id);
        }
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
              ? "${_selectedTaskIds.length} Selected"
              : "Productive Day",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 22,
          ),
        ),
        leading: _isDeleteMode
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => setState(() {
                  _isDeleteMode = false;
                  _selectedTaskIds.clear();
                }),
              )
            : null,
        actions: [
          IconButton(
            icon: Icon(
              _isDeleteMode ? Icons.delete_forever : Icons.delete_outline,
              color: _isDeleteMode ? Colors.redAccent : Colors.white,
            ),
            onPressed: () => setState(() {
              _isDeleteMode = !_isDeleteMode;
              _selectedTaskIds.clear();
            }),
          ),
          if (!_isDeleteMode)
            IconButton(
              icon: const Icon(Icons.sync, color: Colors.white),
              onPressed: _refresh,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildStatsSummary(),
          const SizedBox(height: 10),
          _buildCalendarTimeline(),
          _buildFilterChips(),
          Expanded(child: _buildTasksList()),
        ],
      ),
      bottomNavigationBar: _isDeleteMode && _selectedTaskIds.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(20),
              color: Colors.redAccent.withValues(alpha: 0.9),
              child: InkWell(
                onTap: _handleBulkDelete,
                child: const Text(
                  "CONFIRM BATCH DELETE",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          : null,
      floatingActionButton: _isDeleteMode
          ? null
          : FloatingActionButton(
              backgroundColor: _accentGreen,
              onPressed: () => _showAddTaskModal(context),
              child: const Icon(Icons.add, color: Colors.black, size: 32),
            ),
    );
  }

  Widget _buildStatsSummary() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _statItem(
            "Pending",
            "${_taskStats['pending']}",
            Colors.orangeAccent,
            Icons.pending_actions,
          ),
          _statItem(
            "Done",
            "${_taskStats['completed']}",
            _accentGreen,
            Icons.check_circle_outline,
          ),
          _statItem(
            "Total",
            "${_taskStats['total']}",
            Colors.blueAccent,
            Icons.list_alt,
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color, IconData icon) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.29,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildCalendarTimeline() {
    return FutureBuilder<Map<DateTime, int>>(
      future: _supabaseService.getTasksCountForMonth(_selectedDate),
      builder: (context, snapshot) {
        final countsMap = snapshot.data ?? {};

        return EasyDateTimeLine(
          initialDate: _selectedDate,
          onDateChange: (date) {
            setState(() => _selectedDate = date);
            _refresh();
          },
          headerProps: const EasyHeaderProps(
            monthPickerType: MonthPickerType.switcher,
          ),
          dayProps: const EasyDayProps(
            dayStructure: DayStructure.dayStrDayNum,
            height: 85,
            width: 65,
          ),
          // CORRECTED: Matches (context, date, isSelected, onTap)
          itemBuilder: (context, date, isSelected, onTap) {
            DateTime normalized = DateTime(date.year, date.month, date.day);
            int count = countsMap[normalized] ?? 0;

            return GestureDetector(
              onTap: onTap,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected ? _accentGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: isSelected ? _accentGreen : Colors.white24,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat.E().format(date), // Day Name (Mon, Tue)
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      date.day.toString(), // Day Number
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (count > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.black26
                              : _accentGreen.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "$count",
                          style: TextStyle(
                            color: isSelected ? Colors.black : _accentGreen,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: ["All", "Pending", "Completed"].map((status) {
          final isSelected = _filterStatus == status;
          return ChoiceChip(
            label: Text(status),
            selected: isSelected,
            onSelected: (val) => setState(() => _filterStatus = status),
            selectedColor: _accentGreen,
            backgroundColor: _cardColor,
            labelStyle: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontSize: 13,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTasksList() {
    return FutureBuilder<List<TaskModel>>(
      future: _supabaseService.getTasks(_selectedDate),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(
            child: CircularProgressIndicator(color: _accentGreen),
          );
        var tasks = snapshot.data ?? [];
        if (_filterStatus == "Pending")
          tasks = tasks.where((t) => !t.isCompleted).toList();
        if (_filterStatus == "Completed")
          tasks = tasks.where((t) => t.isCompleted).toList();

        if (tasks.isEmpty)
          return const Center(
            child: Text("No tasks found", style: TextStyle(color: Colors.grey)),
          );

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: tasks.length,
          itemBuilder: (context, index) => _buildTaskCard(tasks[index]),
        );
      },
    );
  }

  Widget _buildTaskCard(TaskModel task) {
    bool isSelectedForDelete = _selectedTaskIds.contains(task.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: isSelectedForDelete
            ? Border.all(color: Colors.redAccent, width: 2)
            : Border.all(
                color: _getPriorityColor(task.priority).withValues(alpha: 0.3),
              ),
      ),
      child: Row(
        children: [
          _isDeleteMode
              ? Checkbox(
                  value: isSelectedForDelete,
                  activeColor: Colors.redAccent,
                  onChanged: (v) => setState(() {
                    if (v!)
                      _selectedTaskIds.add(task.id);
                    else
                      _selectedTaskIds.remove(task.id);
                  }),
                )
              : GestureDetector(
                  onTap: () async {
                    await _supabaseService.toggleTaskStatus(
                      task.id,
                      task.isCompleted,
                    );
                    _refresh();
                  },
                  child: Icon(
                    task.isCompleted
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: task.isCompleted ? _accentGreen : Colors.grey,
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
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                Text(
                  "${DateFormat.yMMMd().format(task.dueDate)} - ${DateFormat.yMMMd().format(task.endDate)}",
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          if (task.linkedWalletId != null && !_isDeleteMode)
            Row(
              children: [
                Text(
                  "\$${task.amount.toStringAsFixed(1)} ",
                  style: const TextStyle(
                    color: _accentGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Icon(
                  Icons.account_balance_wallet,
                  color: _accentGreen,
                  size: 16,
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _showAddTaskModal(BuildContext context) {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    DateTime startDate = _selectedDate;
    DateTime endDate = _selectedDate.add(const Duration(days: 1));
    String priority = 'Medium';
    bool isRecurring = false;
    String? selectedWalletId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 50,
                child: Divider(thickness: 4, color: Colors.white10),
              ),
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputStyle("Task Title", Icons.edit),
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
                  if (range != null)
                    setModalState(() {
                      startDate = range.start;
                      endDate = range.end;
                    });
                },
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range, color: _accentGreen),
                      const SizedBox(width: 15),
                      Text(
                        "${DateFormat.yMMMd().format(startDate)} - ${DateFormat.yMMMd().format(endDate)}",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        "Repeat Daily",
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      value: isRecurring,
                      activeColor: _accentGreen,
                      onChanged: (v) =>
                          setModalState(() => isRecurring = v ?? false),
                    ),
                  ),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: priority,
                      dropdownColor: _cardColor,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: _inputStyle("Priority", Icons.flag),
                      items: ['Low', 'Medium', 'High']
                          .map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          )
                          .toList(),
                      onChanged: (val) => setModalState(() => priority = val!),
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 40),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputStyle("Amount", Icons.attach_money),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: FutureBuilder<List<WalletModel>>(
                      future: _supabaseService.getWallets(),
                      builder: (context, snapshot) =>
                          DropdownButtonFormField<String>(
                            dropdownColor: _cardColor,
                            isExpanded: true,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                            decoration: _inputStyle(
                              "Wallet",
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
                    await _supabaseService.addTask(
                      TaskModel(
                        id: '',
                        title: titleController.text.trim(),
                        description: '',
                        dueDate: startDate,
                        endDate: endDate,
                        priority: priority,
                        userId: user.id,
                        isRecurring: isRecurring,
                        linkedWalletId: selectedWalletId,
                        amount: double.tryParse(amountController.text) ?? 0.0,
                      ),
                    );
                    if (!mounted) return;
                    Navigator.pop(context);
                    _refresh();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGreen,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  "SAVE TASK",
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
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

  InputDecoration _inputStyle(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
    prefixIcon: Icon(icon, color: _accentGreen, size: 20),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.02),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.white10),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _accentGreen),
    ),
  );

  Color _getPriorityColor(String priority) {
    if (priority == 'High') return Colors.redAccent;
    if (priority == 'Medium') return Colors.orangeAccent;
    return Colors.blueAccent;
  }
}

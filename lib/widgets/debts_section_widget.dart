import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/debts_model.dart';
import '../services/debts_service.dart';

class DebtsSectionWidget extends StatefulWidget {
  const DebtsSectionWidget({super.key});

  @override
  State<DebtsSectionWidget> createState() => DebtsSectionWidgetState();
}

class DebtsSectionWidgetState extends State<DebtsSectionWidget> {
  final DebtsService _debtsService = DebtsService();

  late Future<List<DebtModel>> _debtsFuture;

  static const Color _cardColor = Color(0xFF111D1D);
  static const Color _fieldColor = Color(0xFF0B1818);
  static const Color _accentGreen = Color(0xFF34EAB9);
  static const Color _expenseRed = Color(0xFFFF5252);
  static const Color _accentBlue = Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    _debtsFuture = _debtsService.getActiveDebtsForCurrentUser();
  }

  Future<void> refreshDebts() async {
    final future = _debtsService.getActiveDebtsForCurrentUser();
    if (!mounted) return;
    setState(() => _debtsFuture = future);

    try {
      await future;
    } catch (_) {
      // The FutureBuilder owns the visible error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            FutureBuilder<List<DebtModel>>(
              future: _debtsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: CircularProgressIndicator(color: _accentGreen),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                }

                final debts = snapshot.data ?? [];
                final summary = _debtsService.buildSummary(debts);

                return Column(
                  children: [
                    _buildSummary(summary),
                    const SizedBox(height: 16),
                    if (debts.isEmpty)
                      _buildEmptyState()
                    else
                      _buildDebtsList(debts),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _accentBlue.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.handshake, color: _accentBlue, size: 20),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Debt Tracking",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 2),
              Text(
                "Separate from account balances",
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: "Add Debt",
          onPressed: () => _showDebtSheet(),
          icon: const Icon(Icons.add_circle, color: _accentGreen, size: 30),
        ),
      ],
    );
  }

  Widget _buildSummary(DebtSummary summary) {
    final netDebt = summary.netDebt;
    final netColor = netDebt > 0
        ? _accentGreen
        : netDebt < 0
        ? _expenseRed
        : Colors.white70;
    final netText = netDebt > 0
        ? "You should receive ${_formatAmount(netDebt)}"
        : netDebt < 0
        ? "You should pay ${_formatAmount(netDebt.abs())}"
        : "No net debt";

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                title: "Money Owed To Me",
                amount: summary.totalDebtorAmount,
                icon: Icons.south_west,
                color: _accentGreen,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSummaryCard(
                title: "Money I Owe",
                amount: summary.totalCreditorAmount,
                icon: Icons.north_east,
                color: _expenseRed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _fieldColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: netColor.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Icon(Icons.balance, color: netColor, size: 20),
              const SizedBox(width: 10),
              const Text(
                "Net",
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  netText,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: netColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required double amount,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _fieldColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _formatAmount(amount),
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebtsList(List<DebtModel> debts) {
    return Column(children: debts.map(_buildDebtCard).toList());
  }

  Widget _buildDebtCard(DebtModel debt) {
    final isDebtor = debt.isDebtor;
    final color = isDebtor ? _accentGreen : _expenseRed;
    final typeText = isDebtor ? "Debtor • Owes me" : "Creditor • I owe";
    final dueText = debt.dueDate == null
        ? "No due date"
        : "Due: ${DateFormat.yMMMd().format(debt.dueDate!)}";

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _fieldColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isDebtor ? Icons.south_west : Icons.north_east,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        debt.personName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _formatAmount(debt.amount),
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  typeText,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$dueText • ${debt.status}",
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (debt.note != null && debt.note!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    debt.note!,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
            color: _cardColor,
            onSelected: (value) {
              if (value == 'edit') {
                _showDebtSheet(existingDebt: debt);
              } else if (value == 'paid') {
                _markAsPaid(debt);
              } else if (value == 'delete') {
                _deleteDebt(debt);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: Text("Edit", style: TextStyle(color: Colors.white)),
              ),
              PopupMenuItem(
                value: 'paid',
                child: Text(
                  "Mark as Paid",
                  style: TextStyle(color: _accentGreen),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text("Delete", style: TextStyle(color: _expenseRed)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      decoration: BoxDecoration(
        color: _fieldColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined, color: Colors.white38, size: 34),
          SizedBox(height: 10),
          Text(
            "No active debts",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          SizedBox(height: 4),
          Text(
            "Track money owed to you or money you owe here.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _fieldColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: _expenseRed, size: 30),
          const SizedBox(height: 8),
          const Text(
            "Could not load debts",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: refreshDebts,
            icon: const Icon(Icons.refresh, color: _accentGreen),
            label: const Text("Retry", style: TextStyle(color: _accentGreen)),
          ),
        ],
      ),
    );
  }

  void _showDebtSheet({DebtModel? existingDebt}) {
    final isEditing = existingDebt != null;
    final personController = TextEditingController(
      text: existingDebt?.personName ?? '',
    );
    final amountController = TextEditingController(
      text: existingDebt == null ? '' : existingDebt.amount.toStringAsFixed(2),
    );
    final noteController = TextEditingController(
      text: existingDebt?.note ?? '',
    );

    String selectedType = existingDebt?.type ?? 'debtor';
    DateTime? selectedDueDate = existingDebt?.dueDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF061414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 22,
                right: 22,
                top: 18,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isEditing ? "Edit Debt" : "Add Debt",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTypeToggle(
                          label: "Debtor",
                          subtitle: "Owes me",
                          icon: Icons.south_west,
                          color: _accentGreen,
                          isSelected: selectedType == 'debtor',
                          onTap: () =>
                              setModalState(() => selectedType = 'debtor'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildTypeToggle(
                          label: "Creditor",
                          subtitle: "I owe",
                          icon: Icons.north_east,
                          color: _expenseRed,
                          isSelected: selectedType == 'creditor',
                          onTap: () =>
                              setModalState(() => selectedType = 'creditor'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: personController,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration("Person Name", Icons.person),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: _inputDecoration("Amount (JD)", Icons.payments),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: sheetContext,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(DateTime.now().year + 10),
                        initialDate: selectedDueDate ?? DateTime.now(),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: _accentGreen,
                                surface: _cardColor,
                                onSurface: Colors.white,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );

                      if (pickedDate != null) {
                        setModalState(() => selectedDueDate = pickedDate);
                      }
                    },
                    child: InputDecorator(
                      decoration: _inputDecoration(
                        "Due Date",
                        Icons.event_outlined,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedDueDate == null
                                  ? "Optional"
                                  : DateFormat.yMMMd().format(selectedDueDate!),
                              style: TextStyle(
                                color: selectedDueDate == null
                                    ? Colors.grey
                                    : Colors.white,
                              ),
                            ),
                          ),
                          if (selectedDueDate != null)
                            GestureDetector(
                              onTap: () =>
                                  setModalState(() => selectedDueDate = null),
                              child: const Icon(
                                Icons.close,
                                color: Colors.grey,
                                size: 18,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: noteController,
                    minLines: 2,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration("Note", Icons.notes),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentGreen,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: () async {
                      final personName = personController.text.trim();
                      final amount =
                          double.tryParse(amountController.text.trim()) ?? 0.0;

                      if (personName.isEmpty) {
                        _showSnack("Person name is required.");
                        return;
                      }

                      if (amount <= 0) {
                        _showSnack("Amount must be greater than zero.");
                        return;
                      }

                      final userId = _debtsService.currentUserId;
                      if (userId == null) {
                        _showSnack("User not logged in.");
                        return;
                      }

                      final debt = DebtModel(
                        id: existingDebt?.id ?? '',
                        userId: existingDebt?.userId ?? userId,
                        personName: personName,
                        amount: amount,
                        type: selectedType,
                        note: noteController.text,
                        dueDate: selectedDueDate,
                        status: existingDebt?.status ?? 'active',
                        createdAt: existingDebt?.createdAt ?? DateTime.now(),
                      );

                      try {
                        if (isEditing) {
                          await _debtsService.updateDebt(debt);
                        } else {
                          await _debtsService.addDebt(debt);
                        }

                        if (!mounted) return;
                        Navigator.pop(sheetContext);
                        await refreshDebts();
                      } catch (e) {
                        _showSnack("Save failed: $e");
                      }
                    },
                    child: Text(
                      isEditing ? "UPDATE DEBT" : "SAVE DEBT",
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTypeToggle({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.14) : _fieldColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAsPaid(DebtModel debt) async {
    final confirmed = await _confirmAction(
      title: "Mark as Paid",
      message:
          "This will remove ${debt.personName} from active debt totals without changing any account balance.",
      confirmText: "Mark Paid",
      confirmColor: _accentGreen,
    );

    if (confirmed != true) return;

    try {
      await _debtsService.markDebtAsPaid(debt.id);
      await refreshDebts();
    } catch (e) {
      _showSnack("Could not mark as paid: $e");
    }
  }

  Future<void> _deleteDebt(DebtModel debt) async {
    final confirmed = await _confirmAction(
      title: "Delete Debt",
      message:
          "Delete this debt record? This will not change any account balance.",
      confirmText: "Delete",
      confirmColor: _expenseRed,
    );

    if (confirmed != true) return;

    try {
      await _debtsService.deleteDebt(debt.id);
      await refreshDebts();
    } catch (e) {
      _showSnack("Could not delete debt: $e");
    }
  }

  Future<bool?> _confirmAction({
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmText,
              style: TextStyle(
                color: confirmColor == _accentGreen
                    ? Colors.black
                    : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
      prefixIcon: Icon(icon, color: _accentGreen, size: 21),
      filled: true,
      fillColor: _cardColor,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: _accentGreen, width: 2),
      ),
    );
  }

  String _formatAmount(double amount) {
    return "JD ${amount.toStringAsFixed(2)}";
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: _cardColor),
    );
  }
}

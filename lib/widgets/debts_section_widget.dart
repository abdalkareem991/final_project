import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/app_text.dart';
import '../core/app_theme.dart';
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

  AppThemeColors get _colors => context.themeColors;
  Color get _cardColor => _colors.surface;
  Color get _fieldColor => _colors.field;
  Color get _accentGreen => _colors.primary;
  Color get _expenseRed => _colors.expense;
  Color get _accentBlue => _colors.transfer;
  Color get _textColor => _colors.textPrimary;
  Color get _secondaryTextColor => _colors.textSecondary;
  Color get _mutedTextColor => _colors.textMuted;

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
          border: Border.all(color: _colors.subtleBorder),
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
                  return Padding(
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
          child: Icon(Icons.handshake, color: _accentBlue, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t("Debt Tracking", "تتبع الديون"),
                style: TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                context.t(
                  "Separate from account balances",
                  "منفصلة عن أرصدة الحسابات",
                ),
                style: TextStyle(color: _mutedTextColor, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: context.t("Add Debt", "إضافة دين"),
          onPressed: () => _showDebtSheet(),
          icon: Icon(Icons.add_circle, color: _accentGreen, size: 30),
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
        : _secondaryTextColor;
    final netText = netDebt > 0
        ? context.t(
            "You should receive ${_formatAmount(netDebt)}",
            "يجب أن تستلم ${_formatAmount(netDebt)}",
          )
        : netDebt < 0
        ? context.t(
            "You should pay ${_formatAmount(netDebt.abs())}",
            "يجب أن تدفع ${_formatAmount(netDebt.abs())}",
          )
        : context.t("No net debt", "لا يوجد صافي دين");

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                title: context.t("Money Owed To Me", "أموال مستحقة لي"),
                amount: summary.totalDebtorAmount,
                icon: Icons.south_west,
                color: _accentGreen,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSummaryCard(
                title: context.t("Money I Owe", "أموال علي دفعها"),
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
              Text(
                context.t("Net", "الصافي"),
                style: TextStyle(
                  color: _secondaryTextColor,
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
                  style: TextStyle(
                    color: _mutedTextColor,
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
    final typeText = isDebtor
        ? context.t("Debtor • Owes me", "مدين • عليه لي")
        : context.t("Creditor • I owe", "دائن • له علي");
    final dueText = debt.dueDate == null
        ? context.t("No due date", "لا يوجد تاريخ استحقاق")
        : "${context.t("Due", "الاستحقاق")}: ${DateFormat.yMMMd().format(debt.dueDate!)}";

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
                        style: TextStyle(
                          color: _textColor,
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
                  "$dueText • ${context.enumText(debt.status)}",
                  style: TextStyle(color: _mutedTextColor, fontSize: 12),
                ),
                if (debt.note != null && debt.note!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    debt.note!,
                    style: TextStyle(color: _secondaryTextColor, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: _mutedTextColor, size: 20),
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
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(
                  context.t("Edit", "تعديل"),
                  style: TextStyle(color: _textColor),
                ),
              ),
              PopupMenuItem(
                value: 'paid',
                child: Text(
                  context.t("Mark as Paid", "تحديد كمدفوع"),
                  style: TextStyle(color: _accentGreen),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  context.t("Delete", "حذف"),
                  style: TextStyle(color: _expenseRed),
                ),
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
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            color: _mutedTextColor.withValues(alpha: 0.6),
            size: 34,
          ),
          const SizedBox(height: 10),
          Text(
            context.t("No active debts", "لا توجد ديون نشطة"),
            style: TextStyle(
              color: _textColor,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.t(
              "Track money owed to you or money you owe here.",
              "تتبع الأموال المستحقة لك أو عليك هنا.",
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: _mutedTextColor, fontSize: 12),
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
          Icon(Icons.error_outline, color: _expenseRed, size: 30),
          const SizedBox(height: 8),
          Text(
            context.t("Could not load debts", "تعذر تحميل الديون"),
            style: TextStyle(color: _textColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: _mutedTextColor, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: refreshDebts,
            icon: Icon(Icons.refresh, color: _accentGreen),
            label: Text(
              context.t("Retry", "إعادة المحاولة"),
              style: TextStyle(color: _accentGreen),
            ),
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
      backgroundColor: _cardColor,
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
                        color: _mutedTextColor.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isEditing
                        ? context.t("Edit Debt", "تعديل الدين")
                        : context.t("Add Debt", "إضافة دين"),
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTypeToggle(
                          label: context.t("Debtor", "مدين"),
                          subtitle: context.t("Owes me", "عليه لي"),
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
                          label: context.t("Creditor", "دائن"),
                          subtitle: context.t("I owe", "له علي"),
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
                    style: TextStyle(color: _textColor),
                    decoration: _inputDecoration(
                      context.t("Person Name", "اسم الشخص"),
                      Icons.person,
                    ),
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
                    style: TextStyle(
                      color: _textColor,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: _inputDecoration(
                      context.t("Amount (JD)", "المبلغ بالدينار"),
                      Icons.payments,
                    ),
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
                              colorScheme: ColorScheme.dark(
                                primary: _accentGreen,
                                surface: _cardColor,
                                onSurface: _textColor,
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
                        context.t("Due Date", "تاريخ الاستحقاق"),
                        Icons.event_outlined,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedDueDate == null
                                  ? context.t("Optional", "اختياري")
                                  : DateFormat.yMMMd().format(selectedDueDate!),
                              style: TextStyle(
                                color: selectedDueDate == null
                                    ? _mutedTextColor
                                    : _textColor,
                              ),
                            ),
                          ),
                          if (selectedDueDate != null)
                            GestureDetector(
                              onTap: () =>
                                  setModalState(() => selectedDueDate = null),
                              child: Icon(
                                Icons.close,
                                color: _mutedTextColor,
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
                    style: TextStyle(color: _textColor),
                    decoration: _inputDecoration(
                      context.t("Note", "ملاحظة"),
                      Icons.notes,
                    ),
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
                        _showSnack(
                          context.t(
                            "Person name is required.",
                            "اسم الشخص مطلوب.",
                          ),
                        );
                        return;
                      }

                      if (amount <= 0) {
                        _showSnack(
                          context.t(
                            "Amount must be greater than zero.",
                            "يجب أن يكون المبلغ أكبر من صفر.",
                          ),
                        );
                        return;
                      }

                      final userId = _debtsService.currentUserId;
                      if (userId == null) {
                        _showSnack(
                          context.t(
                            "User not logged in.",
                            "المستخدم غير مسجل.",
                          ),
                        );
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
                        _showSnack(
                          context.t("Save failed: $e", "فشل الحفظ: $e"),
                        );
                      }
                    },
                    child: Text(
                      isEditing
                          ? context.t("UPDATE DEBT", "تحديث الدين")
                          : context.t("SAVE DEBT", "حفظ الدين"),
                      style: TextStyle(
                        color: _colors.onPrimary,
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
          border: Border.all(color: isSelected ? color : _colors.subtleBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : _textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: _mutedTextColor, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAsPaid(DebtModel debt) async {
    final confirmed = await _confirmAction(
      title: context.t("Mark as Paid", "تحديد كمدفوع"),
      message: context.t(
        "This will remove ${debt.personName} from active debt totals without changing any account balance.",
        "سيتم إزالة ${debt.personName} من إجماليات الديون النشطة دون تغيير أي رصيد حساب.",
      ),
      confirmText: context.t("Mark Paid", "تحديد كمدفوع"),
      confirmColor: _accentGreen,
    );

    if (confirmed != true) return;

    try {
      await _debtsService.markDebtAsPaid(debt.id);
      await refreshDebts();
    } catch (e) {
      _showSnack(
        context.t("Could not mark as paid: $e", "تعذر التحديد كمدفوع: $e"),
      );
    }
  }

  Future<void> _deleteDebt(DebtModel debt) async {
    final confirmed = await _confirmAction(
      title: context.t("Delete Debt", "حذف الدين"),
      message: context.t(
        "Delete this debt record? This will not change any account balance.",
        "هل تريد حذف سجل الدين؟ لن يغيّر ذلك أي رصيد حساب.",
      ),
      confirmText: context.t("Delete", "حذف"),
      confirmColor: _expenseRed,
    );

    if (confirmed != true) return;

    try {
      await _debtsService.deleteDebt(debt.id);
      await refreshDebts();
    } catch (e) {
      _showSnack(context.t("Could not delete debt: $e", "تعذر حذف الدين: $e"));
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
          style: TextStyle(color: _textColor, fontWeight: FontWeight.bold),
        ),
        content: Text(message, style: TextStyle(color: _secondaryTextColor)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              context.t("Cancel", "إلغاء"),
              style: TextStyle(color: _mutedTextColor),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmText,
              style: TextStyle(
                color: confirmColor == _accentGreen
                    ? _colors.onPrimary
                    : _textColor,
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
      labelStyle: TextStyle(color: _mutedTextColor, fontSize: 14),
      prefixIcon: Icon(icon, color: _accentGreen, size: 21),
      filled: true,
      fillColor: _cardColor,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: _colors.subtleBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: _accentGreen, width: 2),
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

// lib/screens/analytics_screen.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/supabase_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _supabaseService = SupabaseService();

  // State variables for dynamic animation
  String _selectedFilter = 'Month';
  final List<String> _filterOrder = ['Day', 'Week', 'Month', 'Year'];

  // --- UI Constants ---
  static const Color _bgColor = Color(0xFF061414);
  static const Color _cardColor = Color(0xFF111D1D);
  static const Color _accentGreen = Color(0xFF34EAB9);
  static const Color _expenseRed = Color(0xFFFF6B6B);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Analytics & Reports",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          _buildTimeFilterBar(),
          Expanded(
            child: FutureBuilder<Map<String, double>>(
              future: _supabaseService.getFilteredSummary(_selectedFilter),
              builder: (context, snapshot) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  // Professional curve for realistic movement
                  switchInCurve: Curves.easeOutQuart,
                  switchOutCurve: Curves.easeInQuart,
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    // Define the offset based on the intended direction
                    // We use a "Key" check to determine if we are sliding forward or backward
                    final bool slideFromRight =
                        child.key == ValueKey(_selectedFilter);

                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: slideFromRight
                            ? const Offset(
                                0.3,
                                0.0,
                              ) // Realistic small offset from right
                            : const Offset(
                                -0.3,
                                0.0,
                              ), // Realistic small offset from left
                        end: Offset.zero,
                      ).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: _buildContentBasedOnState(snapshot),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentBasedOnState(
    AsyncSnapshot<Map<String, double>> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(
        key: ValueKey('loading_state'),
        child: CircularProgressIndicator(color: _accentGreen),
      );
    }

    final data = snapshot.data ?? {'Income': 0.0, 'Expense': 0.0};
    final double income = data['Income'] ?? 0.0;
    final double expense = data['Expense'] ?? 0.0;

    return SingleChildScrollView(
      // The ValueKey ensures the AnimatedSwitcher knows when to trigger
      key: ValueKey(_selectedFilter),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Column(
        children: [
          _buildFinancialSummaryCards(income, expense),
          const SizedBox(height: 25),
          _buildBarChartContainer(income, expense),
          const SizedBox(height: 25),
          _buildDistributionPieContainer(income, expense),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTimeFilterBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filterOrder.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final String filter = _filterOrder[index];
          final bool isSelected = _selectedFilter == filter;

          return ChoiceChip(
            label: Text(filter),
            selected: isSelected,
            onSelected: (val) {
              if (val && _selectedFilter != filter) {
                setState(() {
                  _selectedFilter = filter;
                });
              }
            },
            selectedColor: _accentGreen,
            backgroundColor: _cardColor,
            labelStyle: TextStyle(
              color: isSelected ? Colors.black : Colors.grey,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            side: BorderSide(
              color: isSelected ? _accentGreen : Colors.transparent,
            ),
          );
        },
      ),
    );
  }

  Widget _buildFinancialSummaryCards(double income, double expense) {
    return Row(
      children: [
        _buildSummaryCard("INCOME", income, _accentGreen),
        const SizedBox(width: 15),
        _buildSummaryCard("EXPENSE", expense, _expenseRed),
      ],
    );
  }

  Widget _buildSummaryCard(String title, double amount, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 10,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "\$${amount.toStringAsFixed(2)}",
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChartContainer(double income, double expense) {
    return Container(
      padding: const EdgeInsets.all(24),
      height: 300,
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(28),
      ),
      child: BarChart(
        BarChartData(
          barGroups: [
            BarChartGroupData(
              x: 0,
              barRods: [
                BarChartRodData(
                  toY: income,
                  color: _accentGreen,
                  width: 20,
                  borderRadius: BorderRadius.circular(6),
                ),
                BarChartRodData(
                  toY: expense,
                  color: _expenseRed,
                  width: 20,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ),
          ],
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  Widget _buildDistributionPieContainer(double income, double expense) {
    final double total = income + expense;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(28),
      ),
      child: SizedBox(
        height: 200,
        child: PieChart(
          PieChartData(
            sections: [
              PieChartSectionData(
                value: income > 0 ? income : 1,
                color: _accentGreen,
                title: total > 0
                    ? '${((income / total) * 100).toStringAsFixed(0)}%'
                    : '0%',
                radius: 60,
                titleStyle: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              PieChartSectionData(
                value: expense > 0 ? expense : 1,
                color: _expenseRed,
                title: total > 0
                    ? '${((expense / total) * 100).toStringAsFixed(0)}%'
                    : '0%',
                radius: 60,
                titleStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            centerSpaceRadius: 45,
            sectionsSpace: 10,
          ),
        ),
      ),
    );
  }
}

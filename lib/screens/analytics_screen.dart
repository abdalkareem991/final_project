import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/supabase_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _supabaseService = SupabaseService();

  // --- Theme Colors ---
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
        title: const Text(
          "Analytics & Reports",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      // FutureBuilder is used here to fetch data and prevent errors
      body: FutureBuilder<Map<String, double>>(
        future: _supabaseService.getCategorySummary(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _accentGreen));
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text("Error loading data", style: TextStyle(color: Colors.white)),
            );
          }

          // Use real data from Supabase or default to 0.0
          final data = snapshot.data ?? {};
          final double totalIncome = data['Income'] ?? 0.0;
          final double totalExpenses = data['Expense'] ?? 0.0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildTimeFilters(),
                const SizedBox(height: 25),
                _buildStatCards(totalIncome, totalExpenses),
                const SizedBox(height: 25),
                _buildBarChartCard(totalIncome, totalExpenses),
                const SizedBox(height: 25),
                _buildCategoryDonutCard(totalIncome, totalExpenses),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- UI Components ---

  Widget _buildTimeFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ['Day', 'Week', 'Month', 'Year'].map((label) {
          bool isSelected = label == 'Month';
          return Container(
            margin: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) {},
              selectedColor: _accentGreen,
              backgroundColor: _cardColor,
              labelStyle: TextStyle(
                color: isSelected ? Colors.black : Colors.grey,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatCards(double income, double expense) {
    return Row(
      children: [
        _statItem("INCOME", "\$${income.toStringAsFixed(2)}", _accentGreen, Icons.trending_up),
        const SizedBox(width: 15),
        _statItem("EXPENSES", "\$${expense.toStringAsFixed(2)}", _expenseRed, Icons.trending_down),
      ],
    );
  }

  Widget _statItem(String label, String amount, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
            const SizedBox(height: 8),
            Text(
              amount,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Icon(icon, color: color.withValues(alpha: 0.5), size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChartCard(double income, double expense) {
    return Container(
      padding: const EdgeInsets.all(20),
      height: 300,
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Income vs Expenses",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: BarChart(
              BarChartData(
                backgroundColor: Colors.transparent,
                barGroups: _generateBarGroups(income, expense),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<BarChartGroupData> _generateBarGroups(double income, double expense) {
    // Creating bars based on actual data
    return List.generate(
      6,
      (i) => BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(toY: income > 0 ? income : 1.0, color: _accentGreen, width: 8),
          BarChartRodData(toY: expense > 0 ? expense : 1.0, color: Colors.blueGrey, width: 8),
        ],
      ),
    );
  }

  Widget _buildCategoryDonutCard(double income, double expense) {
    double total = income + expense;
    // Safety check to avoid division by zero
    double incomePercent = total > 0 ? (income / total) * 100 : 0;
    double expensePercent = total > 0 ? (expense / total) * 100 : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Financial Distribution",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(
                    value: income > 0 ? income : 1,
                    color: _accentGreen,
                    title: '${incomePercent.toStringAsFixed(0)}%',
                    radius: 50,
                    titleStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                  PieChartSectionData(
                    value: expense > 0 ? expense : 1,
                    color: _expenseRed,
                    title: '${expensePercent.toStringAsFixed(0)}%',
                    radius: 50,
                    titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
                centerSpaceRadius: 40,
                sectionsSpace: 5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
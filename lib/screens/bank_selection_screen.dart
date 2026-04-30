// lib/screens/bank_selection_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BankSelectionScreen extends StatefulWidget {
  const BankSelectionScreen({super.key});

  @override
  State<BankSelectionScreen> createState() => _BankSelectionScreenState();
}

class _BankSelectionScreenState extends State<BankSelectionScreen> {
  // 1. القائمة أصبحت متغيرة للسماح بالإضافة الديناميكية
  final List<Map<String, String>> _availableBanks = [
    {"name": "Arab Bank", "identifier": "ArabBank"},
    {"name": "Jordan Islamic Bank (JIB)", "identifier": "JIB"},
    {"name": "Housing Bank", "identifier": "HousingBank"},
    {"name": "Jordan Kuwait Bank", "identifier": "JKB"},
    {"name": "Etihad Bank", "identifier": "BankEtihad"},
    {"name": "Capital Bank", "identifier": "CapitalBank"},
  ];

  List<String> _selectedBanks = [];

  // الألوان المستخدمة في الهوية البصرية للتطبيق
  static const Color bgColor = Color(0xFF061414);
  static const Color cardColor = Color(0xFF111D1D);
  static const Color accentGreen = Color(0xFF34EAB9);

  @override
  void initState() {
    super.initState();
    _loadSelectedBanks();
  }

  Future<void> _loadSelectedBanks() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedBanks = prefs.getStringList('authorized_banks') ?? [];
    });
  }

  Future<void> _toggleBank(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_selectedBanks.contains(identifier)) {
        _selectedBanks.remove(identifier);
      } else {
        _selectedBanks.add(identifier);
      }
    });
    await prefs.setStringList('authorized_banks', _selectedBanks);
  }

  // --- دالة إظهار نافذة إضافة بنك جديد ---
  void _showAddBankDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController idController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Add Custom Bank",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration("Bank Name (e.g. JIB)"),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: idController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration("SMS Sender ID (e.g. JIB)"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              if (nameController.text.isNotEmpty &&
                  idController.text.isNotEmpty) {
                setState(() {
                  _availableBanks.add({
                    "name": nameController.text.trim(),
                    "identifier": idController.text.trim(),
                  });
                });
                Navigator.pop(context);
              }
            },
            child: const Text(
              "Add",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
    enabledBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: Colors.white10),
    ),
    focusedBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: accentGreen),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Bank Monitoring",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          // إضافة زر الإضافة في الـ AppBar
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: accentGreen),
            onPressed: _showAddBankDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Select banks to automate",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _availableBanks.length,
                itemBuilder: (context, index) {
                  final bank = _availableBanks[index];
                  final bool isSelected = _selectedBanks.contains(
                    bank['identifier'],
                  );

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: isSelected ? accentGreen : Colors.white10,
                        width: 1.5,
                      ),
                    ),
                    child: CheckboxListTile(
                      title: Text(
                        bank['name']!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        "ID: ${bank['identifier']}",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      value: isSelected,
                      activeColor: accentGreen,
                      checkColor: Colors.black,
                      onChanged: (val) => _toggleBank(bank['identifier']!),
                      secondary: Icon(
                        Icons.account_balance_wallet_outlined,
                        color: isSelected ? accentGreen : Colors.grey,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

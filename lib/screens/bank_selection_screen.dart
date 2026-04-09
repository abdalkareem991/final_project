// lib/screens/bank_selection_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BankSelectionScreen extends StatefulWidget {
  const BankSelectionScreen({super.key});

  @override
  State<BankSelectionScreen> createState() => _BankSelectionScreenState();
}

class _BankSelectionScreenState extends State<BankSelectionScreen> {
  // Pre-defined list of popular banks in Jordan for the user to choose from
  final List<Map<String, String>> _availableBanks = [
    {"name": "Arab Bank", "identifier": "ArabBank"},
    {"name": "Housing Bank", "identifier": "HousingBank"},
    {"name": "Jordan Kuwait Bank", "identifier": "JKB"},
    {"name": "Etihad Bank", "identifier": "BankEtihad"},
    {"name": "Capital Bank", "identifier": "CapitalBank"},
  ];

  List<String> _selectedBanks = [];

  @override
  void initState() {
    super.initState();
    _loadSelectedBanks(); // Load user preferences on screen startup
  }

  // Load the current authorized banks from SharedPreferences
  Future<void> _loadSelectedBanks() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedBanks = prefs.getStringList('authorized_banks') ?? [];
    });
  }

  // Save the updated list of authorized banks
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

  @override
  Widget build(BuildContext context) {
    // Using the app's established Neon-Dark theme colors
    const Color bgColor = Color(0xFF061414);
    const Color cardColor = Color(0xFF111D1D);
    const Color accentGreen = Color(0xFF34EAB9);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        title: const Text(
          "Bank Monitoring",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Select banks to monitor their SMS for automatic transactions:",
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 25),
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
                      value: isSelected,
                      activeColor: accentGreen,
                      checkColor: Colors.black,
                      onChanged: (val) => _toggleBank(bank['identifier']!),
                      secondary: Icon(
                        Icons.account_balance,
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

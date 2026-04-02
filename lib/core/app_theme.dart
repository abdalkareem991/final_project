import 'package:flutter/material.dart';

class AppTheme {
  // Define the Neon-Dark colors for Financial Mind
  static const Color backgroundColor = Color(0xFF0A0E21);
  static const Color accentColor = Color(0xFF00E676); // Neon Green
  static const Color surfaceColor = Color(0xFF161B33); // Card color

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: backgroundColor,
    primaryColor: accentColor,
    colorScheme: const ColorScheme.dark(
      primary: accentColor,
      surface: surfaceColor,
    ),
    // Standard font from your documentation
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontFamily: 'Times New Roman', // As requested in documentation
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
  );
}
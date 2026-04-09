// lib/services/ai_service.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class AIService {
  // Requirement: Secure your API Key (Use environment variables in production)
  final String _apiKey = "YOUR_GEMINI_API_KEY_HERE";
  late GenerativeModel _model;

  AIService() {
    // Initializing the Gemini Pro model
    _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
  }
  Future<Map<String, dynamic>?> parseBankSMS(String smsBody) async {
    try {
      final prompt = [
        Content.text("""
    Act as a financial data extractor. Analyze this SMS: "$smsBody"
    
    Extract into JSON:
    1. 'amount' (double)
    2. 'type' (Must be: 'Income', 'Expense', 'Transfer', or 'Hold')
    3. 'bank' (Bank name)
    4. 'status' (If message contains "Hold" or "Reserved", status is 'Pending', otherwise 'Final')
    
    Return ONLY JSON. Example: {"amount": 25.5, "type": "Expense", "bank": "Arab Bank", "status": "Final"}
    """),
      ];

      final response = await _model.generateContent(prompt);
      final text = response.text;

      // Logic to parse the string into a Map (simplification)
      if (text != null) {
        // Note: In production, use a proper JSON parser or regex to clean the AI response
        return _cleanAndParseJson(text);
      }
    } catch (e) {
      debugPrint("SMS AI Analysis Error: $e");
    }
    return null;
  }

  Map<String, dynamic>? _cleanAndParseJson(String text) {
    try {
      // Regular expression to find JSON content between curly braces
      final jsonRegex = RegExp(r'\{.*\}', dotAll: true);
      final match = jsonRegex.firstMatch(text);

      if (match != null) {
        final jsonString = match.group(0)!;
        return json.decode(jsonString) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint("Parsing Error: $e");
    }
    return null;
  }

  // Function to get financial advice based on user prompt
  Future<String> getFinancialAdvice(
    String userMessage,
    String financialContext,
  ) async {
    try {
      // Engineering Prompt: Giving the AI a "Personality" and "Context"
      final prompt = [
        Content.text("""
        You are 'FinMind AI', a professional financial assistant for Abdulkareem.
        User's Financial Context: $financialContext
        User Question: $userMessage
        Provide concise, professional, and helpful financial advice .
        """),
      ];

      final response = await _model.generateContent(prompt);
      return response.text ?? "I'm having trouble analyzing that right now.";
    } catch (e) {
      debugPrint("FinMind AI Error: $e");
      return "Connection error. Please check your internet.";
    }
  }
}

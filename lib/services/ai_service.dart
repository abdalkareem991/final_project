// lib/services/ai_service.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class AIService {
  // IMPORTANT: API Key should ideally be moved to an .env file for security
  final String _apiKey = "AIzaSyB3o37ExwfLr8dcI-KeJzU007-3h1IkBOE";
  late GenerativeModel _model;

  AIService() {
    // Initializing the Gemini 1.5 Flash model for fast and efficient processing
    _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
  }

  /// Extracts financial transaction data from a bank SMS string
  Future<Map<String, dynamic>?> parseBankSMS(String smsBody) async {
    try {
      final prompt = [
        Content.text("""
          Analyze this bank SMS: "$smsBody"
          
          CRITICAL: Return ONLY a raw JSON object. No markdown, no explanations.
          
          Required JSON Format:
          {
            "amount": double,
            "type": "Income" or "Expense",
            "bank": "Bank Name",
            "currency": "JOD",
            "isAutomated": true
          }
        """),
      ];

      final response = await _model.generateContent(prompt);
      final text = response.text;

      if (text != null) {
        debugPrint("🤖 AI Raw SMS Response: $text");
        return _cleanAndParseJson(text);
      }
    } catch (e) {
      debugPrint("❌ SMS AI Analysis Error: $e");
    }
    return null;
  }

  /// Cleans the AI response and ensures it is a valid JSON map
  Map<String, dynamic>? _cleanAndParseJson(String text) {
    try {
      // Find the JSON block using Regex to avoid issues with extra AI text
      final jsonRegex = RegExp(r'\{[\s\S]*\}');
      final match = jsonRegex.firstMatch(text);

      if (match != null) {
        final jsonString = match.group(0)!;
        final decoded = json.decode(jsonString) as Map<String, dynamic>;

        // Minimal validation to ensure essential fields exist
        if (decoded.containsKey('amount')) {
          return decoded;
        }
      }
    } catch (e) {
      debugPrint("❌ AI JSON Parsing Error: $e");
    }
    return null;
  }

  /// Provides financial advice based on the user message and their real-time financial context
  Future<String> getFinancialAdvice(
    String userMessage,
    String financialContext,
  ) async {
    try {
      final prompt = [
        Content.text("""
          You are 'FinMind AI', the professional financial strategist for Abdulkareem.
          
          Your Knowledge Base (User Context):
          $financialContext
          
          User Request: "$userMessage"
          
          Instructions:
          1. Be concise, professional, and supportive.
          2. Use the provided financial context (balances, expenses) to give specific advice.
          3. If the user asks to do something (like checking a budget), explain how you can help.
          4. Always respond in the language used by the user.
        """),
      ];

      final response = await _model.generateContent(prompt);
      return response.text ??
          "I'm sorry, I couldn't process that financial request.";
    } catch (e) {
      debugPrint("❌ FinMind AI Advice Error: $e");
      return "I'm currently having trouble connecting to my financial brain. Please check your internet.";
    }
  }

  /// Experimental: Detects if the user wants to perform an action (e.g., Add transaction)
  Future<Map<String, dynamic>?> detectUserIntent(String userMessage) async {
    try {
      final prompt = [
        Content.text("""
          Determine the user intent from this message: "$userMessage"
          Return a JSON: {"intent": "advice" | "transaction" | "report", "detected_amount": double?}
        """),
      ];
      final response = await _model.generateContent(prompt);
      return _cleanAndParseJson(response.text ?? "{}");
    } catch (e) {
      return null;
    }
  }
}

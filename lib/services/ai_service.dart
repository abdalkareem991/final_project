// lib/services/ai_service.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class AIService {
  // IMPORTANT: Ensure this API Key is active in Google AI Studio
  final String _apiKey = "AIzaSyB3o37ExwfLr8dcI-KeJzU007-3h1IkBOE";
  late GenerativeModel _model;

  AIService() {
    // FIXED: Using 'gemini-1.5-flash' without the 'models/' prefix
    // to match standard API implementation for generateContent
    _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);
  }

  /// Extracts the current available balance from a raw bank SMS string
  Future<double?> extractBalanceFromSMS(String smsBody) async {
    try {
      final prompt = [
        Content.text("""
          You are a financial data extractor. Analyze this SMS: "$smsBody"
          
          TASK: Find the "Available Balance" or "New Balance" after the transaction.
          
          CRITICAL: 
          1. Do NOT return the transaction amount (the money spent/received).
          2. Return ONLY the final current balance available in the account.
          3. Return ONLY a raw JSON object.
          
          Format:
          {
            "balance": double or null
          }
        """),
      ];

      final response = await _model.generateContent(prompt);
      final text = response.text;

      if (text != null) {
        debugPrint("🤖 AI Balance Extraction Response: $text");
        final jsonResult = _cleanAndParseJson(text);
        if (jsonResult != null && jsonResult.containsKey('balance')) {
          return (jsonResult['balance'] as num?)?.toDouble();
        }
      }
    } catch (e) {
      // Logic: Log error details for debugging API version issues
      debugPrint("❌ AI Balance Extraction Error: $e");
    }
    return null;
  }

  /// Parses bank SMS to extract transaction details for automated logging
  Future<Map<String, dynamic>?> parseBankSMS(String smsBody) async {
    try {
      final prompt = [
        Content.text("""
          Extract financial transaction data from this SMS: "$smsBody"
          
          CRITICAL: Return ONLY a raw JSON object. Do not include markdown code blocks.
          
          Required Format:
          {
            "amount": double,
            "type": "Income" or "Expense",
            "bank": "Bank Name",
            "status": "Final"
          }
        """),
      ];

      final response = await _model.generateContent(prompt);
      final text = response.text;

      if (text != null) {
        debugPrint("🤖 AI Transaction Parsing Response: $text");
        return _cleanAndParseJson(text);
      }
    } catch (e) {
      debugPrint("❌ SMS AI Analysis Error: $e");
    }
    return null;
  }

  /// Utility to clean AI response and parse JSON safely
  Map<String, dynamic>? _cleanAndParseJson(String text) {
    try {
      final jsonRegex = RegExp(r'\{[\s\S]*\}');
      final match = jsonRegex.firstMatch(text);

      if (match != null) {
        final jsonString = match.group(0)!;
        return json.decode(jsonString) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint("❌ AI JSON Parsing Error: $e");
    }
    return null;
  }

  /// Generates professional financial advice based on user context
  Future<String> getFinancialAdvice(
    String userMessage,
    String financialContext,
  ) async {
    try {
      final prompt = [
        Content.text("""
          You are 'FinMind AI', a professional financial assistant for Abdulkareem.
          Context: $financialContext
          Question: $userMessage
          Provide professional, concise, and actionable advice.
        """),
      ];

      final response = await _model.generateContent(prompt);
      return response.text ??
          "I'm having trouble analyzing your request right now.";
    } catch (e) {
      debugPrint("❌ FinMind AI Advice Error: $e");
      return "Connection error. Please check your internet or API key.";
    }
  }
}

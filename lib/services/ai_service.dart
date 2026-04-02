// lib/services/ai_service.dart

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
        Provide concise, professional, and helpful financial advice in English.
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

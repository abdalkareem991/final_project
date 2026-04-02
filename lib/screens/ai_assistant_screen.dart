// lib/screens/ai_assistant_screen.dart

import 'package:flutter/material.dart';
import '../services/ai_service.dart'; // Import the AI Logic
import '../services/supabase_service.dart'; // To fetch real balance for context

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({super.key});

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AIService _aiService = AIService(); // Initialize AI Service
  final SupabaseService _supabaseService = SupabaseService();

  final List<Map<String, dynamic>> _messages = [
    {
      "text": "Hello Abdulkareem! I'm your AI Financial Assistant. How can I help you today?",
      "isAI": true,
    },
  ];

  bool _isLoading = false;

  // --- Theme Colors ---
  static const Color _bgColor = Color(0xFF061414);
  static const Color _accentGreen = Color(0xFF34EAB9);
  static const Color _aiChatColor = Color(0xFF111D1D);

  // Scroll to bottom whenever a new message is added
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() async {
    if (_messageController.text.isEmpty || _isLoading) return;

    String userMessage = _messageController.text;
    _messageController.clear();

    setState(() {
      _messages.add({"text": userMessage, "isAI": false});
      _isLoading = true;
      // Add a temporary loading bubble
      _messages.add({"text": "Thinking...", "isAI": true});
    });
    _scrollToBottom();

    try {
      // Requirement: Fetch real data to give AI context
      final profile = await _supabaseService.getProfileData();
      String contextInfo = "User's current total balance is \$${profile.totalNetWorth}";

      // Logic: Get real response from Gemini API
      String aiResponse = await _aiService.getFinancialAdvice(userMessage, contextInfo);

      setState(() {
        _messages.removeLast(); // Remove "Thinking..."
        _messages.add({"text": aiResponse, "isAI": true});
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add({"text": "Sorry, I'm having trouble connecting. Check your API key.", "isAI": true});
        _isLoading = false;
      });
    }
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          "Ask AI Assistant",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Chat History with ScrollController
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildChatBubble(msg["text"], msg["isAI"]);
              },
            ),
          ),
          // Input Area
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String text, bool isAI) {
    return Align(
      alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(15),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isAI ? _aiChatColor : _accentGreen,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isAI ? 0 : 20),
            bottomRight: Radius.circular(isAI ? 20 : 0),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isAI ? Colors.white : Colors.black,
            fontSize: 15,
            fontStyle: text == "Thinking..." ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: _aiChatColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _sendMessage(),
              decoration: const InputDecoration(
                hintText: "Ask about your balance or advice...",
                hintStyle: TextStyle(color: Colors.grey),
                border: InputBorder.none,
              ),
            ),
          ),
          _isLoading 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _accentGreen))
            : IconButton(
                icon: const Icon(Icons.send, color: _accentGreen),
                onPressed: _sendMessage,
              ),
        ],
      ),
    );
  }
}
// lib/screens/ai_assistant_screen.dart

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import '../services/supabase_service.dart';

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({super.key});

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final AIService _aiService = AIService();
  final SupabaseService _supabaseService = SupabaseService();

  final List<Map<String, dynamic>> _messages = [];
  final List<Map<String, dynamic>> _chats = [];

  final List<String> _suggestions = [
    "Analyze my monthly spending",
    "Where does my income come from?",
    "Summarize my debts",
    "Give me a practical budget plan",
  ];

  bool _isLoading = false;
  bool _isLoadingChats = false;

  String _userName = "User";
  String? _currentChatId;

  static const Color _bgColor = Color(0xFF061414);
  static const Color _accentGreen = Color(0xFF34EAB9);
  static const Color _aiChatColor = Color(0xFF111D1D);

  @override
  void initState() {
    super.initState();
    _initializeChatScreen();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeChatScreen() async {
    await _loadUserName();

    if (!mounted) return;

    await _loadChats();

    if (!mounted) return;

    _startNewChatLocally();
  }

  Future<void> _loadUserName() async {
    try {
      final profile = await _supabaseService.getProfileData();

      if (!mounted) return;

      setState(() {
        _userName = profile.fullName.isNotEmpty ? profile.fullName : "User";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _userName = "User";
      });
    }
  }

  String _greetingMessage() {
    return "Hello $_userName! I'm your AI Financial Assistant. How can I help you today?";
  }

  Future<void> _loadChats() async {
    try {
      if (!mounted) return;

      setState(() {
        _isLoadingChats = true;
      });

      final chats = await _supabaseService.getAiChats();

      if (!mounted) return;

      setState(() {
        _chats
          ..clear()
          ..addAll(chats);

        _isLoadingChats = false;
      });
    } catch (e) {
      debugPrint("Load AI chats error: $e");

      if (!mounted) return;

      setState(() {
        _isLoadingChats = false;
      });
    }
  }

  void _startNewChatLocally() {
    if (!mounted) return;

    setState(() {
      _currentChatId = null;
      _messages
        ..clear()
        ..add({"text": _greetingMessage(), "isAI": true});
    });
  }

  Future<String> _ensureCurrentChat(String firstUserMessage) async {
    if (_currentChatId != null) {
      return _currentChatId!;
    }

    final title = _generateChatTitle(firstUserMessage);
    final chatId = await _supabaseService.createAiChat(title: title);

    _currentChatId = chatId;

    await _loadChats();

    return chatId;
  }

  String _generateChatTitle(String text) {
    final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (cleaned.isEmpty) {
      return "New Chat";
    }

    if (cleaned.length <= 35) {
      return cleaned;
    }

    return "${cleaned.substring(0, 35)}...";
  }

  Future<void> _loadChat(Map<String, dynamic> chat) async {
    final chatId = chat['id']?.toString();

    if (chatId == null || chatId.isEmpty) return;

    try {
      setState(() {
        _currentChatId = chatId;
        _messages.clear();
        _isLoading = true;
      });

      final messages = await _supabaseService.getAiMessages(chatId);

      if (!mounted) return;

      setState(() {
        _messages
          ..clear()
          ..addAll(
            messages.map((msg) {
              return {
                "text": msg['text']?.toString() ?? '',
                "isAI": msg['is_ai'] == true,
              };
            }),
          );

        if (_messages.isEmpty) {
          _messages.add({"text": _greetingMessage(), "isAI": true});
        }

        _isLoading = false;
      });

      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      _scrollToBottom();
    } catch (e) {
      debugPrint("Load AI chat messages error: $e");

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _messages.add({"text": "Could not load this chat.", "isAI": true});
      });
    }
  }

  Future<void> _deleteChat(Map<String, dynamic> chat) async {
    final chatId = chat['id']?.toString();

    if (chatId == null || chatId.isEmpty) return;

    try {
      await _supabaseService.deleteAiChat(chatId);

      if (!mounted) return;

      if (_currentChatId == chatId) {
        _startNewChatLocally();
      }

      await _loadChats();
    } catch (e) {
      debugPrint("Delete AI chat error: $e");
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final userMessage = _messageController.text.trim();

    if (userMessage.isEmpty || _isLoading) return;

    _messageController.clear();

    setState(() {
      _messages.add({"text": userMessage, "isAI": false});

      _isLoading = true;

      _messages.add({"text": "Thinking...", "isAI": true});
    });

    _scrollToBottom();

    String? chatId;

    try {
      chatId = await _ensureCurrentChat(userMessage);

      await _supabaseService.addAiMessage(
        chatId: chatId,
        text: userMessage,
        isAi: false,
      );

      final contextInfo = await _supabaseService.buildFinancialContextForAI();

      final aiResponse = await _aiService.getFinancialAdvice(
        userMessage,
        contextInfo,
      );

      await _supabaseService.addAiMessage(
        chatId: chatId,
        text: aiResponse,
        isAi: true,
      );

      if (!mounted) return;

      setState(() {
        if (_messages.isNotEmpty && _messages.last["text"] == "Thinking...") {
          _messages.removeLast();
        }

        _messages.add({"text": aiResponse, "isAI": true});

        _isLoading = false;
      });

      await _loadChats();
    } catch (e) {
      debugPrint("Send AI message error: $e");

      if (!mounted) return;

      const errorMessage =
          "AI connection is temporarily unstable. Please try again shortly.";

      setState(() {
        if (_messages.isNotEmpty && _messages.last["text"] == "Thinking...") {
          _messages.removeLast();
        }

        _messages.add({"text": errorMessage, "isAI": true});

        _isLoading = false;
      });

      if (chatId != null) {
        try {
          await _supabaseService.addAiMessage(
            chatId: chatId,
            text: errorMessage,
            isAi: true,
          );
        } catch (saveError) {
          debugPrint("Save AI error message failed: $saveError");
        }
      }
    }

    _scrollToBottom();
  }

  void _sendSuggestion(String text) {
    if (_isLoading) return;

    _messageController.text = text;
    _sendMessage();
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: _bgColor,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Chat History",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _startNewChatLocally();
                    },
                    icon: const Icon(Icons.add, color: _accentGreen),
                    tooltip: "New Chat",
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.add_comment, color: _accentGreen),
              title: const Text(
                "New Chat",
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _startNewChatLocally();
              },
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: _isLoadingChats
                  ? const Center(
                      child: CircularProgressIndicator(color: _accentGreen),
                    )
                  : _chats.isEmpty
                  ? const Center(
                      child: Text(
                        "No previous chats.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _chats.length,
                      itemBuilder: (context, index) {
                        final chat = _chats[index];
                        final chatId = chat['id']?.toString() ?? '';
                        final isSelected = chatId == _currentChatId;

                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _accentGreen.withOpacity(0.14)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.chat_bubble_outline,
                              color: isSelected ? _accentGreen : Colors.grey,
                              size: 20,
                            ),
                            title: Text(
                              chat['title']?.toString() ?? "New Chat",
                              style: TextStyle(
                                color: isSelected ? _accentGreen : Colors.white,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                                size: 19,
                              ),
                              onPressed: () async {
                                await _deleteChat(chat);
                              },
                            ),
                            onTap: () => _loadChat(chat),
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

  Widget _buildSuggestions() {
    if (_messages.length > 1 || _isLoading) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final suggestion = _suggestions[index];

          return ActionChip(
            label: Text(suggestion),
            backgroundColor: _aiChatColor,
            labelStyle: const TextStyle(color: _accentGreen),
            side: BorderSide(color: _accentGreen.withOpacity(0.4)),
            onPressed: () => _sendSuggestion(suggestion),
          );
        },
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
            fontStyle: text == "Thinking..."
                ? FontStyle.italic
                : FontStyle.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: _aiChatColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _sendMessage(),
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: "Ask about your finances...",
                hintStyle: TextStyle(color: Colors.grey),
                border: InputBorder.none,
              ),
            ),
          ),
          _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _accentGreen,
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.send, color: _accentGreen),
                  onPressed: _sendMessage,
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bgColor,
      drawer: _buildDrawer(),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text(
          "FinMind AI",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSuggestions(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];

                return _buildChatBubble(
                  msg["text"]?.toString() ?? '',
                  msg["isAI"] == true,
                );
              },
            ),
          ),
          SafeArea(top: false, child: _buildInputArea()),
        ],
      ),
    );
  }
}

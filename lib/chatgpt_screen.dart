import 'dart:convert';

import 'package:chatgpt_app/models/response.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? docId; // For Firebase document reference

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.docId,
  });

  // Convert Firestore document to ChatMessage
  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      text: data['text'] ?? '',
      isUser: data['isUser'] ?? false,
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      docId: doc.id,
    );
  }

  // Convert ChatMessage to Firestore format
  Map<String, dynamic> toFirestore() {
    return {
      'text': text,
      'isUser': isUser,
      'timestamp': Timestamp.fromDate(timestamp),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

// Firebase Service
class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Save individual message
  Future<void> saveChatMessage({
    required String text,
    required bool isUser,
    required DateTime timestamp,
  }) async {
    try {
      await _db.collection('chat_messages').add({
        'text': text,
        'isUser': isUser,
        'timestamp': Timestamp.fromDate(timestamp),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error saving to Firebase: $e');
      rethrow;
    }
  }

  // Load chat history
  Future<List<ChatMessage>> loadChatHistory() async {
    try {
      final snapshot = await _db
          .collection('chat_messages')
          .orderBy('timestamp', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => ChatMessage.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error loading chat history: $e');
      return [];
    }
  }

  // Stream chat history (real-time updates)
  Stream<List<ChatMessage>> streamChatHistory() {
    return _db
        .collection('chat_messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatMessage.fromFirestore(doc))
            .toList());
  }

  // Clear all history
  Future<void> clearHistory() async {
    try {
      final snapshot = await _db.collection('chat_messages').get();
      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('Error clearing history: $e');
      rethrow;
    }
  }
}

class ChatgptScreen extends StatefulWidget {
  const ChatgptScreen({super.key});

  @override
  State<ChatgptScreen> createState() => _ChatgptScreenState();
}

class _ChatgptScreenState extends State<ChatgptScreen> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseService _firebaseService = FirebaseService();
  List<ChatMessage> messages = [];
  late ResponseModel _responseModel;
  bool inputEnabled = true;
  bool isLoading = false;
  bool isLoadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }

  // Load chat history from Firebase
  Future<void> _loadChatHistory() async {
    setState(() {
      isLoadingHistory = true;
    });

    try {
      final history = await _firebaseService.loadChatHistory();
      setState(() {
        messages = history;
        isLoadingHistory = false;
      });

      // Show welcome message if no history
      if (messages.isEmpty) {
        Future.delayed(const Duration(milliseconds: 300), () {
          setState(() {
            messages.add(ChatMessage(
              text: "Pag ask na Kang Oblong",
              isUser: false,
              timestamp: DateTime.now(),
            ));
          });
        });
      }

      _scrollToBottom();
    } catch (e) {
      debugPrint('Error loading history: $e');
      setState(() {
        isLoadingHistory = false;
      });
    }
  }

  // Clear chat history
  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff2d2d2d),
        title: const Text(
          'Clear Chat History?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will delete all messages from Firebase. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _firebaseService.clearHistory();
        setState(() {
          messages.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat history cleared'),
            backgroundColor: Color(0xff667eea),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing history: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> completionFun() async {
    if (_promptController.text.trim().isEmpty) return;
    
    final dio = Dio();
    String prompt = _promptController.text.trim();
    DateTime promptTimestamp = DateTime.now();
    
    // Add user message
    final userMessage = ChatMessage(
      text: prompt,
      isUser: true,
      timestamp: promptTimestamp,
    );

    setState(() {
      messages.add(userMessage);
      inputEnabled = false;
      isLoading = true;
    });
    
    _promptController.clear();
    _scrollToBottom();

    // Save user message to Firebase
    try {
      await _firebaseService.saveChatMessage(
        text: prompt,
        isUser: true,
        timestamp: promptTimestamp,
      );
      debugPrint('✅ User message saved to Firebase');
    } catch (e) {
      debugPrint('❌ Firebase save error: $e');
    }
    
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      final errorMessage = ChatMessage(
        text: "Error: API key not found. Please check your .env file.",
        isUser: false,
        timestamp: DateTime.now(),
      );

      setState(() {
        messages.add(errorMessage);
        inputEnabled = true;
        isLoading = false;
      });

      await _firebaseService.saveChatMessage(
        text: errorMessage.text,
        isUser: false,
        timestamp: errorMessage.timestamp,
      );

      _scrollToBottom();
      return;
    }
    
    try {
      final response = await dio.post(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey',
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          contentType: "application/json",
          headers: {
            'Content-Type': 'application/json',
          },
        ),
        data: jsonEncode({
          "contents": [
            {
              "parts": [
                {
                  "text": prompt
                }
              ]
            }
          ],
        }),
      );
      
      FocusManager.instance.primaryFocus?.unfocus();
      
      setState(() {
        inputEnabled = true;
        isLoading = false;
        try {
          Map<String, dynamic>? responseJson = Map.from(response.data);
          _responseModel = ResponseModel.fromJson(responseJson);
          String responseText = _responseModel.choices?.content ?? "No response received.";
          
          final aiMessage = ChatMessage(
            text: responseText,
            isUser: false,
            timestamp: DateTime.now(),
          );

          messages.add(aiMessage);
          
          // Save AI response to Firebase
          _firebaseService.saveChatMessage(
            text: responseText,
            isUser: false,
            timestamp: aiMessage.timestamp,
          ).then((_) {
            debugPrint('✅ AI response saved to Firebase');
          }).catchError((error) {
            debugPrint('❌ Firebase save error: $error');
          });
          
          debugPrint(responseText);
        } catch (e) {
          debugPrint("Error parsing response: $e");
          final errorMessage = ChatMessage(
            text: "Error parsing response: $e",
            isUser: false,
            timestamp: DateTime.now(),
          );
          messages.add(errorMessage);

          _firebaseService.saveChatMessage(
            text: errorMessage.text,
            isUser: false,
            timestamp: errorMessage.timestamp,
          );
        }
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        inputEnabled = true;
        isLoading = false;
        debugPrint("API Error: $e");
        String errorText;
        if (e.toString().contains('401') || e.toString().contains('403')) {
          errorText = "Error: Invalid API key. Please check your .env file.";
        } else {
          errorText = "Error: Unable to connect. ${e.toString()}";
        }

        final errorMessage = ChatMessage(
          text: errorText,
          isUser: false,
          timestamp: DateTime.now(),
        );

        messages.add(errorMessage);

        _firebaseService.saveChatMessage(
          text: errorMessage.text,
          isUser: false,
          timestamp: errorMessage.timestamp,
        );
      });
      _scrollToBottom();
    }
  }

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

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xff212121),
              const Color(0xff1a1a2e),
              const Color(0xff16213e),
            ],
          ),
        ),
        child: Column(
          children: [
            // Custom AppBar with Clear History button
            Container(
              decoration: BoxDecoration(
                color: const Color(0xff2d2d2d).withOpacity(0.9),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xff667eea), Color(0xff764ba2)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xff667eea).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.mood,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Gemini Chat',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      // Clear History Button
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.white70,
                          size: 24,
                        ),
                        onPressed: messages.isEmpty ? null : _clearHistory,
                        tooltip: 'Clear History',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: isLoadingHistory
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xff667eea)),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Loading history...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(30),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xff667eea), Color(0xff764ba2)],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xff667eea).withOpacity(0.3),
                                      blurRadius: 30,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.mood,
                                  size: 80,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 32),
                              const Text(
                                'Start a conversation',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ask me anything!',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          itemCount: messages.length + (isLoading ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == messages.length) {
                              return const _LoadingIndicator();
                            }
                            return _MessageBubble(message: messages[index]);
                          },
                        ),
            ),
            _InputField(
              promptController: _promptController,
              btnFunc: completionFun,
              enabled: inputEnabled,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xff667eea), Color(0xff764ba2)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xff667eea).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.mood,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: message.isUser
                    ? const LinearGradient(
                        colors: [Color(0xff667eea), Color(0xff764ba2)],
                      )
                    : null,
                color: message.isUser ? null : const Color(0xff2d2d2d),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(22),
                  topRight: const Radius.circular(22),
                  bottomLeft: Radius.circular(message.isUser ? 22 : 6),
                  bottomRight: Radius.circular(message.isUser ? 6 : 22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: message.isUser
                        ? const Color(0xff667eea).withOpacity(0.3)
                        : Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 12),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xff444444),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.person,
                color: Colors.white,
                size: 22,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xff667eea), Color(0xff764ba2)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xff667eea).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.mood,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xff2d2d2d),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xff667eea)),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Ga overthink Pa...',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InputField extends StatefulWidget {
  final TextEditingController promptController;
  final Function btnFunc;
  final bool enabled;

  const _InputField({
    required this.promptController,
    required this.btnFunc,
    required this.enabled,
  });

  @override
  State<_InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<_InputField> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff2d2d2d).withOpacity(0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Form(
                  key: _formKey,
                  child: TextFormField(
                    cursorColor: const Color(0xff667eea),
                    enabled: widget.enabled,
                    controller: widget.promptController,
                    maxLines: null,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onFieldSubmitted: (value) {
                      if (_formKey.currentState?.validate() ?? false) {
                        widget.btnFunc();
                      }
                    },
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.0,
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: const Color(0xff3d3d3d),
                      hintText: "Type your message...",
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: Color(0xff667eea),
                          width: 2.5,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: Colors.red,
                          width: 1,
                        ),
                      ),
                      errorStyle: const TextStyle(
                        fontSize: 12.0,
                      ),
                    ),
                    validator: (String? value) {
                      if (value == null || value.trim().isEmpty) {
                        return "Please enter something";
                      }
                      return null;
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  gradient: widget.enabled
                      ? const LinearGradient(
                          colors: [Color(0xff667eea), Color(0xff764ba2)],
                        )
                      : null,
                  color: widget.enabled ? null : const Color(0xff555555),
                  shape: BoxShape.circle,
                  boxShadow: widget.enabled
                      ? [
                          BoxShadow(
                            color: const Color(0xff667eea).withOpacity(0.5),
                            blurRadius: 12,
                            spreadRadius: 1,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.enabled
                        ? () {
                            if (_formKey.currentState?.validate() ?? false) {
                              widget.btnFunc();
                            }
                          }
                        : null,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(12.0),
                      child: widget.enabled
                          ? const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 24,
                            )
                          : const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white70,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/room_location_model.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class KenemberloChatSheet extends StatefulWidget {
  const KenemberloChatSheet({super.key});

  @override
  State<KenemberloChatSheet> createState() => _KenemberloChatSheetState();
}

class _KenemberloChatSheetState extends State<KenemberloChatSheet> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isTyping = false;

  final List<ChatMessage> _messages = [
    ChatMessage(
      text:
          "Hello! I am Kenemerot Ask, your official ESSU campus location assistant. How may I assist you with campus directions today?",
      isUser: false,
      timestamp: DateTime.now(),
    ),
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _messageController.clear();
      _isTyping = true;
    });

    _scrollToBottom();
    _processDatabaseResponse(text);
  }

  String _stripEmojis(String text) {
    return text.replaceAll(
      RegExp(
        r'[\u{1F600}-\u{1F64F}'
        r'|\u{1F300}-\u{1F5FF}'
        r'|\u{1F680}-\u{1F6FF}'
        r'|\u{1F700}-\u{1F77F}'
        r'|\u{1F780}-\u{1F7FF}'
        r'|\u{1F800}-\u{1F8FF}'
        r'|\u{1F900}-\u{1F9FF}'
        r'|\u{1FA00}-\u{1FA6F}'
        r'|\u{1FA70}-\u{1FAFF}'
        r'|\u{2600}-\u{26FF}'
        r'|\u{2700}-\u{27BF}]',
        unicode: true,
      ),
      '',
    ).trim();
  }

  bool _isAmbiguousRoomQuery(String lower) {
    final genericRoom = RegExp(r'\broom\s+\d+[a-z]?\b');
    final hasBuildingClue = lower.contains('building') ||
        lower.contains('college') ||
        lower.contains('cota') ||
        lower.contains('cta') ||
        lower.contains('conas') ||
        lower.contains('col') ||
        lower.contains('library') ||
        lower.contains('lib') ||
        lower.contains('admin') ||
        lower.contains('engineering') ||
        lower.contains('ccs') ||
        lower.contains('coe') ||
        lower.contains('typhoon');

    return genericRoom.hasMatch(lower) && !hasBuildingClue;
  }

  Future<void> _processDatabaseResponse(String userQuery) async {
    final lowerQuery = userQuery.toLowerCase().trim();
    String responseText = "";

    await Future.delayed(const Duration(milliseconds: 500));

    if (lowerQuery == 'who are you' ||
        lowerQuery == 'who are you?' ||
        lowerQuery.contains('sino ka') ||
        lowerQuery == 'hi' ||
        lowerQuery == 'hello') {
      responseText =
          "I am Kenemerot Ask, the official location assistant for ESSU Main Campus. My knowledge is strictly limited to the information stored in our official campus database.";
    } else if (_isAmbiguousRoomQuery(lowerQuery)) {
      final roomNum =
          RegExp(r'\d+[a-z]?').firstMatch(lowerQuery)?.group(0) ?? '';
      responseText =
          "Could you please specify which building or college Room $roomNum is located in? I can only search for locations that are explicitly recorded in our campus records.";
    } else {
      try {
        final data = await _supabase.from('room_locations').select();
        final List<RoomLocation> locations = (data as List)
            .map((json) => RoomLocation.fromJson(json))
            .toList();

        final queryWords = lowerQuery
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .split(RegExp(r'\s+'))
            .where((w) => w.length >= 3)
            .toList();

        List<RoomLocation> matchedLocations = [];

        for (var location in locations) {
          final roomNameLower = location.roomName.toLowerCase();
          final bCodeLower = location.buildingCode.toLowerCase();
          final keywordsLower =
              location.keywords.map((k) => k.toLowerCase()).toList();

          bool isMatched = false;

          if (lowerQuery.contains(bCodeLower) ||
              lowerQuery.contains(roomNameLower)) {
            isMatched = true;
          }

          if (!isMatched) {
            for (var kw in keywordsLower) {
              if (lowerQuery.contains(kw) || kw.contains(lowerQuery)) {
                isMatched = true;
                break;
              }
              for (var word in queryWords) {
                if (kw.contains(word)) {
                  isMatched = true;
                  break;
                }
              }
              if (isMatched) break;
            }
          }

          if (isMatched) {
            matchedLocations.add(location);
          }
        }

        final roomMatch =
            RegExp(r'\broom\s+(\d+[a-z]?)\b').firstMatch(lowerQuery);
        if (roomMatch != null && matchedLocations.isEmpty) {
          final requestedRoomStr = roomMatch.group(0);

          String? targetBuilding;
          for (var loc in locations) {
            final bCode = loc.buildingCode.toLowerCase();
            if (lowerQuery.contains(bCode)) {
              targetBuilding = loc.buildingCode;
              break;
            }
          }

          if (targetBuilding != null) {
            responseText =
                "I apologize, but ${requestedRoomStr?.toUpperCase()} is not located in $targetBuilding according to our campus records.";
          } else {
            responseText =
                "I apologize, but I cannot find $requestedRoomStr in our database records.";
          }
        } else if (matchedLocations.isNotEmpty) {
          StringBuffer sb = StringBuffer();
          if (matchedLocations.length == 1) {
            final loc = matchedLocations.first;
            sb.writeln("Location: ${loc.roomName} (${loc.buildingCode})");
            sb.writeln("Directions: ${_stripEmojis(loc.directions)}");
          } else {
            sb.writeln(
                "Here are the matching locations found in our campus records:");
            sb.writeln();
            for (var loc in matchedLocations) {
              sb.writeln("• ${loc.roomName} [${loc.buildingCode}]:");
              sb.writeln("  ${_stripEmojis(loc.directions)}");
              sb.writeln();
            }
          }
          responseText = sb.toString().trim();
        } else {
          responseText =
              "I apologize, but I do not have information about that in my records. My knowledge is strictly limited to recorded campus locations.";
        }
      } catch (e) {
        debugPrint("Database Fetch Error: $e");
        responseText =
            "An error occurred while accessing campus records. Please check your network connection and try again.";
      }
    }

    if (!mounted) return;

    setState(() {
      _isTyping = false;
      _messages.add(ChatMessage(
        text: responseText,
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });

    _scrollToBottom();
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryHeaderColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFF0F5B33);
    final cardBgColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF1F5F9);
    final textPrimaryColor = isDark ? Colors.white : Colors.black87;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header - Kenemerot Ask (Matches Dark Mode Header Color)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            decoration: BoxDecoration(
              color: primaryHeaderColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.help_center_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kenemerot Ask',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'ESSU Room & Location Assistant',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Messages List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Align(
                  alignment:
                      msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: msg.isUser
                          ? const Color(0xFF0F5B33)
                          : cardBgColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
                        bottomRight: Radius.circular(msg.isUser ? 4 : 16),
                      ),
                    ),
                    child: Text(
                      msg.text,
                      style: TextStyle(
                        color: msg.isUser ? Colors.white : textPrimaryColor,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          if (_isTyping)
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Searching campus records...',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.grey,
                      fontStyle: FontStyle.italic),
                ),
              ),
            ),

          // Input Field Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: TextStyle(color: textPrimaryColor),
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText:
                            'Ask Kenemerot (e.g. Where is CPE department?)',
                        hintStyle: TextStyle(
                            color: isDark ? Colors.white38 : Colors.grey.shade400,
                            fontSize: 13),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFFF8FAF8),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                              color: isDark ? Colors.white12 : Colors.grey.shade300),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sendMessage,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF0F5B33),
                    ),
                    icon: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main_shell.dart';
import 'course_page.dart'; // --- IMPORTING THIS FILE NOW ---

// --- IMPORTANT ---
const String _apiKey = 'AIzaSyAhxy_gk0FYEnaxzVa5VH2OqABxhNLxk8s';


// --- Date Helpers (from GoalsTab) ---
String _periodOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
DateTime _monthStart(DateTime any) => DateTime(any.year, any.month, 1);
DateTime _monthEnd(DateTime any) => DateTime(any.year, any.month + 1, 0);
DateTime _dateKey(DateTime d) => DateTime(d.year, d.month, d.day);
// --- End Date Helpers ---

class AssistantTab extends StatefulWidget {
  const AssistantTab({super.key});

  @override
  State<AssistantTab> createState() => _AssistantTabState();
}

class _AssistantTabState extends State<AssistantTab> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  // --- Gemini AI Variables ---
  late final GenerativeModel _model;
  late final ChatSession _chat;
  // ---

  // --- App Data ---
  List<Course> _allCourses = []; // This will use the Course class from course_page.dart
  String? _userId;
  // ---

  bool _sending = false;

  final List<_ChatMessage> _messages = <_ChatMessage>[];

  @override
  void initState() {
    super.initState();

    _userId = FirebaseAuth.instance.currentUser?.uid;
    _ensureDefaultPet();

    // --- This is the new System Instruction Text ---
    // We are telling the AI to expect user data and to
    // return *categories* instead of specific courses.
    final systemInstructionText =
        "You are a helpful and expert financial assistant. "
        "You are a friendly financial assistant helping users manage money. "
        "You will receive a JSON summary of the user's budgets, goals, and spending. "
        "Then the user will ask a question. "
        "Your job: reply with short, warm advice under 100 words"
        "Only suggest courses when users asks for courses recommendations or courses suggestions"
        "Your response MUST be valid JSON with keys: 'reply' and 'suggested_categories'. "
        "The 'reply' key should contain your text-based advice, referencing the user's data where appropriate (e.g., 'I see you've spent X on Y...')."
        "The 'reply' is short advice, and 'suggested_categories' is an array of learning categories like "
        "['Budgeting', 'Investing', 'Investing', 'Planning']. "
        "Suggest courses according to user's requests. "
        "Only suggest courses that exists in the app. "
        "Choose categories based on what the user asks — for example, if they mention saving, suggest 'Budgeting' or 'Planning'.";
        "When a user asks for help, your 'reply' text should: "
        "1. Acknowledge their concern and be empathetic. "
        "2. Suggest 2-3 practical ways to control their budget, *using their provided financial summary*. "
        "3. Suggest a specific action for reducing their budget for the *next* month. "
        "Example response: "
        "{\"reply\": \"I see you've spent 800 on 'Food' this month, which is 200 over your budget. A good first step is...\", \"suggested_categories\": [\"Budgeting\", \"Planning\"]}";

    // --- Initialize Gemini ---
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _apiKey,
      systemInstruction: Content.system(systemInstructionText),
    );

    final greetingMessage = "Hello! I'm your financial assistant. "
        "I can help you with budgeting and suggest ways to manage overspending. "
        "How can I help you today?";

    // Start the chat session
    _chat = _model.startChat(
      history: [
        Content.model([
          TextPart(
              "{\"reply\": \"$greetingMessage\", \"suggested_categories\": []}")
        ]),
      ],
    );

    // Add the greeting to the UI
    _messages.add(
      _ChatMessage(
        text: greetingMessage,
        fromUser: false,
        courses: [],
      ),
    );

    // Fetch the app's courses from Firestore
    _loadCourses();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Fetches all courses from Firestore and stores them in _allCourses
  Future<void> _loadCourses() async {
    try {
      final snapshot =
      await FirebaseFirestore.instance.collection('courses').get();
      // This now works because Course.fromMap (from course_page.dart)
      // will use the Section class defined in that same file.
      final courses = snapshot.docs
          .map((doc) => Course.fromMap(doc.data(), doc.id))
          .toList();
      setState(() {
        _allCourses = courses;
      });
    } catch (e) {
      print("Error loading courses: $e");
      // Handle error, maybe show a snackbar
    }
  }

  Future<void> _ensureDefaultPet() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('userPet')
        .doc('current');
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'name': 'Mr. Kitty',
        'key': 'cat1',
        'asset': 'assets/pets/cat1.png',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }


  /// --- THIS IS THE IMPLEMENTED FUNCTION ---
  /// Fetches real financial data from Firestore
  Future<String> _getUserFinancialSummary() async {
    if (_userId == null) {
      return Future.value('{"error": "User not logged in"}');
    }

    // 1. Get Date helpers
    final now = DateTime.now();
    final periodKey = _periodOf(now);
    final monthStart = _monthStart(now);
    final monthEnd = _monthEnd(now);

    // 2. Define Firestore refs
    final userDoc =
    FirebaseFirestore.instance.collection('users').doc(_userId!);
    final budgetsCol = userDoc.collection('budgets');
    final goalsCol = userDoc.collection('goals');
    final txCol = userDoc.collection('transactions');

    try {
      // 3. Fetch data in parallel
      final results = await Future.wait([
        budgetsCol.where('period', isEqualTo: periodKey).get(),
        goalsCol.where('period', isEqualTo: periodKey).get(),
        txCol
            .where('date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(_dateKey(monthStart)))
            .where('date',
            isLessThanOrEqualTo: Timestamp.fromDate(_dateKey(monthEnd)))
            .get(),
      ]);

      // 4. Process data
      // Process Budgets
      final budgetsSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final budgets = budgetsSnap.docs.map((doc) {
        final data = doc.data();
        return {
          'label': data['label'],
          'category': data['category'],
          'amount': data['amount'],
        };
      }).toList();

      // Process Goals
      final goalsSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final goals = goalsSnap.docs.map((doc) {
        final data = doc.data();
        return {
          'label': data['label'],
          'category': data['category'],
          'goalAmount': data['goalAmount'],
        };
      }).toList();

      // Process Transactions (build spending map)
      final txSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
      final spendByCategory = <String, double>{};
      double totalSpending = 0;
      for (final d in txSnap.docs) {
        final data = d.data();
        final cats = (data['categories'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final amount = (data['amount'] ?? 0).toDouble();
        totalSpending += amount;
        if (cats.isEmpty) {
          spendByCategory['uncategorized'] =
              (spendByCategory['uncategorized'] ?? 0) + amount;
        } else {
          for (final c in cats) {
            final k = c.toLowerCase();
            spendByCategory[k] = (spendByCategory[k] ?? 0) + amount;
          }
        }
      }

      // 5. Build final summary object
      final summary = {
        'currentMonth': periodKey,
        'budgets': budgets,
        'goals': goals,
        'spendByCategory': spendByCategory,
        'totalSpending': totalSpending,
      };

      // 6. Return as JSON string
      return jsonEncode(summary);
    } catch (e) {
      print("Error fetching financial summary: $e");
      return jsonEncode(
          {"error": "Failed to fetch data", "details": e.toString()});
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, fromUser: true));
      _sending = true;
      _input.clear();
    });
    _scrollToBottom();

    try {
      // --- 1. Get user's financial data ---
      final financialSummary = await _getUserFinancialSummary();

      // --- 2. Send data + message to AI ---
      final prompt =
          "User financial summary: $financialSummary\n\nUser message: $text";
      final response = await _chat.sendMessage(Content.text(prompt));
      final botResponseText = response.text;

      if (botResponseText == null) {
        throw Exception("No response from the assistant.");
      }

      // --- 3. Parse the JSON response ---
      String cleanedResponse = botResponseText
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final jsonResponse = jsonDecode(cleanedResponse) as Map<String, dynamic>;
      final reply = jsonResponse['reply'] as String?;
      final categories =
          (jsonResponse['suggested_categories'] as List<dynamic>?)
              ?.cast<String>() ??
              [];

      if (reply == null) {
        throw Exception("Response missing 'reply' key.");
      }

      // --- 4. Filter REAL courses based on AI's suggested categories ---
      final List<Course> suggestedCourses = [];
      if (categories.isNotEmpty && _allCourses.isNotEmpty) {
        for (final category in categories) {
          // Check both long and short titles for the category
          final matchingCourses = _allCourses.where((course) =>
          course.longTitle.toLowerCase().contains(category.toLowerCase()) ||
              course.shortTitle.toLowerCase().contains(category.toLowerCase()) ||
              course.longTitle // Also check against the categories from GoalsTab
                  .toLowerCase()
                  .contains(category.toLowerCase()));
          suggestedCourses.addAll(matchingCourses);
        }
      }

      // --- 5. Add message to UI with REAL courses ---
      setState(() {
        _messages.add(_ChatMessage(
          text: reply,
          fromUser: false,
          courses: suggestedCourses.toSet().toList(), // Remove duplicates
        ));
      });
    } catch (e) {
      print("--- ASSISTANT TAB ERROR ---");
      print(e.toString());
      print("---------------------------");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send/process: $e')),
        );
        setState(() {
          _messages.add(_ChatMessage(
            text:
            'Hmm, I couldn’t reach the assistant just now. Check your API key or network and try again.',
            fromUser: false,
          ));
        });
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // ... (This build method is unchanged) ...
    final theme = Theme.of(context);

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(blurRadius: 8, color: Color(0x14000000))],
          ),
          width: double.infinity,
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline),
              const SizedBox(width: 8),
              Text('Assistant', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (_sending)
                const Padding(
                  padding: EdgeInsets.only(right: 8.0),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: Container(
            color: const Color(0xFFF6F7F9),
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                return _ChatBubble(
                  message: m,
                  isFirstOfGroup:
                  i == 0 || _messages[i - 1].fromUser != m.fromUser,
                );
              },
            ),
          ),
        ),

        // Composer
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(
                left: 12, right: 12, bottom: 12, top: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Ask about your finances…',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFDADDE2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFDADDE2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFF264E3C)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---
// DATA MODELS
// ---

// --- DELETED: The duplicate 'Course' class was here. It is now gone. ---
// It is imported from 'course_page.dart'

class _ChatMessage {
  _ChatMessage({
    required this.text,
    required this.fromUser,
    this.courses,
  });

  final String text;
  final bool fromUser;
  // --- UPDATED ---
  // Now uses the strong Course type (from course_page.dart)
  final List<Course>? courses;
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.isFirstOfGroup,
  });

  final _ChatMessage message;
  final bool isFirstOfGroup;

  @override
  Widget build(BuildContext context) {
    final isUser = message.fromUser;

    // Visuals
    final bubbleColor = isUser ? const Color(0xFF264E3C) : Colors.white;
    final textColor = isUser ? Colors.white : const Color(0xFF1B1E23);

    // Bubble widget (shared)
    Widget bubble = Container(
      margin: EdgeInsets.only(left: isUser ? 48 : 0, right: isUser ? 0 : 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(isUser ? 14 : 4),  // slight "tail"
          bottomRight: Radius.circular(isUser ? 4 : 14), // slight "tail"
        ),
        boxShadow: isUser
            ? null
            : [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
        border: isUser ? null : Border.all(color: const Color(0xFFE6E9EE)),
      ),
      child: Text(
        message.text,
        style: TextStyle(color: textColor, height: 1.35),
      ),
    );

    // Row layout:
    // - Assistant: [pet][gap][bubble]
    // - User:                [bubble] (right aligned)
    return Column(
      crossAxisAlignment:
      isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (isFirstOfGroup) const SizedBox(height: 6),
        Row(
          mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              const UserPetAvatar(size: 40), // small pet icon
              const SizedBox(width: 6),
            ],
            Flexible(child: bubble),
          ],
        ),

        // Course suggestions under assistant bubbles (unchanged)
        if (!isUser && (message.courses?.isNotEmpty ?? false))
          _CourseSuggestions(courses: message.courses!),

        const SizedBox(height: 8),
      ],
    );
  }

}

// --- UPDATED ---
// This widget now uses the strong Course type,
// which makes the code much cleaner.
class _CourseSuggestions extends StatelessWidget {
  const _CourseSuggestions({required this.courses});
  final List<Course> courses;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(
          top: 6, left: 8, right: 48), // align under assistant bubble
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE6E9EE)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text('Suggested courses',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const Divider(height: 1),
          ...courses.take(10).map((course) {
            // We can now directly access properties
            final title = course.shortTitle;
            final sub = '${course.author} • ${course.duration}';

            return ListTile(
              dense: true,
              title: Text(title),
              subtitle: Text(sub),
              leading: const Icon(Icons.menu_book_outlined),
                onTap: () {
                  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => MainShell(
                        initialIndex: 0,                    // Courses tab
                        highlightCourseId: course.id,       // which course
                        openCourseImmediately: true,        // let CoursePage open it right away
                      ),
                    ),
                        (route) => false,
                  );

                }

            );
          }).toList(),
        ],
      ),
    );
  }
}


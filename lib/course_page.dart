import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum QuizMode { playing, result, review }

/// Course model with sections
class Course {
  final String id;
  final String shortTitle;
  final String longTitle;
  final String author;
  final String duration;
  final bool hasQuiz;
  final List<Section> sections;

  Course({
    required this.id,
    required this.shortTitle,
    required this.longTitle,
    required this.author,
    required this.duration,
    required this.hasQuiz,
    required this.sections,
  });

  factory Course.fromMap(Map<String, dynamic> data, String docId) {
    return Course(
      id: docId,
      shortTitle: data['shortTitle'] ?? '',
      longTitle: data['longTitle'] ?? '',
      author: data['author'] ?? '',
      duration: data['duration'] ?? '',
      hasQuiz: data['hasQuiz'] ?? false,
      sections: (data['sections'] as List<dynamic>? ?? [])
          .map((s) => Section.fromMap(s))
          .toList(),
    );
  }
}

class Section {
  final String title;
  final String content;

  Section({required this.title, required this.content});

  factory Section.fromMap(Map<String, dynamic> data) {
    return Section(
      title: data['title'] ?? '',
      content: data['content'] ?? '',
    );
  }
}

class QuizQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;

  QuizQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
  });

  factory QuizQuestion.fromMap(Map<String, dynamic> data) {
    final rawIndex = data['correctIndex'];
    return QuizQuestion(
      question: data['question'] ?? '',
      options: (data['options'] as List<dynamic>? ?? []).cast<String>(),
      correctIndex:
      rawIndex is int ? rawIndex : int.tryParse(rawIndex.toString()) ?? 0,
    );
  }
}

class CoursePage extends StatefulWidget {
  final String? highlightCourseId;
  final bool openCourseImmediately;

  const CoursePage({
    super.key,
    this.highlightCourseId,
    this.openCourseImmediately = false,
  });

  @override
  State<CoursePage> createState() => _CoursePageState();
}

/// Reusable tile for course rows used across the app (Courses/Home/Assistant).
class CourseListTile extends StatelessWidget {
  const CourseListTile({
    super.key,
    required this.course,
    required this.onTap,
    required this.isFavouriteFuture,
    required this.onToggleFavourite, required bool isFD,
  });

  final Course course;
  final VoidCallback onTap;

  /// Provide a future that returns whether this course is favourited.
  final Future<bool> Function(String courseId) isFavouriteFuture;

  /// Called to toggle favourite for this course.
  final Future<void> Function(String courseId) onToggleFavourite;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF355E47),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Texts
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.shortTitle,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  Text("By ${course.author}",
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(
                    course.hasQuiz ? "Quiz included" : "No Quiz",
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.yellow,
                    ),
                  ),
                ],
              ),
            ),

            // Fav + duration
            Column(
              children: [
                FutureBuilder<bool>(
                  future: isFavouriteFuture(course.id),
                  builder: (context, snapshot) {
                    final isFav = snapshot.data ?? false;
                    return IconButton(
                      icon: Icon(
                        isFav ? Icons.star : Icons.star_border,
                        color: Colors.orange,
                      ),
                      onPressed: () => onToggleFavourite(course.id),
                    );
                  },
                ),
                Text(
                  course.duration,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}



class UserPetAvatar extends StatelessWidget {
  final double size; // circle size
  const UserPetAvatar({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('userPet')
          .doc('current')
          .snapshots(),
      builder: (context, snap) {
        // Until we know the asset, show nothing to avoid flashing a fallback
        if (!snap.hasData || !snap.data!.exists) {
          return SizedBox(width: size, height: size);
        }

        final data = snap.data!.data();
        final a = (data?['asset'] ?? '').toString().trim();
        if (a.isEmpty) {
          return SizedBox(width: size, height: size);
        }

        // Render the real pet as soon as we have it
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(
              image: AssetImage(a),
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}

class _CoursePageState extends State<CoursePage> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _courseKeys = {};
  bool _didScroll = false;

  bool _isFixedDepositTitle(String t) {
    final s = t.trim().toLowerCase();
    return s.contains('fixed deposit');
  }


  String? _selectedCategory; // null = all
  bool _showFavoritesOnly = false;
  Course? _activeCourse; // for sheet

  // Quiz state
  bool _inQuiz = false;
  QuizMode _quizMode = QuizMode.playing;
  List<QuizQuestion> _quiz = [];
  int _qIndex = 0;
  int? _selectedOption;
  int _score = 0;
  bool _loadingQuiz = false;

  // Choices per question (for review)
  List<int?> _answers = [];

  // Feedback
  bool _showingFeedback = false; // true for 1s after an answer
  bool _locked = false; // ignore taps while showing feedback
  String _bubble = "First question. We can do this!";

  final TextEditingController _searchController = TextEditingController();
  final List<String> _categories = ["Budgeting", "Investing", "Banking", "Planning"];

  // Coin awarding (per run)
  bool _coinsAwardedThisRun = false;
  int _coinsEarnedThisRun = 0;

  /// Get courses from Firestore
  Stream<List<Course>> getCourses() {
    return FirebaseFirestore.instance
        .collection('courses')
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => Course.fromMap(doc.data(), doc.id)).toList());
  }

  /// Fetch quiz (array field `quizzes` on course doc)
  Future<List<QuizQuestion>> _fetchQuizForCourse(String courseId) async {
    final snap = await FirebaseFirestore.instance
        .collection('courses')
        .doc(courseId)
        .get();
    final data = snap.data();
    final List<dynamic> raw = (data?['quizzes'] as List<dynamic>? ?? []);
    return raw
        .map((m) => QuizQuestion.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Ensure user doc has `pet_coins` (default 0) without overwriting existing
  Future<void> _ensurePetCoinsField() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await userRef.get();

    if (!snap.exists) {
      await userRef.set({'pet_coins': 0}, SetOptions(merge: true));
      return;
    }

    final data = snap.data() as Map<String, dynamic>? ?? {};
    if (!data.containsKey('pet_coins')) {
      await userRef.set({'pet_coins': 0}, SetOptions(merge: true));
    }
  }

  /// Award coins with a per-quiz cap = total number of questions.
  /// Increments only the REMAINING coins not yet earned for this quiz.
  /// Stores per-quiz progress at `users/{uid}/quizProgress/{courseId}.earnedCoins`.
  /// Returns the number of coins actually awarded this run.
  Future<int> _awardCoinsWithCap({
    required String courseId,
    required int score,
    required int totalQuestions,
  }) async {
    if (_coinsAwardedThisRun) return 0; // guard

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final progressRef = userRef.collection('quizProgress').doc(courseId);

    int awarded = 0;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      // Ensure user doc + pet_coins
      final userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        tx.set(userRef, {'pet_coins': 0}, SetOptions(merge: true));
      } else {
        final udata = (userSnap.data() ?? {}) as Map<String, dynamic>;
        if (udata['pet_coins'] == null) {
          tx.set(userRef, {'pet_coins': 0}, SetOptions(merge: true));
        }
      }

      // Read current progress for this quiz
      final progSnap = await tx.get(progressRef);
      final already = (progSnap.data()?['earnedCoins'] ?? 0) as int;
      final cap = totalQuestions;

      // Desired earned after this attempt (cannot exceed cap)
      final desiredAfter = (already + score).clamp(0, cap);
      awarded = desiredAfter - already; // could be 0

      if (awarded > 0) {
        tx.set(
          userRef,
          {'pet_coins': FieldValue.increment(awarded)},
          SetOptions(merge: true),
        );
        tx.set(
          progressRef,
          {
            'earnedCoins': desiredAfter,
            'maxCoins': cap,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });

    _coinsAwardedThisRun = true;
    return awarded;
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

  Future<void> _startQuiz(Course course) async {
    setState(() => _loadingQuiz = true);
    try {
      final q = await _fetchQuizForCourse(course.id);

      // If no quiz → stay in article mode
      if (q.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No quiz found for this course')),
          );
        }
        setState(() {
          _inQuiz = false;
          _quiz = const [];
          _quizMode = QuizMode.playing;
        });
        return;
      }

      // Otherwise start quiz
      setState(() {
        _quiz = q;
        _qIndex = 0;
        _selectedOption = null;
        _score = 0;
        _inQuiz = true;
        _quizMode = QuizMode.playing;

        _answers = List<int?>.filled(q.length, null);

        _showingFeedback = false;
        _locked = false;
        _bubble = "First question. We can do this!";

        _coinsAwardedThisRun = false;
        _coinsEarnedThisRun = 0;
      });
    } finally {
      setState(() => _loadingQuiz = false);
    }
  }

  void _exitQuizToArticle() {
    setState(() {
      _inQuiz = false;
      _quizMode = QuizMode.playing;
      _selectedOption = null;
      _showingFeedback = false;
      _locked = false;
    });
  }

  // Tap handler: show red/green, change bubble, then auto-next in 1s or go to RESULT
  void _onOptionTap(int i) {
    if (_locked || _quiz.isEmpty || _quizMode != QuizMode.playing) return;
    final q = _quiz[_qIndex];
    final correct = i == q.correctIndex;

    // Record answer for review
    _answers[_qIndex] = i;

    setState(() {
      _selectedOption = i;
      _showingFeedback = true;
      _locked = true;
      if (correct) _score++;
      _bubble = correct ? "Yayyy! You got the answer" : "Oh noo... We got it wrong";
    });

    Future.delayed(const Duration(seconds: 1), () async {
      if (!mounted) return;
      if (_qIndex < _quiz.length - 1) {
        setState(() {
          _qIndex++;
          _selectedOption = null;
          _showingFeedback = false;
          _locked = false;
          _bubble = "Here comes the next one!";
        });
      } else {
        // finished -> results page
        setState(() {
          _quizMode = QuizMode.result;
          _showingFeedback = false;
          _locked = false;
        });

        // Award capped coins exactly once after finishing
        final active = _activeCourse; // guard for null
        if (active != null) {
          final earned = await _awardCoinsWithCap(
            courseId: active.id,
            score: _score,
            totalQuestions: _quiz.length,
          );
          if (mounted) {
            setState(() {
              _coinsEarnedThisRun = earned; // show in UI
            });
          }
        }
      }
    });
  }

  /// Toggle favourite in Firestore
  Future<void> _toggleFavorite(String courseId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snapshot = await userDoc.get();
    List favourites = snapshot.data()?['favourites'] ?? [];

    if (favourites.contains(courseId)) {
      await userDoc.update({'favourites': FieldValue.arrayRemove([courseId])});
    } else {
      await userDoc.update({'favourites': FieldValue.arrayUnion([courseId])});
    }
  }

  /// Check if course is favourited
  Future<bool> _isFavourite(String courseId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final snapshot =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

    List favourites = snapshot.data()?['favourites'] ?? [];
    return favourites.contains(courseId);
  }

  void _openCourse(Course course) {
    setState(() {
      _activeCourse = course;
    });
  }

  Widget _buildChip(String text, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = isSelected ? null : text;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: isSelected
              ? Border.all(color: const Color(0xFF2B8761), width: 2)
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isSelected ? const Color(0xFF2B8761) : const Color(0xFF858597),
          ),
        ),
      ),
    );
  }


  // ---------- QUIZ VIEWS ----------

  Widget _buildQuizView(ScrollController scrollController) {
    final total = _quiz.length;
    if (total == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'No quiz found for this course.',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    final q = _quiz[_qIndex];
    final current = _qIndex + 1;


    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: _exitQuizToArticle,
              ),
              Expanded(
                child: Text(
                  'Question $current/$total',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 12),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: current / total,
              minHeight: 8,
              backgroundColor: Colors.white24,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // Speech bubble + pet
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(15),
                      topRight: Radius.circular(15),
                      bottomLeft: Radius.circular(15),
                      bottomRight: Radius.circular(0),
                    ),
                  ),
                  child: Text(
                    _bubble,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.black,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const UserPetAvatar(size: 90),
            ],
          ),
          const SizedBox(height: 16),

          // Question card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6F1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                q.question,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF214235),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Options with feedback colors
          ...List.generate(q.options.length, (i) {
            // Colors
            const defaultBg = Color(0xFF2F5643);
            const selectedBg = Color(0xFF466F5A);
            const correctBg = Color(0xFF78C850); // green
            const wrongBg = Color(0xFFE04F5F);   // red

            Color bg;
            if (_showingFeedback) {
              if (i == q.correctIndex) {
                bg = correctBg;          // correct answer in green
              } else if (_selectedOption == i) {
                bg = wrongBg;            // chosen wrong option in red
              } else {
                bg = defaultBg;          // others stay dim
              }
            } else {
              bg = _selectedOption == i ? selectedBg : defaultBg;
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => _onOptionTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 4,
                        offset: const Offset(2, 2),
                      )
                    ],
                  ),
                  child: Text(
                    q.options[i],
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }


  @override
  void initState() {
    super.initState();
    _ensureDefaultPet();
    _ensurePetCoinsField();
  }

  Widget _buildResultView(ScrollController scrollController) {
    final total = _quiz.length;
    final ratio = total == 0 ? 0.0 : _score / total;
    int stars = 1;
    if (ratio == 1.0) {
      stars = 3;
    } else if (ratio > 0.5) {
      stars = 2;
    } else {
      stars = 1;
    }

    Widget star(int index) {
      final filled = index <= stars;
      return Icon(
        Icons.star,
        size: 28,
        color: filled ? const Color(0xFFFFD54F) : Colors.white30,
      );
    }

    return SingleChildScrollView(
      controller: scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Close button
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _exitQuizToArticle,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Nice Work",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 24,
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Image.asset(
            'assets/big-check.png',
            height: 110,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 16),

          // Stars
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              star(1),
              const SizedBox(width: 8),
              star(2),
              const SizedBox(width: 8),
              star(3)
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$_score/$total Correct!',
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 16, color: Colors.white),
          ),
          const SizedBox(height: 16),

          // Reward bubble (dynamic)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE7DAF5).withOpacity(.7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _coinsEarnedThisRun > 0
                  ? "Wow! You’ve Earned $_coinsEarnedThisRun Pet Coins!\nLet's read more to earn more coins!"
                  : "You're already at the max for this quiz.\nGreat consistency—keep learning!",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFF2A2A2A),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Review Answer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => setState(() => _quizMode = QuizMode.review),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8A5B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 18),
                  textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
                child: const Text("Review Answer"),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Play Again
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _quizMode = QuizMode.playing;
                    _qIndex = 0;
                    _score = 0;
                    _answers = List<int?>.filled(_quiz.length, null);
                    _selectedOption = null;
                    _showingFeedback = false;
                    _locked = false;
                    _bubble = "First question. We can do this!";
                    _coinsAwardedThisRun = false;
                    _coinsEarnedThisRun = 0;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8AD03D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 18),
                  textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
                child: const Text("Play Again"),
              ),
            ),
          ),

          const SizedBox(height: 18),
        ],
      ),
    );
  }
  Widget _buildReviewView(ScrollController scrollController) {
    return SingleChildScrollView(
      controller: scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Close
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _exitQuizToArticle,
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),

          // Bubble
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6F8D7E),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    "Let's review our answers",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const UserPetAvatar(size: 64),
            ],
          ),
          const SizedBox(height: 16),

          ...List.generate(_quiz.length, (idx) {
            final q = _quiz[idx];
            final chosen = _answers[idx];
            final correctIdx = q.correctIndex;
            final isCorrect = chosen == correctIdx;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF6E9C7F),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Question
                  Text(
                    q.question,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 10),

                  // Your choice (if wrong show red X + text)
                  if (chosen != null && !isCorrect)
                    Row(
                      children: [
                        const Icon(Icons.close, color: Color(0xFFE04F5F)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            q.options[chosen],
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Color(0xFFE04F5F),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (chosen != null && !isCorrect) const SizedBox(height: 6),

                  // Correct answer (green check)
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF78C850)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          q.options[correctIdx],
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Color(0xFFCBF1CB),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          // Play Again button at bottom
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _quizMode = QuizMode.playing;
                    _qIndex = 0;
                    _score = 0;
                    _answers = List<int?>.filled(_quiz.length, null);
                    _selectedOption = null;
                    _showingFeedback = false;
                    _locked = false;
                    _bubble = "First question. We can do this!";
                    _coinsAwardedThisRun = false;
                    _coinsEarnedThisRun = 0;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8AD03D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 18),
                  textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
                child: const Text("Play Again"),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------- BUILD ----------

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF8EBB87),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser!.uid)
              .snapshots(),
          builder: (context, favSnapshot) {
            if (!favSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final authUser = FirebaseAuth.instance.currentUser;
            final data = favSnapshot.data!.data() ?? {};

            // User's favourites (live)
            final List favs = (data['favourites'] as List?) ?? [];

            // Resolve name (Firestore first, then fallbacks)
            String userName = '';
            for (final key in ['firstName', 'first_name', 'firstname']) {
              final v = (data[key] ?? '').toString().trim();
              if (v.isNotEmpty) {
                userName = v;
                break;
              }
            }
            if (userName.isEmpty) {
              final full = (data['name'] ?? data['username'] ?? authUser?.displayName ?? '')
                  .toString()
                  .trim();
              if (full.isNotEmpty) {
                userName = full.split(' ').first; // "Jane Doe" -> "Jane"
              } else {
                userName = (authUser?.email?.split('@').first ?? 'there');
              }
            }

            return StreamBuilder<List<Course>>(
              stream: getCourses(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allCourses = snapshot.data!;
                final q = _searchController.text.trim().toLowerCase();

                // Filter courses
                final filtered = allCourses.where((c) {
                  if (_selectedCategory != null &&
                      !c.longTitle.toLowerCase().contains(_selectedCategory!.toLowerCase())) {
                    return false;
                  }
                  if (_showFavoritesOnly && !favs.contains(c.id)) {
                    return false;
                  }
                  if (q.isNotEmpty &&
                      !c.shortTitle.toLowerCase().contains(q) &&
                      !c.longTitle.toLowerCase().contains(q)) {
                    return false;
                  }
                  return true;
                }).toList();

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_didScroll || widget.highlightCourseId == null) return;

                  // 1) Find the course in the CURRENT filtered list
                  final int idx = filtered.indexWhere((c) => c.id == widget.highlightCourseId);
                  if (idx < 0) return; // not visible under current filters

                  _didScroll = true;
                  final course = filtered[idx];

                  // 2) Try precise scroll first (needs the keyed widget to be built)
                  final key = _courseKeys[course.id];
                  if (key?.currentContext != null) {
                    Scrollable.ensureVisible(
                      key!.currentContext!,
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOut,
                    );
                  } else {
                    // 3) Fallback: approximate scroll using controller (card ~150px tall)
                    const double approxItemExtent = 150;
                    _scrollController.animateTo(
                      idx * approxItemExtent,
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOut,
                    );
                  }

                  // 4) Auto-open the bottom sheet if requested
                  if (widget.openCourseImmediately) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _activeCourse = course);
                    });
                  }
                });

                return Stack(
                  children: [
                    SingleChildScrollView(
                      controller: _scrollController, // ← attach so animateTo() works
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Search bar + star filter
                          Container(
                            height: 45,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.search, color: Colors.grey),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    decoration: const InputDecoration(
                                      hintText: "Search for courses",
                                      border: InputBorder.none,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    _showFavoritesOnly ? Icons.star : Icons.star_border,
                                    color: Colors.orange,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _showFavoritesOnly = !_showFavoritesOnly;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Category chips
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: _categories.map((cat) {
                              final isSelected = _selectedCategory == cat;
                              return Row(
                                children: [
                                  _buildChip(cat, isSelected),
                                  const SizedBox(width: 8),
                                ],
                              );
                            }).toList(),
                          ),

                          // Pet bubble on main list
                          const SizedBox(height: 12),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Bubble (left)
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(16),
                                      topRight: Radius.circular(16),
                                      bottomLeft: Radius.circular(16),
                                      bottomRight: Radius.circular(0),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 6,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    "Hi $userName!\nLets find some courses and learn to earn together!",
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      height: 1.35,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(width: 12),

                              // Big pet (right)
                              const Padding(
                                padding: EdgeInsets.only(top: 30),
                                child: UserPetAvatar(size: 96),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          const SizedBox(height: 24),
                          const Text(
                            "Recommended for you",
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (filtered.isEmpty)
                            const Text("No courses found.", style: TextStyle(color: Colors.white70))
                          else
                            Column(
                              children: filtered.map((course) {
                                final bool isFD = _isFixedDepositTitle(course.shortTitle);
                                return CourseListTile(
                                  course: course,
                                  isFD: isFD,
                                  onTap: () => _openCourse(course),
                                  isFavouriteFuture: (id) => _isFavourite(id),
                                  onToggleFavourite: (id) async {
                                    await _toggleFavorite(id);
                                    if (mounted) setState(() {}); // refresh stars
                                  },
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),

                    // --- backdrop: tap outside to close ---
                    if (_activeCourse != null)
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () => setState(() => _activeCourse = null),
                          child: Container(color: Colors.black26), // dim background
                        ),
                      ),

                    // Draggable sheet for active course
                    if (_activeCourse != null)
                      DraggableScrollableSheet(
                        initialChildSize: 0.9,
                        minChildSize: 0.0, // allow full collapse
                        maxChildSize: 0.95,
                        builder: (context, scrollController) {
                          final course = _activeCourse!;
                          final bool isFD = _isFixedDepositTitle(course.shortTitle);

                          return NotificationListener<DraggableScrollableNotification>(
                            onNotification: (n) {
                              // auto-dismiss when nearly collapsed
                              if (n.extent <= 0.05 && _activeCourse != null) {
                                setState(() => _activeCourse = null);
                              }
                              return false;
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: const BoxDecoration(
                                color: Color(0xFF355E47),
                                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                              ),
                              child: !_inQuiz
                                  ? SingleChildScrollView(
                                controller: scrollController,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // drag handle
                                    Center(
                                      child: Container(
                                        width: 44,
                                        height: 5,
                                        margin: const EdgeInsets.only(bottom: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.white24,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                      ),
                                    ),

                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                                          onPressed: () => setState(() => _activeCourse = null),
                                        ),
                                        Expanded(
                                          child: Text(
                                            course.longTitle,
                                            style: const TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        Column(
                                          children: [
                                            FutureBuilder<bool>(
                                              future: _isFavourite(course.id),
                                              builder: (context, snapshot) {
                                                final isFav = snapshot.data ?? false;
                                                return IconButton(
                                                  icon: Icon(
                                                    isFav ? Icons.star : Icons.star_border,
                                                    color: Colors.orange,
                                                  ),
                                                  onPressed: () async {
                                                    await _toggleFavorite(course.id);
                                                    setState(() {});
                                                  },
                                                );
                                              },
                                            ),
                                            if (course.hasQuiz)
                                              ElevatedButton(
                                                onPressed: _loadingQuiz ? null : () => _startQuiz(course),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF8AD03D),
                                                  foregroundColor: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 10,
                                                  ),
                                                  textStyle: const TextStyle(
                                                    fontFamily: 'Poppins',
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                child: _loadingQuiz
                                                    ? const SizedBox(
                                                  height: 16,
                                                  width: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                                    : const Text('Take Quiz !'),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      "By ${course.author} • ${course.duration}",
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 12,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(height: 24),


                                    if (isFD) ...[
                                      FixedDepositBanksView(course: course),
                                    ] else ...[...course.sections.map(
                                          (s) => Padding(
                                        padding: const EdgeInsets.only(bottom: 16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              s.title,
                                              style: const TextStyle(
                                                fontFamily: 'Poppins',
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              s.content,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF9393A3),
                                                fontFamily: 'Poppins',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    ],
                                  ],),
                              )
                                  : (_quizMode == QuizMode.playing
                                  ? _buildQuizView(scrollController)
                                  : _quizMode == QuizMode.result
                                  ? _buildResultView(scrollController)
                                  : _buildReviewView(scrollController)),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class FixedDepositBanksView extends StatelessWidget {
  final Course course;
  const FixedDepositBanksView({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    // Parse sections -> banks
    final banks = course.sections
        .map((s) => BankFDInfo.fromSection(s))
        .where((b) => b != null)
        .cast<BankFDInfo>()
        .toList();

    if (banks.isEmpty) {
      return const Text(
        'No fixed deposit details found.',
        style: TextStyle(fontFamily: 'Poppins', color: Colors.white70),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fixed Deposit offers by bank',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),

        // List of bank containers
        ...banks.map((b) => _BankFDCard(info: b)),

        const SizedBox(height: 8),
      ],
    );
  }
}

class BankFDInfo {
  final String bankName;

  final String rateLabel;
  final String rateValue;

  final String earlyLabel;
  final String earlyValue;

  final String earnedLabel;
  final String earnedValue;

  BankFDInfo({
    required this.bankName,
    required this.rateLabel,
    required this.rateValue,
    required this.earlyLabel,
    required this.earlyValue,
    required this.earnedLabel,
    required this.earnedValue,
  });

  static BankFDInfo? fromSection(Section s) {
    final lines = s.content
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (lines.isEmpty) return null;

    final bank = s.title.trim().isNotEmpty ? s.title.trim() : lines[0];
    int startIdx = s.title.trim().isNotEmpty ? 0 : 1;

    // Helper: extract label/value for a line pair
    LabelValue getLabelValue(int index) {
      if (lines.length > startIdx + index) {
        final line = lines[startIdx + index];
        // If line contains colon, split by colon
        if (line.contains(':')) {
          final parts = line.split(':');
          final label = parts[0].trim();
          final value = parts.sublist(1).join(':').trim();
          return LabelValue(label, value);
        } else if (lines.length > startIdx + index + 1) {
          // Otherwise, next line is the value
          final label = line;
          final value = lines[startIdx + index + 1];
          return LabelValue(label, value);
        } else {
          return LabelValue('', line);
        }
      }
      return LabelValue('', '');
    }

    final rate = getLabelValue(0);
    final early = getLabelValue(2);   // skip to next pair
    final earned = getLabelValue(4);  // skip to next pair

    return BankFDInfo(
      bankName: bank,
      rateLabel: rate.label,
      rateValue: rate.value,
      earlyLabel: early.label,
      earlyValue: early.value,
      earnedLabel: earned.label,
      earnedValue: earned.value,
    );
  }
}

class LabelValue {
  final String label;
  final String value;
  LabelValue(this.label, this.value);
}

class _BankFDCard extends StatelessWidget {
  final BankFDInfo info;
  const _BankFDCard({required this.info});

  @override
  Widget build(BuildContext context) {
    Widget buildRow(String label, String value, Color valueColor) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LabelPill(text: label),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value.isNotEmpty ? value : '—',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: valueColor,  // colored per type
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3D6B52),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bank name
          Row(
            children: [
              const Icon(Icons.account_balance, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  info.bankName,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Rows with colored values
          buildRow(info.rateLabel, info.rateValue, const Color(0xFF8AD03D)), // green
          buildRow(info.earlyLabel, info.earlyValue, Colors.white),
          buildRow(info.earnedLabel, info.earnedValue, Colors.white),
        ],
      ),
    );
  }
}

class _LabelPill extends StatelessWidget {
  final String text;
  const _LabelPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF2F5643),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Poppins',
          color: Colors.white70,   // slightly muted
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

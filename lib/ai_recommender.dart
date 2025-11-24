// lib/ai_recommender.dart
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';

class AiCourseRecommender {
  AiCourseRecommender._();
  static final AiCourseRecommender instance = AiCourseRecommender._();

  static const String _apiKey = 'AIzaSyAhxy_gk0FYEnaxzVa5VH2OqABxhNLxk8s';

  late final GenerativeModel _model = GenerativeModel(
    model: 'gemini-2.5-flash',
    apiKey: _apiKey,
    systemInstruction: Content.system(_systemInstructionText),
  );

  /// Returns up to 3 category strings. No copy, no UI text.
  Future<List<String>> pickCategories({
    required String financialSummaryJson,
  }) async {
    final prompt =
        "User financial summary: $financialSummaryJson\n\nUser message: Recommend up to 3 relevant learning categories.";
    final res = await _model.generateContent([Content.text(prompt)]);
    final raw = (res.text ?? '').trim();
    if (raw.isEmpty) return const [];

    final cleaned = raw.replaceAll('```json', '').replaceAll('```', '').trim();
    final map = jsonDecode(cleaned) as Map<String, dynamic>;
    final cats = (map['suggested_categories'] as List?)?.cast<String>() ?? const [];
    // normalize + dedupe
    final set = <String>{};
    for (final c in cats) {
      final s = c.trim();
      if (s.isNotEmpty) set.add(s);
      if (set.length == 3) break;
    }
    return set.toList();
  }
}

const _systemInstructionText =
    "You will receive a JSON summary of the user's budgets, goals, and spending. "
    "You must reply with valid JSON containing ONLY the key 'suggested_categories' with an array of up to 3 strings. "
    "Example: {\"suggested_categories\":[\"Budgeting\",\"Planning\"]}. "
    "Pick categories that EXIST in the app (e.g., Budgeting, Investing, Planning). "
    "No extra keys, no prose, no markdown.";

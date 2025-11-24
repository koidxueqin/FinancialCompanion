// lib/models/course.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Course {
  final String id;
  final String shortTitle;
  final String author;

  Course({
    required this.id,
    required this.shortTitle,
    required this.author,
  });

  // Convert Firestore doc into Course
  factory Course.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Course(
      id: doc.id,
      shortTitle: data['shortTitle'] ?? '',
      author: data['author'] ?? '',
    );
  }
}

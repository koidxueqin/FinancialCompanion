import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TermsAndConditionPage extends StatelessWidget {
  const TermsAndConditionPage({super.key});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF8EBB87);
    final docRef = FirebaseFirestore.instance.collection('legal').doc('terms');

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: docRef.snapshots(),
          builder: (context, snap) {
            final title = (snap.data?.data() ?? const {})['title'] ?? 'Terms & Condition';
            return Text(
              title,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            );
          },
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: docRef.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              // Show the actual error to help debugging
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!.data();
            if (data == null) {
              return const Center(child: Text('Document not found'));
            }

            final updatedAt = (data['updatedAt'] ?? '').toString();
            final sections = (data['sections'] as List<dynamic>? ?? [])
                .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
                .toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (updatedAt.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Last Updated $updatedAt',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Color(0xFF1F3B2F),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  for (final s in sections) _buildBlock(s),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBlock(Map<String, dynamic> block) {
    final style = (block['style'] ?? 'p') as String;
    final text = (block['text'] ?? '') as String;

    switch (style) {
      case 'h2':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      case 'p':
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            text,
            textAlign: TextAlign.justify,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              height: 1.5,
              color: Colors.black,
            ),
          ),
        );
    }
  }
}

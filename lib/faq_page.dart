import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FaqPage extends StatefulWidget {
  const FaqPage({super.key});

  @override
  State<FaqPage> createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  // Tracks open/closed state by document id so it survives rebuilds.
  final Map<String, bool> _open = {};
  late final Stream<List<_FaqDoc>> _faqsStream;

  @override
  void initState() {
    super.initState();
    _faqsStream = FirebaseFirestore.instance
        .collection('faqs')
        .orderBy('order')
        .snapshots()
        .map((snap) => snap.docs.map((d) => _FaqDoc.fromDoc(d)).toList());
  }

  // Colors (kept from your UI)
  static const bg = Color(0xFFF6F7F8);
  static const textPrimary = Color(0xFF0F1728);
  static const cardBorder = Color(0xFFE6E7EB);

  Stream<List<_FaqDoc>> _faqStream() {
    return FirebaseFirestore.instance
        .collection('faqs')
        .orderBy('order') // requires 'order' int field
        .snapshots()
        .map((snap) => snap.docs.map((d) => _FaqDoc.fromDoc(d)).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: bg,
        foregroundColor: textPrimary,
        title: const Text('FAQ'),
      ),
      body: StreamBuilder<List<_FaqDoc>>(
        stream: _faqStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Failed to load FAQs: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final faqs = snapshot.data ?? const <_FaqDoc>[];

          // Merge current open/closed state with incoming docs
          final items = faqs
              .map((f) => _FaqItem(
            id: f.id,
            q: f.question,
            a: f.answer,
            expanded: _open[f.id] ?? f.expandedDefault,
          ))
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // Header Illustration
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/avatars/faq.png', // make sure in pubspec.yaml
                  fit: BoxFit.cover,
                  height: 262,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              const Text(
                'Frequently Asked Questions',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // FAQ list
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  children: List.generate(items.length, (i) {
                    final item = items[i];
                    final isLast = i == items.length - 1;
                    return Column(
                      children: [
                        _FaqTile(
                          item: item,
                          onToggle: () {
                            setState(() {
                              final newVal = !item.expanded;
                              item.expanded = newVal;
                              _open[item.id] = newVal; // remember by doc id
                            });
                          },
                        ),
                        if (!isLast)
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFEFEFF3),
                          ),
                      ],
                    );
                  }),
                ),
              ),

              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'No FAQs yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ----------------- Widgets (same visuals) -----------------

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.item, required this.onToggle});

  final _FaqItem item;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    const qStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0F1728),
    );
    const aStyle = TextStyle(
      fontSize: 14,
      height: 1.5,
      color: Color(0xFF667085),
    );

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question row + plus/close icon
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Text(item.q, style: qStyle)),
                _PlusClose(isOpen: item.expanded),
              ],
            ),
            // Animated answer section
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: item.expanded
                  ? Padding(
                padding: const EdgeInsets.only(top: 10, right: 8),
                child: Text(item.a, style: aStyle),
              )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlusClose extends StatelessWidget {
  const _PlusClose({required this.isOpen});
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
      child: Container(
        key: ValueKey(isOpen),
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD6D8DE)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          isOpen ? '×' : '+',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.0),
        ),
      ),
    );
  }
}

// ----------------- Models / Mapping -----------------

class _FaqDoc {
  final String id;
  final String question;
  final String answer;
  final int order;
  final bool expandedDefault;

  _FaqDoc({
    required this.id,
    required this.question,
    required this.answer,
    required this.order,
    required this.expandedDefault,
  });

  factory _FaqDoc.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return _FaqDoc(
      id: doc.id,
      question: (d['question'] ?? '').toString(),
      answer: (d['answer'] ?? '').toString(),
      order: (d['order'] is int)
          ? d['order'] as int
          : int.tryParse('${d['order']}') ?? 0,
      expandedDefault: (d['expanded'] ?? false) == true,
    );
  }
}

class _FaqItem {
  final String id;
  final String q;
  final String a;
  bool expanded;

  _FaqItem({
    required this.id,
    required this.q,
    required this.a,
    required this.expanded,
  });
}

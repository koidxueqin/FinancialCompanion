import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PantryDialog extends StatefulWidget {
  final String userId;
  final Function(String) onFeed; // callback when feeding

  const PantryDialog({
    super.key,
    required this.userId,
    required this.onFeed,
  });

  @override
  State<PantryDialog> createState() => _PantryDialogState();
}

class _PantryDialogState extends State<PantryDialog> {
  List<Map<String, dynamic>> pantryItems = [];

  @override
  void initState() {
    super.initState();
    fetchPantry();
  }

  Future<void> fetchPantry() async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(widget.userId);
    final snapshot = await userRef.get();

    if (!snapshot.exists) return;

    final pantryRaw = snapshot.data()?['pantry'] ?? [];

    // Convert to list of maps
    final List<Map<String, dynamic>> rawList =
    List<Map<String, dynamic>>.from(pantryRaw);

    // --- MERGING LOGIC ---
    final Map<String, Map<String, dynamic>> merged = {};

    for (var item in rawList) {
      final name = item['name'];
      final qty = item['qty'] ?? 0;
      final image = item['image'] ?? '';

      if (merged.containsKey(name)) {
        // Add quantities together
        merged[name]!['qty'] += qty;
      } else {
        // Insert new entry
        merged[name] = {
          'name': name,
          'qty': qty,
          'image': image,
        };
      }
    }

    // Remove items with qty <= 0
    merged.removeWhere((key, value) => (value['qty'] ?? 0) <= 0);

    // --- Update local UI state ---
    setState(() {
      pantryItems = merged.values.toList();
    });

    // Save cleaned merged pantry back to Firestore
    await userRef.update({'pantry': pantryItems});

  }

  Future<void> feedItem(int index) async {
    final item = pantryItems[index];
    final userRef = FirebaseFirestore.instance.collection('users').doc(widget.userId);

    // Decrement qty
    int newQty = (item['qty'] ?? 1) - 1;

    // Update local state
    setState(() {
      if (newQty <= 0) {
        pantryItems.removeAt(index);
      } else {
        pantryItems[index]['qty'] = newQty;
      }
    });

    // Update Firestore pantry
    final snapshot = await userRef.get();
    if (snapshot.exists) {
      List<Map<String, dynamic>> pantry = List<Map<String, dynamic>>.from(snapshot.data()?['pantry'] ?? []);

      // Find the item and update qty
      for (var pItem in pantry) {
        if (pItem['name'] == item['name']) {
          pItem['qty'] = newQty;
          break;
        }
      }

      await userRef.update({'pantry': pantry});
    }

    // Trigger callback
    widget.onFeed(item['name']);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFDFF2E4),
      insetPadding: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 400,
          child: Column(
            children: [
              // Title + Close button
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Pantry',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF233068),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Pantry Grid
              Expanded(
                child: pantryItems.isEmpty
                    ? const Center(child: Text('No food items available'))
                    : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: pantryItems.length,
                  itemBuilder: (context, index) {
                    final item = pantryItems[index];
                    final itemName = item['name'];
                    final itemImage = item['image'];
                    final qty = item['qty'] ?? 1;

                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(itemImage, width: 80, height: 80),
                          const SizedBox(height: 8),
                          Text(itemName,
                              style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Qty: $qty'),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => feedItem(index),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('Feed'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

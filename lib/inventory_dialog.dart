import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pet_item_image_mapper.dart';

class InventoryDialog extends StatefulWidget {
  final String userId;
  final String petType;
  final String? wornItem; // pass currently worn item
  final Function(String newImage, String? itemName) onItemWear; // pass item name too

  const InventoryDialog({
    super.key,
    required this.userId,
    required this.petType,
    required this.onItemWear,
    this.wornItem,
  });

  @override
  State<InventoryDialog> createState() => _InventoryDialogState();
}

class _InventoryDialogState extends State<InventoryDialog> {
  List<Map<String, dynamic>> inventoryItems = [];
  String? wornItem;

  @override
  void initState() {
    super.initState();
    wornItem = widget.wornItem; // init from parent
    fetchInventory();
  }

  Future<void> fetchInventory() async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(widget.userId);
    final snapshot = await userRef.get();
    if (snapshot.exists) {
      final inv = snapshot.data()?['inventory'] ?? [];
      setState(() {
        inventoryItems = List<Map<String, dynamic>>.from(inv);
      });
    }
  }

  void handleWearRemove(String itemName) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(widget.userId);

    if (wornItem == itemName) {
      wornItem = null;
      await userRef.update({'worn_item': null}); // update Firestore
      widget.onItemWear(
        PetItemImageMapper.getImageResource(widget.petType, widget.petType),
        null,
      );
    } else {
      wornItem = itemName;
      await userRef.update({'worn_item': itemName}); // save worn item
      widget.onItemWear(
        PetItemImageMapper.getImageResource(widget.petType, itemName),
        itemName,
      );
    }
    setState(() {}); // refresh button
    Navigator.pop(context); // close popup
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
                      'Inventory',
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

              // Inventory Grid
              Expanded(
                child: inventoryItems.isEmpty
                    ? const Center(child: Text('No items in inventory'))
                    : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: inventoryItems.length,
                  itemBuilder: (context, index) {
                    final item = inventoryItems[index];
                    final itemName = item['name'];
                    final itemImage = item['image'];
                    final isWorn = wornItem == itemName;

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
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Qty: ${item['qty'] ?? 1}'),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => handleWearRemove(itemName),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                              isWorn ? Colors.redAccent : Colors.green,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(isWorn ? 'Remove' : 'Wear'),
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


import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'item.dart';

class StoreItemsDialog extends StatefulWidget {
  final int petCoinBalance;
  final String userId; // userId added

  const StoreItemsDialog({
    super.key,
    required this.petCoinBalance,
    required this.userId,
  });

  @override
  State<StoreItemsDialog> createState() => _StoreItemsDialogState();
}

class _StoreItemsDialogState extends State<StoreItemsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Item> accessoryItems = [];
  List<Item> foodItems = []; // can be populated later
  Map<Item, int> itemQuantities = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    accessoryItems = getAccessoryItems();
    for (var item in accessoryItems) {
      itemQuantities[item] = 0;
    }

    foodItems = getFoodItems(); // empty list for now
  }

  List<Item> getAccessoryItems() {
    return [
      Item.create(name: 'Black Sunglasses', coinsNeeded: 10, imageResource: 'assets/black_sunglasses.png'),
      Item.create(name: 'Yellow Sunglasses', coinsNeeded: 12, imageResource: 'assets/yellow_sunglasses.png'),
      Item.create(name: 'Black Spectacles', coinsNeeded: 15, imageResource: 'assets/black_specs.png'),
      Item.create(name: 'Purple Bone Collar', coinsNeeded: 8, imageResource: 'assets/purplebonecollar.png'),
      Item.create(name: 'Pink Ribbon', coinsNeeded: 10, imageResource: 'assets/pink_ribbon.png'),
      Item.create(name: 'Pink Bone Collar', coinsNeeded: 9, imageResource: 'assets/pinkbonecollar.png'),
      Item.create(name: 'Yellow Bone Collar', coinsNeeded: 8, imageResource: 'assets/yellowbonecollar.png'),
      Item.create(name: 'Gold Chain', coinsNeeded: 10, imageResource: 'assets/gold_chain.png'),
    ];
  }

  List<Item> getFoodItems() {
    return [
      Item.create(name: 'Burger', coinsNeeded: 5, imageResource: 'assets/burger.png'),
      Item.create(name: 'Pasta', coinsNeeded: 6, imageResource: 'assets/pasta.png'),
      Item.create(name: 'Pizza', coinsNeeded: 7, imageResource: 'assets/pizza.png'),
      Item.create(name: 'Coffee', coinsNeeded: 4, imageResource: 'assets/coffee.png'),
      Item.create(name: 'Banana', coinsNeeded: 3, imageResource: 'assets/banana.png'),
      Item.create(name: 'Cheese', coinsNeeded: 4, imageResource: 'assets/cheese.png'),
      Item.create(name: 'Sandwich', coinsNeeded: 6, imageResource: 'assets/sandwich.png'),
      Item.create(name: 'Croissant', coinsNeeded: 5, imageResource: 'assets/croissant.png'),
    ];
  }

  int getTotalCoinsNeeded() {
    int total = 0;
    itemQuantities.forEach((item, qty) {
      total += item.coinsNeeded * qty;
    });
    return total;
  }

  void increaseQuantity(Item item) {
    setState(() {
      itemQuantities[item] = (itemQuantities[item] ?? 0) + 1;
    });
  }

  void decreaseQuantity(Item item) {
    setState(() {
      if ((itemQuantities[item] ?? 0) > 0) {
        itemQuantities[item] = (itemQuantities[item] ?? 0) - 1;
      }
    });
  }

  Future<void> handleBuy() async {
    final totalCoins = getTotalCoinsNeeded();

    if (totalCoins == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one item.')),
      );
      return;
    }

    if (totalCoins <= widget.petCoinBalance) {
      final userRef = FirebaseFirestore.instance.collection('users').doc(widget.userId);

      try {
        // Separate food vs accessory
        final purchasedItems = itemQuantities.entries.where((e) => e.value > 0).toList();
        final foodPurchased = purchasedItems.where((e) => foodItems.contains(e.key)).toList();
        final accessoryPurchased = purchasedItems.where((e) => accessoryItems.contains(e.key)).toList();

        // Prepare data for Firestore
        final foodData = foodPurchased.map((e) => {
          'name': e.key.name,
          'image': e.key.imageResource,
          'qty': e.value,
        }).toList();

        final accessoryData = accessoryPurchased.map((e) => {
          'name': e.key.name,
          'image': e.key.imageResource,
          'qty': e.value,
        }).toList();

        // Update Firestore
        await userRef.update({
          'pet_coins': widget.petCoinBalance - totalCoins,
          if (accessoryData.isNotEmpty) 'inventory': FieldValue.arrayUnion(accessoryData),
          if (foodData.isNotEmpty) 'pantry': FieldValue.arrayUnion(foodData),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase successful!')),
        );

        Navigator.pop(
          context,
          purchasedItems,
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough coins.')),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget buildItemList(List<Item> items) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final qty = itemQuantities[item] ?? 0;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(2, 2),
              )
            ],
          ),
          child: Row(
            children: [
              Image.asset(item.imageResource, width: 50, height: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Coins: ${item.coinsNeeded}'),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => decreaseQuantity(item),
                  ),
                  Text('$qty'),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => increaseQuantity(item),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFDFF2E4),
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        height: 500, // fixed height for tab + list + buy section
        child: Column(
          children: [
            // TITLE + CLOSE BUTTON
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Item Shop',
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

            // TABS
            TabBar(
              controller: _tabController,
              labelColor: Colors.green[800],
              unselectedLabelColor: Colors.black54,
              indicatorColor: Colors.green[800],
              tabs: const [
                Tab(text: 'Food'),
                Tab(text: 'Accessory'),
              ],
            ),

            const SizedBox(height: 8),

            // TAB VIEWS
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Food tab
                  buildItemList(foodItems),
                  // Accessory tab
                  buildItemList(accessoryItems),
                ],
              ),
            ),

            // COINS SUMMARY + BUY BUTTON
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(2, 2),
                  )
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Coins: ${widget.petCoinBalance}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total Coins Needed: ${getTotalCoinsNeeded()}',
                        style: const TextStyle(fontSize: 16, color: Colors.redAccent),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: handleBuy,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2B8761),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Buy', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

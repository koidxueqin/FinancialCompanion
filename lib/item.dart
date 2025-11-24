class Item {
  String id;
  String name;
  int coinsNeeded;
  String imageResource;

  // Constructor
  Item({
    required this.id,
    required this.name,
    required this.coinsNeeded,
    required this.imageResource,
  });

  // Named constructor for creating a dummy item with a random ID
  factory Item.create({
    required String name,
    required int coinsNeeded,
    required String imageResource,
  }) {
    return Item(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // unique ID
      name: name,
      coinsNeeded: coinsNeeded,
      imageResource: imageResource,
    );
  }
}

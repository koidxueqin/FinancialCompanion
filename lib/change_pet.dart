import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChangePetPage extends StatefulWidget {
  const ChangePetPage({super.key});
  @override
  State<ChangePetPage> createState() => _ChangePetPageState();
}

class _ChangePetPageState extends State<ChangePetPage> {
  final _nameCtrl = TextEditingController();

  // Pet catalog (assets)
  final List<_PetItem> _pets = const [
    _PetItem(key: 'cat1',   name: 'Cat',     asset: 'assets/pets/cat1.png'),
    _PetItem(key: 'dog1',   name: 'Dog',     asset: 'assets/pets/dog1.png'),
    _PetItem(key: 'penguin',name: 'Penguin', asset: 'assets/pets/penguin.png'),
    _PetItem(key: 'lizard', name: 'Lizard',  asset: 'assets/pets/lizard.png'),
    _PetItem(key: 'sheep',  name: 'Sheep',   asset: 'assets/pets/sheep.png'),
    _PetItem(key: 'bird',   name: 'Bird',    asset: 'assets/pets/bird.png'),
    _PetItem(key: 'dog2',   name: 'Dog 2',   asset: 'assets/pets/dog2.png'),
    _PetItem(key: 'yoda',   name: 'Yoda',    asset: 'assets/pets/yoda.png'),
  ];

  String? _selectedKey;
  String? _currentKey;

  @override
  void initState() {
    super.initState();
    _loadCurrentPet();
  }

  Future<void> _loadCurrentPet() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('userPet').doc('current');

    final doc = await ref.get();

    if (!doc.exists) {
      // Default = cat1
      final def = _pets.firstWhere((p) => p.key == 'cat1');
      await ref.set({
        'name': 'Mr. Kitty',
        'key': def.key,
        'asset': def.asset,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      setState(() {
        _nameCtrl.text = 'Mr. Kitty';
        _currentKey = def.key;
        _selectedKey = def.key;
      });
      return;
    }

    final data = doc.data()!;
    setState(() {
      _nameCtrl.text = (data['name'] ?? '').toString();
      _currentKey = (data['key'] ?? '').toString();
      _selectedKey = _currentKey;
    });
  }

  Future<void> _savePet(_PetItem pet) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('userPet').doc('current')
        .set({
      'name': _nameCtrl.text.trim(),
      'key': pet.key,
      'asset': pet.asset,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    setState(() {
      _currentKey = pet.key;
      _selectedKey = pet.key;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pet updated!')),
      );
      // NOTE: no Navigator.pop() here anymore
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF8EBB87),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8EBB87),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pet Name',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  hintText: 'Mr. Kitty',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Grid of pets
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.88, // slightly taller -> avoids overflow
                  ),
                  itemCount: _pets.length,
                  itemBuilder: (_, i) {
                    final pet = _pets[i];
                    return _PetTile(
                      pet: pet,
                      currentKey: _currentKey,
                      selectedKey: _selectedKey,
                      onTap: () => setState(() => _selectedKey = pet.key),
                      onChange: () => _savePet(pet),
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

class _PetItem {
  final String key;
  final String name;
  final String asset;
  const _PetItem({required this.key, required this.name, required this.asset});
}

class _PetTile extends StatelessWidget {
  final _PetItem pet;
  final String? currentKey;
  final String? selectedKey;
  final VoidCallback onTap;
  final VoidCallback onChange;

  const _PetTile({
    required this.pet,
    required this.currentKey,
    required this.selectedKey,
    required this.onTap,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final isChosen = currentKey == pet.key;
    final isSelected = selectedKey == pet.key;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6F1),
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: const Color(0xFF2B8761), width: 2) : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                pet.asset,
                height: 86,
                width: 86,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              pet.name,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                color: Color(0xFF214235),
              ),
            ),
            if (isChosen) ...[
              const SizedBox(height: 4),
              const Text('Chosen', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
              const SizedBox(height: 8),
            ] else ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onChange,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A5B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('Change'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

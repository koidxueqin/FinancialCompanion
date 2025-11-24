import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  // Country + phone code (simple built-in list to avoid extra packages)
  final List<_Country> _countries = const [
    _Country('Malaysia', 'MY', '+60', '🇲🇾'),
    _Country('Singapore', 'SG', '+65', '🇸🇬'),
    _Country('Indonesia', 'ID', '+62', '🇮🇩'),
    _Country('Thailand', 'TH', '+66', '🇹🇭'),
    _Country('Philippines', 'PH', '+63', '🇵🇭'),
  ];

  late _Country _selectedCountry;
  String _gender = 'Female';


  String? _iconName;

  User get _user => FirebaseAuth.instance.currentUser!;

  // You can extend this list as you add assets
  static const _availableIcons = <String>[
    'icon1.png',
    'icon2.png',
    'icon3.png',
    'icon4.png',
    'icon5.png',
    'icon6.png',
    'icon7.png',
    'icon8.png',

  ];

  @override
  void initState() {
    super.initState();
    _selectedCountry = _countries.first; // default MY
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_user.uid).get();
      final data = doc.data() ?? {};

      _first.text = (data['firstName'] ?? '').toString();
      _last.text = (data['lastName'] ?? '').toString();
      _email.text = _user.email ?? (data['email'] ?? '');
      _phone.text = (data['phoneNumber'] ?? '').toString();
      _gender = (data['gender'] ?? _gender).toString();

      // country by name or code; default Malaysia
      final savedCountry = (data['country'] ?? 'Malaysia').toString();
      final match = _countries.where((c) => c.name == savedCountry || c.code == savedCountry).toList();
      if (match.isNotEmpty) _selectedCountry = match.first;

      // Load saved icon
      _iconName = (data['iconName'] as String?)?.trim();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load profile; using defaults.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      // Update Auth email if changed (verify-before-update flow)
      if (_email.text.trim() != (_user.email ?? '')) {
        await _user.verifyBeforeUpdateEmail(_email.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Check your inbox to confirm the new email.')),
          );
        }
      }

      // Update displayName in Auth
      final displayName = '${_first.text.trim()} ${_last.text.trim()}'.trim();
      await _user.updateDisplayName(displayName.isEmpty ? null : displayName);

      // Build Firestore update
      final update = <String, dynamic>{
        'firstName': _first.text.trim(),
        'lastName': _last.text.trim(),
        'email': _email.text.trim(),
        'phoneNumber': _phone.text.trim(),
        'country': _selectedCountry.name,
        'countryCode': _selectedCountry.dialCode,
        'gender': _gender,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_iconName != null && _iconName!.isNotEmpty) {
        update['iconName'] = _iconName;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user.uid)
          .set(update, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
      Navigator.pop(context); // back to ProfilePage
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'requires-recent-login' => 'Please log in again to change your email.',
        _ => e.message ?? 'Auth error',
      };
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Avatar widget uses selected icon if any
  ImageProvider<Object>? _avatarProvider() {
    if (_iconName != null && _iconName!.isNotEmpty) {
      return AssetImage('assets/avatars/${_iconName!}');
    }
    return null;
  }

  void _showIconPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Choose an avatar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                itemCount: _availableIcons.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemBuilder: (context, index) {
                  final name = _availableIcons[index];
                  return InkWell(
                    onTap: () {
                      setState(() => _iconName = name);
                      Navigator.pop(context);
                    },
                    child: ClipOval(
                      child: Image.asset(
                        'assets/avatars/$name',
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text('This cannot be undone. You might need to re-authenticate.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(_user.uid).delete();
      await _user.delete(); // may throw requires-recent-login
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account deleted')));
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.code == 'requires-recent-login'
              ? 'Please re-login, then try deleting again.'
              : 'Delete failed: ${e.message}')),
        );
      }
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF8EBB87);

    return Scaffold(
      backgroundColor: green,
      appBar: AppBar(
        backgroundColor: green,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            children: [
              // Avatar with icon picker button
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: Colors.white,
                    backgroundImage: _avatarProvider(),
                    child: (_iconName == null || _iconName!.isEmpty)
                        ? const Icon(Icons.person, size: 48, color: Colors.black54)
                        : null,
                  ),
                  GestureDetector(
                    onTap: _showIconPicker,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4, right: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black12)],
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const Icon(Icons.edit, size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Edit profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _LabeledField(
                      label: 'First name',
                      controller: _first,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    _LabeledField(label: 'Last name', controller: _last),
                    const SizedBox(height: 12),
                    _LabeledField(
                      label: 'Email',
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 12),

                    // Phone with flag + code prefix
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('Phone number'),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              InkWell(
                                onTap: () => _showCountryPicker(),
                                child: Row(
                                  children: [
                                    Text(_selectedCountry.flag, style: const TextStyle(fontSize: 20)),
                                    const SizedBox(width: 8),
                                    Text(
                                      _selectedCountry.dialCode,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                    const Icon(Icons.arrow_drop_down),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: _phone,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(
                                    hintText: '6012-345-7890',
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Country + Gender row
                    Row(
                      children: [
                        Expanded(
                          child: _DropdownField<_Country>(
                            label: 'Country',
                            value: _selectedCountry,
                            items: _countries.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                            onChanged: (c) => setState(() => _selectedCountry = c!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DropdownField<String>(
                            label: 'Gender',
                            value: _gender,
                            items: const [
                              DropdownMenuItem(value: 'Female', child: Text('Female', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'Male', child: Text('Male', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'Other', child: Text('Other', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(
                                value: 'Prefer not to say',
                                child: Text('Prefer not to say', overflow: TextOverflow.ellipsis),
                              ),
                            ],
                            onChanged: (g) => setState(() => _gender = g!),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Submit
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2B8761),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _saving
                            ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                            : const Text('SUBMIT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),

                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: _deleteAccount,
                      child: const Text('Delete Account', style: TextStyle(color: Colors.black54)),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          children: _countries
              .map(
                (c) => ListTile(
              leading: Text(c.flag, style: const TextStyle(fontSize: 20)),
              title: Text(c.name),
              trailing: Text(c.dialCode, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                setState(() => _selectedCountry = c);
                Navigator.pop(context);
              },
            ),
          )
              .toList(),
        ),
      ),
    );
  }
}

// ---------- UI helpers ----------

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _LabeledField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextFormField(
            controller: controller,
            validator: validator,
            keyboardType: keyboardType,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '',
            ),
          ),
        ),
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonFormField<T>(
            initialValue: value,
            isExpanded: true,
            menuMaxHeight: 320,
            items: items,
            onChanged: onChanged,
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
      ],
    );
  }
}

class _Country {
  final String name;
  final String code;     // ISO alpha-2
  final String dialCode; // +60
  final String flag;     // emoji
  const _Country(this.name, this.code, this.dialCode, this.flag);
}

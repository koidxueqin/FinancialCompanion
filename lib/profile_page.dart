import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_profile_page.dart';
import 'change_pwd.dart';
import 'change_pet.dart';
import 'privacy_policy.dart';
import 'terms_and_condition.dart';
import 'faq_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_page.dart'; // make sure this exports `class LoginPage extends StatelessWidget`

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool pushEnabled = true;

  User? get _user => FirebaseAuth.instance.currentUser;

  String get _displayName {
    final name = _user?.displayName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final email = _user?.email ?? '';
    if (email.contains('@')) return email.split('@').first;
    return 'User';
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _userDocStream {
    final u = _user;
    if (u == null) {
      return const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();
    }
    return FirebaseFirestore.instance.collection('users').doc(u.uid).snapshots();
  }

  String get _email => _user?.email ?? 'no-email@unknown.com';

  void _navTo(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;

      // 🔑 Replace the entire app stack from the ROOT navigator (kills MainShell/bottom nav too)
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to log out: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const greenBg = Color(0xFF8FBF8C);
    const cardRadius = 16.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      body: Stack(
        children: [
          Container(height: 180, color: greenBg),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              children: [
                const SizedBox(height: 8),
                // Profile card
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(cardRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Avatar from iconName (Firestore)
                        SizedBox(
                          width: 54,
                          height: 54,
                          child: ClipOval(
                            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              stream: _userDocStream,
                              builder: (context, snap) {
                                final data = snap.data?.data();
                                final iconName = (data?['iconName'] as String?)?.trim();

                                if (iconName == null || iconName.isEmpty) {
                                  return Container(
                                    color: const Color(0xFFEFF3F2),
                                    child: const Icon(Icons.person, size: 32, color: Colors.black54),
                                  );
                                }

                                return Image.asset(
                                  'assets/avatars/$iconName',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: const Color(0xFFEFF3F2),
                                    child: const Icon(Icons.person, size: 32, color: Colors.black54),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),
                        // Name + email + phone (phone live from Firestore)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                stream: _userDocStream,
                                builder: (context, snap) {
                                  final d = snap.data?.data() ?? {};
                                  final first = (d['firstName'] ?? '').toString().trim();
                                  final last  = (d['lastName']  ?? '').toString().trim();
                                  final composed = '$first $last'.trim();


                                  final authName = _user?.displayName?.trim();
                                  final emailPart = _email.contains('@') ? _email.split('@').first : 'User';

                                  final name = composed.isNotEmpty
                                      ? composed
                                      : (authName != null && authName.isNotEmpty ? authName : emailPart);

                                  return Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 4),
                              Text(
                                _email,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 4),
                              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                stream: _userDocStream,
                                builder: (context, snap) {
                                  final data = snap.data?.data();
                                  final fsPhone = (data?['phoneNumber'] as String?)?.trim() ?? '';
                                  final cc = (data?['countryCode'] as String?)?.trim() ?? '';
                                  final authPhone = _user?.phoneNumber ?? '';

                                  final phoneToShow =
                                  fsPhone.isNotEmpty ? (cc.isNotEmpty ? '$cc $fsPhone' : fsPhone) : authPhone;

                                  if (phoneToShow.isEmpty) return const SizedBox.shrink();
                                  return Text(
                                    phoneToShow,
                                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                const _SectionHeader('Account Settings'),
                _Tile(
                  title: 'Edit profile',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EditProfilePage()),
                  ),
                ),
                _Tile(
                  title: 'Change password',
                  onTap: () => _navTo(const ChangePwdPage()),
                ),
                _Tile(
                  title: 'Change pet',
                  onTap: () => _navTo(const ChangePetPage()),
                ),
                const SizedBox(height: 8),

                const _SectionHeader('More'),
                _Tile(title: 'FAQ', onTap: () => _navTo(const FaqPage())),
                _Tile(title: 'Privacy policy', onTap: () => _navTo(const PrivacyPolicyPage())),
                _Tile(title: 'Terms and conditions', onTap: () => _navTo(const TermsAndConditionPage())),

                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _signOut,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: greenBg,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Log Out'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF9FA4A5),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;
  const _Tile({required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontSize: 15, color: Colors.black87)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart' hide Settings;
import 'package:flutter/material.dart';
import 'package:hidden_drawer_menu/hidden_drawer_menu.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'app_settings.dart';
import 'api_service.dart';      // ← added for resolveImageUrl
import 'native_login.dart';
import 'main.dart';

import 'page/sales.dart';
import 'page/products.dart';
import 'page/settings.dart';

class AppHiddenDrawer extends StatelessWidget {
  const AppHiddenDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return SimpleHiddenDrawer(
      menu:                  const _Menu(),
      slidePercent:          50,
      initPositionSelected:  0,
      enableScaleAnimation:  true,
      contentCornerRadius:   20,
      screenSelectedBuilder: (position, controller) {
        switch (position) {
          case 0:  return const BrewPosHome();
          case 1:  return Sales();
          case 2:  return const Products();
          case 3:  return Settings();
          default: return const BrewPosHome();
        }
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MENU
// ─────────────────────────────────────────────────────────────

class _Menu extends StatefulWidget {
  const _Menu();
  @override State<_Menu> createState() => _MenuState();
}

class _MenuState extends State<_Menu> {
  late SimpleHiddenDrawerController _ctrl;
  int _sel = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctrl = SimpleHiddenDrawerController.of(context);
    _sel  = _ctrl.position;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.of(context).darkMode;

    final List<Color> gradientColors = isDark
        ? [const Color(0xFF3A2318), const Color(0xFF1A0F0A)]
        : [const Color(0xFF6F4E37), const Color(0xFF3E2723)];

    return Material(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end:   Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: ListView(
            children: [
              const _DrawerHeader(),

              _menuItem(0, Icons.home,          'Home'),
              _menuItem(1, Icons.point_of_sale, 'Sales'),
              _menuItem(2, Icons.inventory_2,   'Products'),
              _menuItem(3, Icons.settings,      'Settings'),

              const Divider(color: Colors.white24),

              ListTile(
                leading: const Icon(Icons.logout, color: Colors.white, size: 24),
                title: const Text('Logout',
                    style: TextStyle(color: Colors.white, fontSize: 20,
                        fontWeight: FontWeight.bold, fontFamily: 'inter')),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  await NativeLogin.openLogin();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuItem(int index, IconData icon, String title) {
    final active = _sel == index;
    return ListTile(
      leading: Icon(icon, size: 24,
          color: active ? Colors.yellow : Colors.white),
      title: Text(title,
          style: TextStyle(
              color: active ? Colors.yellow : Colors.white,
              fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'inter')),
      onTap: () {
        setState(() => _sel = index);
        _ctrl.setSelectedMenuPosition(index);
        _ctrl.close();
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DRAWER HEADER
// Streams the user document from Firestore in real-time.
// Priority for each field:
//   firstName → Firestore 'firstName' > split 'fullname' > Firebase displayName
//   lastName  → Firestore 'lastName'  > split 'fullname' > Firebase displayName
//   photo     → Firestore 'photoUrl'  > Firebase photoURL > initials fallback
// ─────────────────────────────────────────────────────────────

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return _header('Guest', '', null);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .snapshots(),
      builder: (context, snap) {
        // While loading, fall back to Firebase Auth display name / photo
        if (!snap.hasData) {
          final parts = (authUser.displayName ?? '').trim().split(RegExp(r'\s+'));
          return _header(
            parts.isNotEmpty ? parts.first : 'Guest',
            parts.length > 1 ? parts.sublist(1).join(' ') : '',
            // authUser.photoURL is already a full URL — safe to pass directly
            authUser.photoURL,
          );
        }

        final data = snap.data?.data() ?? {};

        // ── Resolve firstName / lastName ──
        String first = (data['firstName'] as String? ?? '').trim();
        String last  = (data['lastName']  as String? ?? '').trim();

        if (first.isEmpty && last.isEmpty) {
          final full = (data['fullname']  as String?
              ?? data['fullName'] as String? ?? '').trim();
          if (full.isNotEmpty) {
            final parts = full.split(RegExp(r'\s+'));
            first = parts.first;
            last  = parts.length > 1 ? parts.sublist(1).join(' ') : '';
          }
        }

        if (first.isEmpty && last.isEmpty) {
          final parts = (authUser.displayName ?? '').trim().split(RegExp(r'\s+'));
          first = parts.isNotEmpty ? parts.first : 'Guest';
          last  = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        }

        // ── Resolve photo ──
        // Firestore photoUrl may be:
        //   • a relative path  "/uploads/profile_xxx.jpg"  (new saves)
        //   • a full localhost  "http://127.0.0.1:8081/..."  (old saves)
        //   • an external URL  "https://lh3.googleusercontent.com/..."  (social)
        // resolveImageUrl handles all three cases correctly.
        final firestorePhoto = (data['photoUrl'] as String? ?? '').trim();
        final String? resolvedPhoto = firestorePhoto.isNotEmpty
            ? ApiService.resolveImageUrl(firestorePhoto)  // ← THE FIX
            : (authUser.photoURL?.isNotEmpty == true ? authUser.photoURL : null);

        return _header(first, last, resolvedPhoto);
      },
    );
  }

  Widget _header(String first, String last, String? photoUrl) {
    // photoUrl is always a full URL here (resolveImageUrl already applied).
    // Fall back to initials if null/empty.
    final ImageProvider avatar = (photoUrl != null && photoUrl.isNotEmpty)
        ? NetworkImage(photoUrl) as ImageProvider
        : const AssetImage('') as ImageProvider;

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 30, 24, 25),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 40,
              key:             ValueKey(photoUrl),
              backgroundImage: avatar,
              backgroundColor: const Color(0xFF4E342E),
              onBackgroundImageError: (_, __) {},
              child: (photoUrl == null || photoUrl.isEmpty)
                  ? Text(
                '${first.isNotEmpty ? first[0] : ''}'
                    '${last.isNotEmpty  ? last[0]  : ''}'
                    .toUpperCase(),
                style: const TextStyle(
                    fontSize:   22,
                    fontWeight: FontWeight.bold,
                    color:      Colors.white),
              )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(first,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 22,
                    fontWeight: FontWeight.bold, fontFamily: 'inter')),
            const SizedBox(height: 4),
            if (last.isNotEmpty)
              Text(last,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 18,
                      fontFamily: 'inter')),
          ],
        ),
      ),
    );
  }
}
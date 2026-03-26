import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hidden_drawer_menu/hidden_drawer_menu.dart';
import 'package:image_picker/image_picker.dart';

import '../app_settings.dart';
import '../api_service.dart';

// ─────────────────────────────────────────────────────────────
// DARK / LIGHT TOKENS
// ─────────────────────────────────────────────────────────────

Color _c(bool d, Color l, Color dk) => d ? dk : l;

abstract class _D {
  static const bg      = Color(0xFF1A0F0A);
  static const surface = Color(0xFF2C1A10);
  static const card    = Color(0xFF3A2318);
  static const text    = Color(0xFFF5EDE4);
  static const sub     = Color(0xFFB08B72);
  static const accent  = Color(0xFFD4A373);
  static const fill    = Color(0xFF241409);
}

// ─────────────────────────────────────────────────────────────
// PROFILE PAGE
// ─────────────────────────────────────────────────────────────

class Profile extends StatefulWidget {
  const Profile({super.key});
  @override State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  Future<void> _openEditProfile({
    required String  first,
    required String  last,
    required String? photo,
    required String  gcash,
    required String  passcode,
    required String? gcashQr,
    required bool    isDark,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // Always re-fetch latest passcode before opening sheet
    // so we never work with a stale PIN from the stream snapshot
    String live = passcode;
    try {
      final snap = await _db.collection('users').doc(uid).get();
      live = (snap.data()?['passcode'] as String?) ?? passcode;
    } catch (_) {}
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(
        firstName:   first,
        lastName:    last,
        photoUrl:    photo,
        gcashNumber: gcash,
        passcode:    live,
        gcashQrUrl:  gcashQr,
        isDark:      isDark,
        // ── onSave writes firstName, lastName, fullname,
        //    gcashNumber, and optionally photoUrl / gcashQrUrl
        //    to Firestore under /users/{uid}
        onSave: (nFirst, nLast, nPhoto, nGcash, nGcashQr) async {
          // Use set+merge instead of update() so this works even if the
          // document doesn't exist yet (e.g. first-ever profile save).
          // update() throws / silently fails on a missing document.
          final updates = <String, dynamic>{
            'firstName':   nFirst,
            'lastName':    nLast,
            'fullname':    '$nFirst $nLast',
            'gcashNumber': nGcash,
          };

          // Always write photoUrl when we have one — whether it's a new
          // upload URL or the same one passed in from the stream.
          // We only skip it if it's genuinely null/empty (no photo ever set).
          if (nPhoto != null && nPhoto.isNotEmpty) {
            updates['photoUrl'] = nPhoto;
          }

          // Same for GCash QR.
          if (nGcashQr != null && nGcashQr.isNotEmpty) {
            updates['gcashQrUrl'] = nGcashQr;
          }

          await _db
              .collection('users')
              .doc(uid)
              .set(updates, SetOptions(merge: true));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.of(context).darkMode;
    final user   = _auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      backgroundColor: _c(isDark, const Color(0xFFF6F6F6), _D.bg),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _db.collection('users').doc(user.uid).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
            if (snap.connectionState == ConnectionState.waiting)
              return const Center(child: CircularProgressIndicator());

            final data     = snap.data?.data();
            String first   = data?['firstName']   ?? '';
            String last    = data?['lastName']    ?? '';
            String full    = data?['fullname']    ?? data?['fullName'] ?? '';
            String photo   = data?['photoUrl']    ?? '';
            String gcash   = data?['gcashNumber'] ?? '';
            String pass    = data?['passcode']    ?? '';
            String gcashQr = data?['gcashQrUrl']  ?? '';

            // Fallback: split fullname if first/last not stored separately
            if (first.isEmpty && last.isEmpty && full.isNotEmpty) {
              final p = full.split(' ');
              first = p.first;
              last  = p.length > 1 ? p.sublist(1).join(' ') : '';
            }
            // Fallback: use Firebase Auth displayName
            if (first.isEmpty && last.isEmpty) {
              final p = (user.displayName ?? 'User').split(' ');
              first = p.first;
              last  = p.length > 1 ? p.sublist(1).join(' ') : '';
            }

            // `photo`    = Firestore photoUrl (relative path or external URL) — used for SAVING
            // `resolved`  = display URL: resolves local paths to full URL, falls back to
            //               Firebase Auth photoURL (Google/FB) when no custom photo is set.
            //               NEVER passed into the save flow — display only.
            final resolved = photo.isNotEmpty
                ? ApiService.resolveImageUrl(photo)
                : (user.photoURL ?? '');

            void edit() => _openEditProfile(
              first: first, last: last,
              // Pass raw Firestore `photo` (storable value), NOT resolved display URL.
              // This prevents user.photoURL (Google/FB external URL) from being
              // written back to Firestore as the photoUrl on every save.
              photo: photo.isNotEmpty ? photo : null,
              gcash: gcash, passcode: pass, gcashQr: gcashQr, isDark: isDark,
            );

            return Column(children: [
              _Topbar(isDark: isDark,
                  onMenuTap: () => SimpleHiddenDrawerController.of(context).toggle()),
              Expanded(child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(children: [
                  const SizedBox(height: 28),
                  _ProfileHero(
                    firstName: first, lastName: last,
                    // Use resolved (full URL) for display only
                    photoUrl:  resolved.isNotEmpty ? resolved : null,
                    isDark: isDark, onEditTap: edit,
                  ),
                  const SizedBox(height: 28),
                  _InfoSection(
                    email:       user.email ?? '—',
                    uid:         user.uid,
                    gcashNumber: gcash,
                    gcashQrUrl:  gcashQr,
                    hasPasscode: pass.isNotEmpty,
                    isDark:      isDark,
                    onEditGcash: edit,
                  ),
                  const SizedBox(height: 100),
                ]),
              )),
            ]);
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────

class _Topbar extends StatelessWidget {
  final bool isDark; final VoidCallback onMenuTap;
  const _Topbar({required this.isDark, required this.onMenuTap});

  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: SizedBox(height: 56, child: Stack(alignment: Alignment.center, children: [
      Align(alignment: Alignment.centerLeft,
          child: IconButton(onPressed: onMenuTap,
              icon: Icon(Icons.menu,
                  color: _c(isDark, const Color(0xFF2C1A0E), _D.accent)))),
      Text('Profile', style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.bold,
          fontFamily: 'playwrite',
          color: _c(isDark, const Color(0xFF2C1A0E), _D.accent))),
    ])),
  );
}

// ─────────────────────────────────────────────────────────────
// PROFILE HERO
// ─────────────────────────────────────────────────────────────

class _ProfileHero extends StatelessWidget {
  final String firstName, lastName;
  final String? photoUrl;
  final bool isDark;
  final VoidCallback onEditTap;
  const _ProfileHero({
    required this.firstName, required this.lastName,
    this.photoUrl, required this.isDark, required this.onEditTap,
  });

  @override Widget build(BuildContext context) {
    final initials =
    '${firstName.isNotEmpty ? firstName[0] : ''}'
        '${lastName.isNotEmpty  ? lastName[0]  : ''}'.toUpperCase();

    return Column(children: [
      GestureDetector(onTap: onEditTap,
          child: Stack(alignment: Alignment.center, children: [
            Container(width: 122, height: 122,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: const LinearGradient(
                        colors: [Color(0xFF8D6E63), Color(0xFF4E342E)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(
                        color: const Color(0xFF4E342E).withOpacity(0.35),
                        blurRadius: 22, offset: const Offset(0, 8))])),
            Container(width: 114, height: 114,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: _c(isDark, Colors.white, _D.surface))),
            CircleAvatar(
              key: ValueKey(photoUrl),
              radius: 52,
              backgroundColor: Colors.transparent,
              backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
                  ? NetworkImage(photoUrl!) as ImageProvider
                  : null,
              child: (photoUrl == null || photoUrl!.isEmpty)
                  ? Text(initials, style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800,
                  color: Color(0xFF4E342E)))
                  : null,
            ),
            Positioned(bottom: 4, right: 4,
                child: Container(width: 30, height: 30,
                    decoration: BoxDecoration(
                        color: const Color(0xFF6BCF7F), shape: BoxShape.circle,
                        border: Border.all(
                            color: _c(isDark, Colors.white, _D.surface), width: 2.5)),
                    child: const Icon(Icons.camera_alt, size: 14, color: Colors.white))),
          ])),
      const SizedBox(height: 16),
      Text('$firstName $lastName', style: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w800,
          color: _c(isDark, const Color(0xFF2C1A0E), _D.text),
          letterSpacing: -0.3)),
      const SizedBox(height: 4),
      Text('☕ Coffee Shop Owner', style: TextStyle(
          fontSize: 13,
          color: _c(isDark, const Color(0xFF8D6E63), _D.sub),
          fontWeight: FontWeight.w500)),
      const SizedBox(height: 10),
      GestureDetector(onTap: onEditTap,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                  color: const Color(0xFF4E342E).withOpacity(isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF4E342E).withOpacity(0.25))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit_outlined, size: 14,
                    color: _c(isDark, const Color(0xFF4E342E), _D.accent)),
                const SizedBox(width: 6),
                Text('Edit Profile', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: _c(isDark, const Color(0xFF4E342E), _D.accent))),
              ]))),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
// INFO SECTION
// ─────────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  final String email, uid, gcashNumber, gcashQrUrl;
  final bool hasPasscode, isDark;
  final VoidCallback onEditGcash;
  const _InfoSection({
    required this.email, required this.uid,
    required this.gcashNumber, required this.gcashQrUrl,
    required this.hasPasscode, required this.isDark,
    required this.onEditGcash,
  });

  void _qrFull(BuildContext ctx) => showDialog(
    context: ctx,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: _c(isDark, Colors.white, const Color(0xFF2C1A10)),
            borderRadius: BorderRadius.circular(24)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('GCash QR Code', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800,
              color: _c(isDark, const Color(0xFF2C1A0E), _D.text))),
          const SizedBox(height: 16),
          ClipRRect(borderRadius: BorderRadius.circular(16),
              child: Image.network(ApiService.resolveImageUrl(gcashQrUrl),
                  width: 260, height: 260, fit: BoxFit.contain)),
          const SizedBox(height: 16),
          Text('Scan to pay via GCash', style: TextStyle(
              fontSize: 13,
              color: _c(isDark, Colors.grey.shade500, _D.sub))),
          const SizedBox(height: 12),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ]),
      ),
    ),
  );

  @override Widget build(BuildContext ctx) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(children: [

      // ── Account card ───────────────────────────────────────
      Container(
        decoration: BoxDecoration(
            color: _c(isDark, Colors.white, _D.card),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(
                color: const Color(0xFF4E342E).withOpacity(isDark ? 0.2 : 0.07),
                blurRadius: 16, offset: const Offset(0, 6))]),
        child: Column(children: [
          _InfoRow(isDark: isDark, icon: Icons.email_outlined,
              label: 'Email', value: email, isFirst: true),
          Divider(height: 1, indent: 56, endIndent: 16,
              color: _c(isDark, Colors.grey.shade100, _D.card)),
          _InfoRow(isDark: isDark, icon: Icons.fingerprint,
              label: 'User ID',
              value: uid.length > 16 ? '${uid.substring(0, 16)}…' : uid),
        ]),
      ),

      const SizedBox(height: 16),

      // ── GCash card ─────────────────────────────────────────
      Container(
        decoration: BoxDecoration(
            color: _c(isDark, Colors.white, _D.card),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(
                color: const Color(0xFF0074D9).withOpacity(isDark ? 0.15 : 0.08),
                blurRadius: 16, offset: const Offset(0, 6))],
            border: Border.all(
                color: const Color(0xFF0074D9).withOpacity(0.15), width: 1.5)),
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header row
          Row(children: [
            Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFF0074D9).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.phone_android_outlined,
                    size: 18, color: Color(0xFF0074D9))),
            const SizedBox(width: 10),
            Expanded(child: Text('GCash Payment Number',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: _c(isDark, const Color(0xFF2C1A0E), _D.text)))),
            GestureDetector(onTap: onEditGcash,
                child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: const Color(0xFF0074D9).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Icon(hasPasscode ? Icons.lock_outline : Icons.lock_open_outlined,
                          size: 11, color: const Color(0xFF0074D9)),
                      const SizedBox(width: 4),
                      const Text('Edit', style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: Color(0xFF0074D9))),
                    ]))),
          ]),
          const SizedBox(height: 14),

          // GCash number display
          gcashNumber.isEmpty
              ? GestureDetector(onTap: onEditGcash,
              child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                      color: const Color(0xFF0074D9).withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF0074D9).withOpacity(0.2))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_circle_outline,
                        color: const Color(0xFF0074D9).withOpacity(0.6), size: 18),
                    const SizedBox(width: 8),
                    Text('Add GCash Number', style: TextStyle(fontSize: 13,
                        color: const Color(0xFF0074D9).withOpacity(0.7),
                        fontWeight: FontWeight.w600)),
                  ])))
              : Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF0074D9), Color(0xFF0056A3)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(
                      color: const Color(0xFF0074D9).withOpacity(0.3),
                      blurRadius: 12, offset: const Offset(0, 4))]),
              child: Row(children: [
                const Icon(Icons.phone_android, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('GCash Number', style: TextStyle(
                          fontSize: 10, color: Colors.white70,
                          fontWeight: FontWeight.w500)),
                      Text(gcashNumber, style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800,
                          color: Colors.white, letterSpacing: 1.5)),
                    ])),
                GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: gcashNumber));
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('GCash number copied!'),
                          duration: Duration(seconds: 1),
                          backgroundColor: Color(0xFF0074D9),
                          behavior: SnackBarBehavior.floating));
                    },
                    child: Container(padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.copy_outlined,
                            size: 16, color: Colors.white))),
              ])),

          const SizedBox(height: 10),

          // Security status row
          Row(children: [
            Icon(Icons.shield_outlined, size: 12,
                color: hasPasscode ? const Color(0xFF6BCF7F) : Colors.grey.shade400),
            const SizedBox(width: 4),
            Expanded(child: Text(
              gcashNumber.isEmpty
                  ? 'Add your GCash number so customers can pay via GCash.'
                  : hasPasscode
                  ? 'Protected by your GCash security PIN.'
                  : 'Set a GCash PIN in Settings › Security to protect this.',
              style: TextStyle(fontSize: 11, height: 1.4,
                  color: hasPasscode
                      ? const Color(0xFF6BCF7F) : Colors.grey.shade500),
            )),
          ]),

          // GCash QR section
          if (gcashQrUrl.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: _c(isDark, Colors.grey.shade100, _D.surface)),
            const SizedBox(height: 10),
            Row(children: [
              Container(padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: const Color(0xFF0074D9).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.qr_code_2,
                      size: 16, color: Color(0xFF0074D9))),
              const SizedBox(width: 8),
              Expanded(child: Text('GCash QR Code', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: _c(isDark, const Color(0xFF2C1A0E), _D.text)))),
              GestureDetector(onTap: () => _qrFull(ctx),
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: const Color(0xFF0074D9).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Text('View', style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: Color(0xFF0074D9))))),
            ]),
            const SizedBox(height: 10),
            GestureDetector(onTap: () => _qrFull(ctx),
                child: ClipRRect(borderRadius: BorderRadius.circular(12),
                    child: Image.network(ApiService.resolveImageUrl(gcashQrUrl),
                        height: 160, width: double.infinity,
                        fit: BoxFit.contain))),
          ] else ...[
            const SizedBox(height: 14),
            Divider(color: _c(isDark, Colors.grey.shade100, _D.surface)),
            const SizedBox(height: 10),
            GestureDetector(onTap: onEditGcash,
                child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                        color: const Color(0xFF0074D9).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF0074D9).withOpacity(0.2))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.qr_code_2,
                          color: const Color(0xFF0074D9).withOpacity(0.6), size: 18),
                      const SizedBox(width: 8),
                      Text('Add GCash QR Code', style: TextStyle(fontSize: 13,
                          color: const Color(0xFF0074D9).withOpacity(0.7),
                          fontWeight: FontWeight.w600)),
                    ]))),
          ],
        ]),
      ),
    ]),
  );
}

class _InfoRow extends StatelessWidget {
  final bool isDark; final IconData icon;
  final String label, value; final bool isFirst;
  const _InfoRow({
    required this.isDark, required this.icon,
    required this.label, required this.value, this.isFirst = false,
  });

  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Container(width: 36, height: 36,
          decoration: BoxDecoration(
              color: const Color(0xFF4E342E).withOpacity(isDark ? 0.18 : 0.08),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18,
              color: _c(isDark, const Color(0xFF4E342E), _D.accent))),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
            color: _c(isDark, Colors.grey.shade500, _D.sub))),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
            color: _c(isDark, const Color(0xFF2C1A0E), _D.text))),
      ])),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────
// PASSCODE INPUT  (numpad)
// ─────────────────────────────────────────────────────────────

class _PasscodeInput extends StatefulWidget {
  final String title, subtitle;
  final Color accentColor;
  final bool isDark;
  final void Function(String) onComplete;
  const _PasscodeInput({
    required super.key, required this.title, required this.subtitle,
    required this.accentColor, required this.isDark, required this.onComplete,
  });
  @override State<_PasscodeInput> createState() => _PasscodeInputState();
}

class _PasscodeInputState extends State<_PasscodeInput>
    with SingleTickerProviderStateMixin {
  String _code = '';
  late AnimationController _sc;
  late Animation<double> _sa;

  @override void initState() {
    super.initState();
    _sc = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _sa = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _sc, curve: Curves.elasticIn));
  }
  @override void dispose() { _sc.dispose(); super.dispose(); }

  void _press(String digit) {
    if (_code.length >= 4) return;
    setState(() => _code += digit);
    if (_code.length == 4) Future.delayed(
        const Duration(milliseconds: 120), () => widget.onComplete(_code));
  }

  void _del() {
    if (_code.isEmpty) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  void shakeAndClear() {
    _sc.forward(from: 0).then((_) {
      if (mounted) setState(() => _code = '');
    });
  }

  @override Widget build(BuildContext context) {
    final d = widget.isDark;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(widget.title, style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w800,
          color: _c(d, const Color(0xFF2C1A0E), _D.text),
          fontFamily: 'playwrite')),
      const SizedBox(height: 6),
      Text(widget.subtitle, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13,
              color: _c(d, Colors.grey.shade500, _D.sub))),
      const SizedBox(height: 28),

      // PIN dots with shake animation
      AnimatedBuilder(animation: _sa,
          builder: (_, child) => Transform.translate(
              offset: Offset(
                  _sa.value * 10 * (_sa.value < 0.5 ? 1 : -1), 0),
              child: child),
          child: Row(mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final on = i < _code.length;
                return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: on ? 18 : 16, height: on ? 18 : 16,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: on ? widget.accentColor : Colors.transparent,
                        border: Border.all(
                            color: on ? widget.accentColor
                                : _c(d, Colors.grey.shade300, _D.sub),
                            width: 2),
                        boxShadow: on ? [BoxShadow(
                            color: widget.accentColor.withOpacity(0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2))] : []));
              }))),
      const SizedBox(height: 32),

      // Numpad
      SizedBox(width: 260, child: Column(children: [
        _pr(d, ['1','2','3']), const SizedBox(height: 14),
        _pr(d, ['4','5','6']), const SizedBox(height: 14),
        _pr(d, ['7','8','9']), const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          const SizedBox(width: 72), _pk(d, '0'), _dk(d),
        ]),
      ])),
    ]);
  }

  Widget _pr(bool d, List<String> ds) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ds.map((x) => _pk(d, x)).toList());

  Widget _pk(bool d, String digit) => GestureDetector(
      onTap: () => _press(digit),
      child: Container(width: 72, height: 60,
          decoration: BoxDecoration(
              color: _c(d, Colors.white, _D.card),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(d ? 0.3 : 0.06),
                  blurRadius: 8, offset: const Offset(0, 3))]),
          child: Center(child: Text(digit, style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w700,
              color: _c(d, const Color(0xFF2C1A0E), _D.text))))));

  Widget _dk(bool d) => GestureDetector(onTap: _del,
      child: Container(width: 72, height: 60,
          decoration: BoxDecoration(
              color: _c(d, Colors.grey.shade100, _D.surface),
              borderRadius: BorderRadius.circular(16)),
          child: Icon(Icons.backspace_outlined, size: 22,
              color: _c(d, Colors.grey.shade500, _D.sub))));
}

// ─────────────────────────────────────────────────────────────
// PASSCODE SHEET
// ─────────────────────────────────────────────────────────────

Future<bool> showPasscodeSheet(
    BuildContext context, {
      required String existingPasscode,
      required String uid,
    }) async =>
    await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: false,
        enableDrag: false,
        builder: (_) => _PasscodeSheet(
            existingPasscode: existingPasscode,
            uid: uid,
            isDark: AppSettings.of(context).darkMode)) ??
        false;

class _PasscodeSheet extends StatefulWidget {
  final String existingPasscode, uid;
  final bool isDark;
  const _PasscodeSheet({
    required this.existingPasscode, required this.uid, required this.isDark,
  });
  @override State<_PasscodeSheet> createState() => _PSState();
}

class _PSState extends State<_PasscodeSheet> {
  String _first = '';
  bool _conf    = false;
  String? _err;
  final GlobalKey<_PasscodeInputState> _k = GlobalKey<_PasscodeInputState>();

  bool   get _create => widget.existingPasscode.isEmpty;
  String get _title  => _create
      ? (_conf ? 'Confirm Passcode' : 'Create GCash PIN')
      : 'Enter GCash PIN';
  String get _sub    => _create
      ? (_conf ? 'Re-enter to confirm'
      : 'Protect your GCash number & QR')
      : 'Enter your 4-digit GCash PIN to continue';

  void _on(String code) {
    if (_create) {
      if (!_conf) {
        setState(() { _first = code; _conf = true; _err = null; });
      } else {
        if (code == _first) {
          _save(code);
        } else {
          setState(() { _err = "PINs don't match."; _conf = false; _first = ''; });
          _k.currentState?.shakeAndClear();
        }
      }
    } else {
      if (code == widget.existingPasscode) {
        Navigator.pop(context, true);
      } else {
        setState(() => _err = 'Wrong PIN. Try again.');
        _k.currentState?.shakeAndClear();
      }
    }
  }

  Future<void> _save(String code) async {
    await FirebaseFirestore.instance
        .collection('users').doc(widget.uid)
        .update({'passcode': code});
    if (mounted) Navigator.pop(context, true);
  }

  @override Widget build(BuildContext context) {
    final d = widget.isDark;
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: BoxDecoration(
          color: _c(d, const Color(0xFFF6F6F6), _D.bg),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 5,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: _c(d, Colors.grey.shade300, _D.card),
                  borderRadius: BorderRadius.circular(99))),
          Container(width: 64, height: 64,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF0074D9), Color(0xFF0056A3)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                      color: const Color(0xFF0074D9).withOpacity(0.3),
                      blurRadius: 14, offset: const Offset(0, 4))]),
              child: const Icon(Icons.phonelink_lock_outlined,
                  color: Colors.white, size: 28)),
          const SizedBox(height: 20),
          _PasscodeInput(key: _k,
              title: _title, subtitle: _sub,
              accentColor: const Color(0xFF0074D9),
              isDark: d, onComplete: _on),
          if (_err != null) ...[
            const SizedBox(height: 16),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200)),
                child: Row(children: [
                  Icon(Icons.error_outline, color: Colors.red.shade400, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_err!, style: TextStyle(
                      fontSize: 13, color: Colors.red.shade600,
                      fontWeight: FontWeight.w500))),
                ])),
          ],
          const SizedBox(height: 20),
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(
                  color: Colors.grey.shade500, fontSize: 14,
                  fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// EDIT PROFILE SHEET
// ─────────────────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  final String  firstName, lastName, gcashNumber, passcode;
  final String? photoUrl, gcashQrUrl;
  final bool    isDark;
  final Future<void> Function(
      String first, String last, String? photoUrl,
      String gcash, String? gcashQrUrl) onSave;

  const _EditProfileSheet({
    required this.firstName, required this.lastName,
    this.photoUrl, required this.gcashNumber,
    required this.passcode, this.gcashQrUrl,
    required this.isDark, required this.onSave,
  });

  @override State<_EditProfileSheet> createState() => _EPSState();
}

class _EPSState extends State<_EditProfileSheet> {
  late final TextEditingController _fc, _lc, _gc;
  File? _pickedImage;    // new profile photo file
  File? _pickedQr;       // new GCash QR file
  bool  _uploading    = false;
  bool  _gcashChanged = false;
  bool  _qrChanged    = false;

  final _api    = ApiService();
  final _picker = ImagePicker();

  @override void initState() {
    super.initState();
    _fc = TextEditingController(text: widget.firstName);
    _lc = TextEditingController(text: widget.lastName);
    _gc = TextEditingController(text: widget.gcashNumber);
  }
  @override void dispose() { _fc.dispose(); _lc.dispose(); _gc.dispose(); super.dispose(); }

  Future<void> _pickImage(ImageSource src) async {
    Navigator.pop(context);
    final x = await _picker.pickImage(
        source: src, imageQuality: 80, maxWidth: 800);
    if (x == null) return;
    setState(() => _pickedImage = File(x.path));
  }

  Future<void> _pickQr() async {
    final x = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90, maxWidth: 1200);
    if (x == null) return;
    setState(() { _pickedQr = File(x.path); _qrChanged = true; });
  }

  void _imgSheet() {
    final d = widget.isDark;
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
        builder: (_) => Container(
            decoration: BoxDecoration(
                color: _c(d, Colors.white, const Color(0xFF2C1A10)),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20))),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text('Change Photo', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  color: _c(d, const Color(0xFF2C1A0E), _D.text))),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _SrcOpt(isDark: d, icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onTap: () => _pickImage(ImageSource.gallery)),
                _SrcOpt(isDark: d, icon: Icons.camera_alt_outlined,
                    label: 'Camera',
                    onTap: () => _pickImage(ImageSource.camera)),
              ]),
            ])));
  }

  // Passcode gate: verify existing PIN before allowing GCash/QR changes.
  // If no PIN is set yet, block the save and direct user to Settings.
  // We do NOT create a PIN inline here — that would be a separate Firestore
  // write that could succeed even if the main profile save fails.
  Future<bool> _passGate() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (widget.passcode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.info_outline, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Expanded(child: Text(
                'Set a GCash PIN in Settings › Security first, then come back to edit.')),
          ]),
          backgroundColor: const Color(0xFF0074D9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4)));
      return false; // block — no PIN set means no GCash/QR edit allowed
    }
    return showPasscodeSheet(
        context, existingPasscode: widget.passcode, uid: uid);
  }

  Future<void> _save() async {
    final first = _fc.text.trim();
    final last  = _lc.text.trim();
    final gcash = _gc.text.trim();

    if (first.isEmpty || last.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Name fields cannot be empty'),
          backgroundColor: Color(0xFF4E342E)));
      return;
    }

    // Require passcode if GCash number OR QR changed
    if (_gcashChanged || _qrChanged) {
      if (!await _passGate()) return;
    }

    setState(() => _uploading = true);

    try {
      // ── Profile image ─────────────────────────────────────────
      // If a new image was picked, upload it and get back a relative
      // path e.g. "/uploads/profile_xxx.jpg" (ApiService strips the host).
      // If no new image, normalize whatever is already stored in Firestore
      // to a relative path via _toRelativePath — this prevents a full
      // "http://127.0.0.1:8081/..." URL from being written back into Firestore
      // when the user saves without changing their photo.
      String? photoUrl = ApiService.toRelativePath(widget.photoUrl ?? '');
      if (photoUrl!.isEmpty) photoUrl = null;
      if (_pickedImage != null) {
        if (!await _pickedImage!.exists()) {
          throw Exception('Profile image file no longer exists.');
        }
        photoUrl = await _api.uploadProfileImage(_pickedImage!);
      }

      // ── GCash QR image ────────────────────────────────────────
      // Same normalization as above — stored path must always be relative.
      String? gcashQrUrl = ApiService.toRelativePath(widget.gcashQrUrl ?? '');
      if (gcashQrUrl!.isEmpty) gcashQrUrl = null;
      if (_pickedQr != null) {
        if (!await _pickedQr!.exists()) {
          throw Exception('QR image file no longer exists.');
        }
        gcashQrUrl = await _api.uploadQrImage(_pickedQr!);
      }

      // ── Firestore write via parent callback ───────────────────
      // Writes: firstName, lastName, fullname, gcashNumber
      // + photoUrl (relative path only if set), gcashQrUrl (relative path only if set)
      await widget.onSave(first, last, photoUrl, gcash, gcashQrUrl);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: const Color(0xFF4E342E),
          behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override Widget build(BuildContext context) {
    final d  = widget.isDark;
    final bi = MediaQuery.of(context).viewInsets.bottom;
    final initials =
    '${widget.firstName.isNotEmpty ? widget.firstName[0] : ''}'
        '${widget.lastName.isNotEmpty  ? widget.lastName[0]  : ''}'.toUpperCase();

    // Image preview providers — use resolveImageUrl so relative paths
    // stored in Firestore are correctly converted to full localhost URLs for display.
    final ImageProvider? photoPreview = _pickedImage != null
        ? FileImage(_pickedImage!) as ImageProvider
        : (widget.photoUrl != null && widget.photoUrl!.isNotEmpty)
        ? NetworkImage(ApiService.resolveImageUrl(widget.photoUrl!)) as ImageProvider
        : null;

    final ImageProvider? qrPreview = _pickedQr != null
        ? FileImage(_pickedQr!) as ImageProvider
        : (widget.gcashQrUrl != null && widget.gcashQrUrl!.isNotEmpty)
        ? NetworkImage(ApiService.resolveImageUrl(widget.gcashQrUrl!)) as ImageProvider
        : null;

    return Container(
      decoration: BoxDecoration(
          color: _c(d, Colors.white, _D.card),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bi),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 22),

          Row(children: [
            Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFF4E342E).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.person_outline,
                    color: Color(0xFF4E342E), size: 18)),
            const SizedBox(width: 10),
            Text('Edit Profile', style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800,
                color: _c(d, const Color(0xFF2C1A0E), _D.text))),
          ]),
          const SizedBox(height: 24),

          // ── Profile photo picker ──────────────────────────────
          GestureDetector(onTap: _imgSheet,
              child: Stack(alignment: Alignment.center, children: [
                Container(width: 96, height: 96,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        gradient: const LinearGradient(
                            colors: [Color(0xFF8D6E63), Color(0xFF4E342E)]),
                        boxShadow: [BoxShadow(
                            color: const Color(0xFF4E342E).withOpacity(0.3),
                            blurRadius: 14, offset: const Offset(0, 6))])),
                CircleAvatar(radius: 43, backgroundColor: Colors.transparent,
                    backgroundImage: photoPreview,
                    child: photoPreview == null
                        ? Text(initials, style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800,
                        color: Color(0xFF4E342E)))
                        : null),
                Positioned(bottom: 2, right: 2,
                    child: Container(width: 28, height: 28,
                        decoration: BoxDecoration(
                            color: const Color(0xFF6BCF7F),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _c(d, Colors.white, _D.card), width: 2)),
                        child: const Icon(Icons.camera_alt,
                            size: 13, color: Colors.white))),
              ])),
          if (_pickedImage != null) ...[
            const SizedBox(height: 6),
            Text('✓ Photo ready to save', style: TextStyle(
                fontSize: 12, color: Colors.green.shade600,
                fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 24),

          // ── Name fields ───────────────────────────────────────
          _lbl(d, 'First Name'), const SizedBox(height: 6),
          _fld(d, _fc, 'Enter first name', Icons.badge_outlined),
          const SizedBox(height: 16),
          _lbl(d, 'Last Name'), const SizedBox(height: 6),
          _fld(d, _lc, 'Enter last name', Icons.badge_outlined),
          const SizedBox(height: 16),

          // ── GCash number ──────────────────────────────────────
          Row(children: [
            _lbl(d, 'GCash Number'), const Spacer(),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: widget.passcode.isNotEmpty
                        ? const Color(0xFF6BCF7F).withOpacity(0.12)
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.passcode.isNotEmpty
                        ? const Color(0xFF6BCF7F).withOpacity(0.4)
                        : Colors.orange.shade200)),
                child: Row(children: [
                  Icon(widget.passcode.isNotEmpty
                      ? Icons.lock_outline : Icons.lock_open_outlined,
                      size: 10,
                      color: widget.passcode.isNotEmpty
                          ? const Color(0xFF6BCF7F) : Colors.orange.shade600),
                  const SizedBox(width: 3),
                  Text(widget.passcode.isNotEmpty ? 'PIN set' : 'No PIN',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                          color: widget.passcode.isNotEmpty
                              ? const Color(0xFF6BCF7F)
                              : Colors.orange.shade600)),
                ])),
          ]),
          const SizedBox(height: 6),
          TextField(
              controller: _gc,
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() => _gcashChanged = true),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  letterSpacing: 1.5, color: Color(0xFF0074D9)),
              decoration: InputDecoration(
                  hintText: '09XXXXXXXXX',
                  hintStyle: TextStyle(color: Colors.grey.shade400,
                      letterSpacing: 0, fontWeight: FontWeight.normal,
                      fontSize: 15),
                  prefixIcon: const Icon(Icons.phone_android_outlined,
                      size: 18, color: Color(0xFF0074D9)),
                  suffixIcon: _gcashChanged
                      ? const Padding(padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.lock_outline,
                          size: 16, color: Color(0xFF0074D9)))
                      : null,
                  filled: true,
                  fillColor: _c(d,
                      const Color(0xFF0074D9).withOpacity(0.05),
                      const Color(0xFF0074D9).withOpacity(0.08)),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: Color(0xFF0074D9), width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14))),
          const SizedBox(height: 20),

          // ── GCash QR picker ───────────────────────────────────
          Row(children: [
            const Icon(Icons.qr_code_2, size: 14, color: Color(0xFF0074D9)),
            const SizedBox(width: 6),
            _lbl(d, 'GCash QR Code'),
            const Spacer(),
            if (_qrChanged) Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFF0074D9).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF0074D9).withOpacity(0.3))),
                child: const Row(children: [
                  Icon(Icons.lock_outline, size: 10, color: Color(0xFF0074D9)),
                  SizedBox(width: 3),
                  Text('PIN required', style: TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w700, color: Color(0xFF0074D9))),
                ])),
          ]),
          const SizedBox(height: 8),
          GestureDetector(onTap: _pickQr,
              child: Container(
                  width: double.infinity, height: 160,
                  decoration: BoxDecoration(
                      color: _c(d,
                          const Color(0xFF0074D9).withOpacity(0.04),
                          const Color(0xFF0074D9).withOpacity(0.08)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _qrChanged
                              ? const Color(0xFF0074D9).withOpacity(0.5)
                              : const Color(0xFF0074D9).withOpacity(0.25),
                          width: _qrChanged ? 2 : 1.5)),
                  child: qrPreview != null
                      ? ClipRRect(borderRadius: BorderRadius.circular(12),
                      child: Image(image: qrPreview, fit: BoxFit.contain))
                      : Column(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_scanner, size: 40,
                            color: const Color(0xFF0074D9).withOpacity(0.4)),
                        const SizedBox(height: 8),
                        Text('Tap to upload GCash QR Code',
                            style: TextStyle(fontSize: 13,
                                color: const Color(0xFF0074D9).withOpacity(0.6),
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('Customers can scan this to pay directly',
                            style: TextStyle(fontSize: 11,
                                color: Colors.grey.shade400)),
                      ]))),
          if (_pickedQr != null) ...[
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_outline, size: 12, color: Colors.green.shade600),
              const SizedBox(width: 4),
              Text('✓ QR ready — GCash PIN required to save',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade600,
                      fontWeight: FontWeight.w600)),
            ]),
          ],
          const SizedBox(height: 28),

          // ── Save button ───────────────────────────────────────
          SizedBox(width: double.infinity, height: 52,
              child: ElevatedButton(
                  onPressed: _uploading ? null : _save,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4E342E),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                      const Color(0xFF4E342E).withOpacity(0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  child: _uploading
                      ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(Colors.white)))
                      : const Text('Save Changes', style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)))),
        ]),
      ),
    );
  }

  Widget _lbl(bool d, String t) => Align(alignment: Alignment.centerLeft,
      child: Text(t, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: _c(d, Colors.grey.shade600, _D.sub))));

  Widget _fld(bool d, TextEditingController c, String h, IconData ic) =>
      TextField(
          controller: c,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
              color: _c(d, const Color(0xFF2C1A0E), _D.text)),
          decoration: InputDecoration(
              hintText: h,
              hintStyle: TextStyle(color: _c(d, Colors.grey.shade400, _D.sub)),
              prefixIcon: Icon(ic, size: 18,
                  color: _c(d, Colors.grey.shade400, _D.sub)),
              filled: true,
              fillColor: _c(d, const Color(0xFFF6F6F6), _D.fill),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: Color(0xFF4E342E), width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14)));
}

// ─────────────────────────────────────────────────────────────
// IMAGE SOURCE OPTION
// ─────────────────────────────────────────────────────────────

class _SrcOpt extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SrcOpt({
    required this.isDark, required this.icon,
    required this.label, required this.onTap,
  });

  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap,
      child: Column(children: [
        Container(width: 64, height: 64,
            decoration: BoxDecoration(
                color: const Color(0xFF4E342E).withOpacity(isDark ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: const Color(0xFF4E342E).withOpacity(0.2), width: 1.5)),
            child: Icon(icon, size: 28,
                color: _c(isDark, const Color(0xFF4E342E), _D.accent))),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
            color: _c(isDark, const Color(0xFF2C1A0E), _D.text))),
      ]));
}
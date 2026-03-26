import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hidden_drawer_menu/controllers/simple_hidden_drawer_controller.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_settings.dart';
import '../api_service.dart';      // ← added: for changePassword API call

// ─────────────────────────────────────────────────────────────
// DARK / LIGHT TOKENS
// ─────────────────────────────────────────────────────────────

Color _c(bool d, Color light, Color dark) => d ? dark : light;

abstract class _L {
  static const bg      = Color(0xFFF6F6F6);
  static const card    = Colors.white;
  static const text    = Color(0xFF2C1A0E);
  static const sub     = Color(0xFF8D6E63);
  static const accent  = Color(0xFF4E342E);
  static const fill    = Color(0xFFF6F6F6);
  static const divider = Color(0xFFF0E8E0);
}

abstract class _DK {
  static const bg      = Color(0xFF1A0F0A);
  static const card    = Color(0xFF2C1A10);
  static const inner   = Color(0xFF3A2318);
  static const text    = Color(0xFFF5EDE4);
  static const sub     = Color(0xFFB08B72);
  static const accent  = Color(0xFFD4A373);
  static const fill    = Color(0xFF241409);
  static const divider = Color(0xFF3A2318);
}

// ─────────────────────────────────────────────────────────────
// SETTINGS PAGE
// ─────────────────────────────────────────────────────────────

class Settings extends StatefulWidget {
  const Settings({super.key});
  @override State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;
  final _api  = ApiService();           // ← API service instance

  bool _soundEnabled      = true;
  bool _receiptAutoPrint  = false;
  bool _lowStockAlert     = true;
  bool _darkMode          = false;
  int  _lowStockThreshold = 5;
  bool _loading           = true;

  String _provider            = 'password';
  bool   _defaultPasswordUsed = false;
  String _passcode            = '';
  String _passcodeQrToken     = '';

  @override
  void initState() { super.initState(); _loadSettings(); }

  Future<void> _loadSettings() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc  = await _db.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    final s    = (data['settings'] as Map<String, dynamic>?) ?? {};
    if (mounted) setState(() {
      _soundEnabled        = s['soundEnabled']     ?? true;
      _receiptAutoPrint    = s['receiptAutoPrint']  ?? false;
      _lowStockAlert       = s['lowStockAlert']     ?? true;
      _darkMode            = s['darkMode']          ?? false;
      _lowStockThreshold   = s['lowStockThreshold'] ?? 5;
      _provider            = (data['provider']      as String?) ?? 'password';
      _defaultPasswordUsed = (data['defaultPasswordUsed'] as bool?) ?? false;
      _passcode            = (data['passcode']       as String?) ?? '';
      _passcodeQrToken     = (data['passcodeQrToken'] as String?) ?? '';
      _loading             = false;
    });
  }

  Future<void> _save(Map<String, dynamic> updates) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc      = await _db.collection('users').doc(uid).get();
    final existing = (doc.data()?['settings'] as Map<String, dynamic>?) ?? {};
    existing.addAll(updates);
    await _db.collection('users').doc(uid).update({'settings': existing});
  }

  bool get _isSocial => _provider == 'google' || _provider == 'facebook';

  // ─────────────────────────────────────────────────────────
  // CHANGE PASSWORD
  // 1. Reauthenticate with Firebase
  // 2. Update Firebase password
  // 3. Call ApiService.changePassword so local server is also notified
  // 4. Clear defaultPassword flag from Firestore
  // ─────────────────────────────────────────────────────────

  void _changePassword(bool d) {
    final oc = TextEditingController();
    final nc = TextEditingController();
    final cc = TextEditingController();
    bool oo = true, no = true, co = true, saving = false;

    final hint = _isSocial && _defaultPasswordUsed
        ? 'Current password (default: your last name)'
        : 'Current password';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _sheet(d, Column(mainAxisSize: MainAxisSize.min, children: [
            _handle(d),
            _sheetTitle(d, Icons.lock_outline, 'Change Password'),
            const SizedBox(height: 8),
            if (_isSocial && _defaultPasswordUsed)
              _infoBanner(d, 'Your default password is your last name. Enter it to set a new one.'),
            const SizedBox(height: 8),
            _pwField(d, oc, hint,                   oo, () => setS(() => oo = !oo)),
            const SizedBox(height: 12),
            _pwField(d, nc, 'New password',          no, () => setS(() => no = !no)),
            const SizedBox(height: 12),
            _pwField(d, cc, 'Confirm new password',  co, () => setS(() => co = !co)),
            const SizedBox(height: 24),
            _submitBtn(d, 'Update Password', saving, () async {
              if (nc.text != cc.text) {
                _snack(context, 'Passwords do not match', true);
                return;
              }
              if (nc.text.length < 6) {
                _snack(context, 'New password must be at least 6 characters', true);
                return;
              }

              setS(() => saving = true);

              try {
                final user = _auth.currentUser!;


                final cred = EmailAuthProvider.credential(
                    email: user.email!, password: oc.text);
                await user.reauthenticateWithCredential(cred);


                await user.updatePassword(nc.text);


                await _api.changePassword(
                    oldPassword: oc.text, newPassword: nc.text);


                await _db.collection('users').doc(user.uid).update({
                  'defaultPasswordUsed': false,
                  'defaultPassword':     FieldValue.delete(),
                });

                if (mounted) {
                  setState(() => _defaultPasswordUsed = false);
                  Navigator.pop(context);
                  _snack(context, 'Password updated successfully');
                }
              } on FirebaseAuthException catch (e) {
                setS(() => saving = false);


                final code = e.code.toLowerCase();
                final String msg;
                if (code.contains('invalid-credential') ||
                    code.contains('wrong-password') ||
                    code.contains('invalid-password')) {
                  msg = 'Wrong current password. Please try again.';
                } else if (code.contains('too-many-requests')) {
                  msg = 'Too many attempts. Please wait a moment and try again.';
                } else if (code.contains('user-mismatch')) {
                  msg = 'Credential does not match the current account.';
                } else if (code.contains('requires-recent-login')) {
                  msg = 'Session expired. Please log out and log back in first.';
                } else {
                  msg = e.message ?? 'Authentication failed. Please try again.';
                }
                _snack(context, msg, true);

              } catch (e) {
                setS(() => saving = false);
                _snack(context, 'Something went wrong. Please try again.', true);
              }
            }),
          ])),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // GCASH PASSCODE
  // ─────────────────────────────────────────────────────────

  void _changePasscode(bool d) {
    final uid = _auth.currentUser?.uid ?? '';
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false, enableDrag: false,
      builder: (_) => _GcashPasscodeSheet(
        uid: uid, existingPasscode: _passcode,
        existingQrToken: _passcodeQrToken, isDark: d,
        onSaved: (pin, token) {
          if (mounted) setState(() { _passcode = pin; _passcodeQrToken = token; });
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // DELETE ACCOUNT
  // ─────────────────────────────────────────────────────────

  void _deleteAccount(bool d) {
    final pc = TextEditingController(); bool ob = true, del = false;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _sheet(d, Column(mainAxisSize: MainAxisSize.min, children: [
          _handle(d),
          Container(width: 56, height: 56,
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.10), shape: BoxShape.circle),
              child: const Icon(Icons.delete_forever_outlined, color: Colors.red, size: 28)),
          const SizedBox(height: 12),
          const Text('Delete Account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.red)),
          const SizedBox(height: 6),
          Text('This will permanently delete your account and all data.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.5)),
          const SizedBox(height: 20),
          _pwField(d, pc,
              _isSocial && _defaultPasswordUsed ? 'Enter password (default: last name)' : 'Enter password to confirm',
              ob, () => setS(() => ob = !ob)),
          const SizedBox(height: 20),
          _submitBtn(d, 'Delete My Account', del, () async {
            setS(() => del = true);
            try {
              final user = _auth.currentUser!;
              await user.reauthenticateWithCredential(
                  EmailAuthProvider.credential(email: user.email!, password: pc.text));
              await _db.collection('users').doc(user.uid).delete();
              await user.delete();
            } catch (e) { setS(() => del = false); _snack(context, 'Error: $e', true); }
          }, color: Colors.red),
        ])),
      )),
    );
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final d   = AppSettings.of(context).darkMode;
    final bg  = _c(d, _L.bg,     _DK.bg);
    final sub = _c(d, _L.sub,    _DK.sub);
    final acc = _c(d, _L.accent, _DK.accent);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(child: Column(children: [
        _Topbar(isDark: d,
            onMenuTap: () => SimpleHiddenDrawerController.of(context).toggle()),
        if (_loading)
          Expanded(child: Center(child: CircularProgressIndicator(color: acc)))
        else
          Expanded(child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── POS Behavior ──────────────────────────────
              _SecHeader(d, '', 'POS Behavior'),
              _Card(d, [
                _SwitchRow(d, Icons.print_outlined, 'Auto-print Receipt',
                    'Print receipt after every sale', _receiptAutoPrint, (v) {
                      setState(() => _receiptAutoPrint = v); _save({'receiptAutoPrint': v});
                    }),
                _Div(d),
                _SwitchRow(d, Icons.volume_up_outlined, 'Sound Effects',
                    'Play sounds on cart actions', _soundEnabled, (v) {
                      setState(() => _soundEnabled = v); _save({'soundEnabled': v});
                    }),
              ]),
              const SizedBox(height: 20),

              // ── Inventory ─────────────────────────────────
              _SecHeader(d, '', 'Inventory'),
              _Card(d, [
                _SwitchRow(d, Icons.warning_amber_outlined, 'Low Stock Alerts',
                    'Get warned when stock is low', _lowStockAlert, (v) {
                      setState(() => _lowStockAlert = v); _save({'lowStockAlert': v});
                    }),
                _Div(d),
                _StepperRow(d, Icons.numbers_outlined, 'Low Stock Threshold',
                    'Alert when qty falls below', _lowStockThreshold, 1, 50, (v) {
                      setState(() => _lowStockThreshold = v); _save({'lowStockThreshold': v});
                    }),
              ]),
              const SizedBox(height: 20),

              // ── Appearance ────────────────────────────────
              _SecHeader(d, '', 'Appearance'),
              _Card(d, [
                _SwitchRow(d, Icons.dark_mode_outlined, 'Dark Mode',
                    'Coffee-shop dark theme', _darkMode, (v) {
                      setState(() => _darkMode = v); _save({'darkMode': v});
                    }),
              ]),
              const SizedBox(height: 20),

              // ── Security ──────────────────────────────────
              _SecHeader(d, '', 'Security'),
              _Card(d, [
                _ActionRow(d, Icons.lock_outline, 'Change Password', acc,
                    badge: (_isSocial && _defaultPasswordUsed) ? 'Default' : null,
                    sublabel: 'Keep your account secure',
                    onTap: () => _changePassword(d)),
                _Div(d),
                _ActionRow(d, Icons.phonelink_lock_outlined, 'GCash Security',
                    const Color(0xFF0074D9),
                    badge:      _passcode.isEmpty ? 'Not set' : 'Active',
                    badgeColor: _passcode.isEmpty ? Colors.orange : Colors.green,
                    sublabel:   _passcode.isEmpty
                        ? 'Not set — GCash changes are unprotected'
                        : 'Protects GCash number & QR code ',
                    onTap: () => _changePasscode(d)),
                _Div(d),
                _ActionRow(d, Icons.delete_forever_outlined, 'Delete Account', Colors.red,
                    onTap: () => _deleteAccount(d)),
              ]),
              const SizedBox(height: 20),

              // ── Account ───────────────────────────────────
              _SecHeader(d, '', 'Account'),
              _Card(d, [
                _ActionRow(d, Icons.logout_outlined, 'Sign Out', Colors.red,
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: _c(d, Colors.white, _DK.inner),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: Text('Sign Out', style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _c(d, _L.text, _DK.text))),
                          content: Text('Are you sure?',
                              style: TextStyle(color: _c(d, _L.sub, _DK.sub))),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false),
                                child: Text('Cancel', style: TextStyle(color: acc))),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              child: const Text('Sign Out'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await FirebaseAuth.instance.signOut();
                    }),
              ]),
              const SizedBox(height: 12),
              Center(child: Text('☕ BrewPos v1.0.0',
                  style: TextStyle(fontSize: 12, color: sub, fontStyle: FontStyle.italic))),
            ]),
          )),
      ])),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// GCASH PASSCODE SHEET
// ─────────────────────────────────────────────────────────────

class _GcashPasscodeSheet extends StatefulWidget {
  final String uid, existingPasscode, existingQrToken;
  final bool isDark;
  final void Function(String pin, String qrToken) onSaved;
  const _GcashPasscodeSheet({required this.uid, required this.existingPasscode,
    required this.existingQrToken, required this.isDark, required this.onSaved});
  @override State<_GcashPasscodeSheet> createState() => _GPSState();
}

class _GPSState extends State<_GcashPasscodeSheet> {
  late String _stage;
  String _first='', _savedPin='', _savedToken='';
  String? _err;
  final GlobalKey<_NumpadState> _nk = GlobalKey<_NumpadState>();

  @override void initState() {
    super.initState();
    _stage = widget.existingPasscode.isNotEmpty ? 'verify' : 'enter';
  }

  String get _title => switch (_stage) {
    'verify'  => 'Verify Current Passcode',
    'enter'   => widget.existingPasscode.isEmpty ? 'Create GCash PIN' : 'New GCash PIN',
    'confirm' => 'Confirm Passcode',
    _         => 'Passcode Updated!',
  };
  String get _sub => switch (_stage) {
    'verify'  => 'Enter your current 4-digit PIN to continue',
    'enter'   => widget.existingPasscode.isEmpty
        ? 'This PIN protects your GCash number & QR code' : 'Enter your new 4-digit PIN',
    'confirm' => 'Re-enter your new PIN to confirm',
    _         => 'Your GCash security PIN and QR have been saved',
  };

  void _onDigits(String code) {
    setState(() => _err = null);
    switch (_stage) {
      case 'verify':
        if (code == widget.existingPasscode) { setState(() => _stage = 'enter'); }
        else { setState(() => _err = 'Wrong PIN. Try again.'); _nk.currentState?.shakeAndClear(); }
      case 'enter':
        setState(() { _first = code; _stage = 'confirm'; });
      case 'confirm':
        if (code == _first) { _persist(code); }
        else {
          setState(() { _err = "PINs don't match. Try again."; _stage = 'enter'; _first = ''; });
          _nk.currentState?.shakeAndClear();
        }
    }
  }

  Future<void> _persist(String pin) async {
    final ts   = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(99999).toString().padLeft(5, '0');
    final tok  = 'BREWPOS:${widget.uid}:$pin:$ts:$rand';
    await FirebaseFirestore.instance.collection('users').doc(widget.uid).update({
      'passcode':          pin,
      'passcodeQrToken':   tok,
      'passcodeUpdatedAt': FieldValue.serverTimestamp(),
    });
    widget.onSaved(pin, tok);
    setState(() { _savedPin = pin; _savedToken = tok; _stage = 'done'; });
  }

  @override Widget build(BuildContext context) {
    final d    = widget.isDark;
    final done = _stage == 'done';
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.93),
      decoration: BoxDecoration(color: _c(d, const Color(0xFFF6F6F6), _DK.bg),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _handle(d),
        Container(width: 64, height: 64,
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: done
                        ? [Colors.green.shade400, Colors.green.shade700]
                        : [const Color(0xFF0074D9), const Color(0xFF0056A3)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                    color: (done ? Colors.green : const Color(0xFF0074D9)).withOpacity(0.3),
                    blurRadius: 14, offset: const Offset(0, 4))]),
            child: Icon(done ? Icons.check_circle_outline : Icons.phonelink_lock_outlined,
                color: Colors.white, size: 28)),
        const SizedBox(height: 20),

        if (done) ...[
          Text(_title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
              color: _c(d, _L.text, _DK.text))),
          const SizedBox(height: 6),
          Text(_sub, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _c(d, Colors.grey.shade500, _DK.sub))),
          const SizedBox(height: 20),
          _infoBanner(d, 'This PIN is required to edit your GCash number or QR photo in Profile.'),
          const SizedBox(height: 20),
          Container(padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: _c(d, Colors.white, _DK.inner),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(
                      color: const Color(0xFF0074D9).withOpacity(0.08),
                      blurRadius: 16, offset: const Offset(0, 6))]),
              child: Column(children: [
                QrImageView(data: _savedToken, version: QrVersions.auto, size: 180,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0074D9)),
                    dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0074D9))),
                const SizedBox(height: 8),
                Text('Scan to unlock GCash edits in Profile',
                    style: TextStyle(fontSize: 11, color: _c(d, Colors.grey.shade500, _DK.sub))),
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFF0074D9).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.pin_outlined, size: 14, color: Color(0xFF0074D9)),
                      const SizedBox(width: 8),
                      Text('PIN: $_savedPin', style: const TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w800, color: Color(0xFF0074D9), letterSpacing: 4)),
                    ])),
                const SizedBox(height: 10),
                GestureDetector(
                    onTap: () { Clipboard.setData(ClipboardData(text: _savedToken)); _snack(context, 'QR token copied'); },
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.copy_outlined, size: 12, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text('Copy QR token', style: TextStyle(fontSize: 11,
                          color: Colors.grey.shade500, decoration: TextDecoration.underline)),
                    ])),
              ])),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, height: 52,
              child: ElevatedButton(onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white, elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: const Text('Done', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
        ] else ...[
          _Numpad(key: _nk, title: _title, subtitle: _sub,
              accentColor: const Color(0xFF0074D9), isDark: d, onComplete: _onDigits),
          if (_err != null) ...[
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200)),
                child: Row(children: [
                  Icon(Icons.error_outline, color: Colors.red.shade400, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_err!, style: TextStyle(fontSize: 13,
                      color: Colors.red.shade600, fontWeight: FontWeight.w500))),
                ])),
          ],
          const SizedBox(height: 20),
          TextButton(onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(
                  color: Colors.grey.shade500, fontSize: 14, fontWeight: FontWeight.w600))),
        ],
      ])),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// NUMPAD WIDGET
// ─────────────────────────────────────────────────────────────

class _Numpad extends StatefulWidget {
  final String title, subtitle; final Color accentColor;
  final bool isDark; final void Function(String) onComplete;
  const _Numpad({required super.key, required this.title, required this.subtitle,
    required this.accentColor, required this.isDark, required this.onComplete});
  @override State<_Numpad> createState() => _NumpadState();
}

class _NumpadState extends State<_Numpad> with SingleTickerProviderStateMixin {
  String _code = '';
  late AnimationController _sc; late Animation<double> _sa;
  @override void initState() {
    super.initState();
    _sc = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _sa = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _sc, curve: Curves.elasticIn));
  }
  @override void dispose() { _sc.dispose(); super.dispose(); }
  void _press(String d) {
    if (_code.length >= 4) return; setState(() => _code += d);
    if (_code.length == 4) Future.delayed(const Duration(milliseconds: 120),
            () => widget.onComplete(_code));
  }
  void _del() { if (_code.isEmpty) return; setState(() => _code = _code.substring(0, _code.length - 1)); }
  void shakeAndClear() { _sc.forward(from: 0).then((_) { if (mounted) setState(() => _code = ''); }); }

  @override Widget build(BuildContext context) {
    final d = widget.isDark;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(widget.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
          color: _c(d, _L.text, _DK.text), fontFamily: 'playwrite')),
      const SizedBox(height: 6),
      Text(widget.subtitle, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: _c(d, Colors.grey.shade500, _DK.sub))),
      const SizedBox(height: 28),
      AnimatedBuilder(animation: _sa,
          builder: (_, child) => Transform.translate(
              offset: Offset(_sa.value * 10 * (_sa.value < 0.5 ? 1 : -1), 0), child: child),
          child: Row(mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final on = i < _code.length;
                return AnimatedContainer(duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: on ? 18 : 16, height: on ? 18 : 16,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: on ? widget.accentColor : Colors.transparent,
                        border: Border.all(
                            color: on ? widget.accentColor : Colors.grey.shade400, width: 2),
                        boxShadow: on ? [BoxShadow(color: widget.accentColor.withOpacity(0.4),
                            blurRadius: 6, offset: const Offset(0, 2))] : []));
              }))),
      const SizedBox(height: 32),
      SizedBox(width: 260, child: Column(children: [
        _row(d, ['1','2','3']), const SizedBox(height: 14),
        _row(d, ['4','5','6']), const SizedBox(height: 14),
        _row(d, ['7','8','9']), const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          const SizedBox(width: 72), _key(d, '0'), _delKey(d),
        ]),
      ])),
    ]);
  }
  Widget _row(bool d, List<String> ds) => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: ds.map((x) => _key(d, x)).toList());
  Widget _key(bool d, String digit) => GestureDetector(onTap: () => _press(digit),
      child: Container(width: 72, height: 60,
          decoration: BoxDecoration(color: _c(d, Colors.white, _DK.inner),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(d ? 0.3 : 0.06),
                  blurRadius: 8, offset: const Offset(0, 3))]),
          child: Center(child: Text(digit, style: TextStyle(fontSize: 22,
              fontWeight: FontWeight.w700, color: _c(d, _L.text, _DK.text))))));
  Widget _delKey(bool d) => GestureDetector(onTap: _del,
      child: Container(width: 72, height: 60,
          decoration: BoxDecoration(color: _c(d, Colors.grey.shade100, _DK.card),
              borderRadius: BorderRadius.circular(16)),
          child: Icon(Icons.backspace_outlined, size: 22,
              color: _c(d, Colors.grey.shade500, _DK.sub))));
}

// ─────────────────────────────────────────────────────────────
// REUSABLE SHEET HELPERS
// ─────────────────────────────────────────────────────────────

Widget _sheet(bool d, Widget child) => Container(
  decoration: BoxDecoration(color: _c(d, Colors.white, _DK.card),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
  child: child,
);

Widget _handle(bool d) => Container(width: 40, height: 4,
    margin: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(color: _c(d, Colors.grey.shade300, _DK.inner),
        borderRadius: BorderRadius.circular(2)));

Widget _sheetTitle(bool d, IconData icon, String title) => Row(children: [
  Container(padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: _c(d, _L.accent, _DK.accent).withOpacity(0.10),
          borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: _c(d, _L.accent, _DK.accent), size: 18)),
  const SizedBox(width: 10),
  Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
      color: _c(d, _L.text, _DK.text))),
]);

Widget _infoBanner(bool d, String msg) => Container(
  margin: const EdgeInsets.only(bottom: 12),
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  decoration: BoxDecoration(
      color: _c(d, _L.accent, _DK.accent).withOpacity(0.08),
      borderRadius: BorderRadius.circular(12)),
  child: Row(children: [
    Icon(Icons.info_outline, size: 16, color: _c(d, _L.accent, _DK.accent)),
    const SizedBox(width: 8),
    Expanded(child: Text(msg, style: TextStyle(fontSize: 11,
        color: _c(d, Colors.brown.shade600, _DK.sub), height: 1.4))),
  ]),
);

Widget _pwField(bool d, TextEditingController ctrl, String hint,
    bool obscure, VoidCallback onToggle) =>
    TextField(
      controller: ctrl, obscureText: obscure,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
          color: _c(d, _L.text, _DK.text)),
      decoration: InputDecoration(
          hintText: hint, hintStyle: TextStyle(color: _c(d, Colors.grey.shade400, _DK.sub)),
          prefixIcon: Icon(Icons.lock_outline, size: 18, color: _c(d, _L.sub, _DK.sub)),
          suffixIcon: IconButton(onPressed: onToggle,
              icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 18, color: _c(d, Colors.grey.shade400, _DK.sub))),
          filled: true, fillColor: _c(d, _L.fill, _DK.bg),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _c(d, _L.accent, _DK.accent), width: 1.5))),
    );

Widget _submitBtn(bool d, String label, bool loading, VoidCallback onTap, {Color? color}) =>
    SizedBox(width: double.infinity, height: 52,
        child: ElevatedButton(
            onPressed: loading ? null : onTap,
            style: ElevatedButton.styleFrom(
                backgroundColor: color ?? _c(d, _L.accent, _DK.accent),
                foregroundColor: Colors.white, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: loading
                ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(Colors.white)))
                : Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))));

void _snack(BuildContext ctx, String msg, [bool err = false]) =>
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: err ? Colors.red : const Color(0xFF4E342E),
        behavior: SnackBarBehavior.floating));

// ─────────────────────────────────────────────────────────────
// WIDGET PRIMITIVES
// ─────────────────────────────────────────────────────────────

Widget _SecHeader(bool d, String icon, String title) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Row(children: [
    Text(icon, style: const TextStyle(fontSize: 16)),
    const SizedBox(width: 8),
    Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
        color: _c(d, _L.sub, _DK.sub), letterSpacing: 0.5)),
  ]),
);

Widget _Card(bool d, List<Widget> children) => Container(
  decoration: BoxDecoration(
      color: _c(d, Colors.white, _DK.card), borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(
          color: const Color(0xFF4E342E).withOpacity(d ? 0.25 : 0.06),
          blurRadius: 16, offset: const Offset(0, 6))]),
  child: Column(children: children),
);

Widget _Div(bool d) => Divider(height: 1, indent: 56, endIndent: 16,
    color: _c(d, Colors.grey.shade100, _DK.divider));

class _SwitchRow extends StatelessWidget {
  final bool d; final IconData icon; final String label, sub;
  final bool val; final ValueChanged<bool> onChange;
  const _SwitchRow(this.d, this.icon, this.label, this.sub, this.val, this.onChange);
  @override Widget build(BuildContext ctx) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Container(width: 36, height: 36,
          decoration: BoxDecoration(
              color: _c(d, _L.accent, _DK.accent).withOpacity(0.10),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: _c(d, _L.accent, _DK.accent))),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
            color: _c(d, _L.text, _DK.text))),
        Text(sub, style: TextStyle(fontSize: 11,
            color: _c(d, Colors.grey.shade500, _DK.sub))),
      ])),
      Switch(value: val, onChanged: onChange,
          activeColor: _c(d, _L.accent, _DK.accent),
          activeTrackColor: _c(d, _L.sub, _DK.sub).withOpacity(0.4)),
    ]),
  );
}

class _StepperRow extends StatelessWidget {
  final bool d; final IconData icon; final String label, sub;
  final int val, min, max; final ValueChanged<int> onChange;
  const _StepperRow(this.d, this.icon, this.label, this.sub, this.val, this.min, this.max, this.onChange);
  @override Widget build(BuildContext ctx) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Container(width: 36, height: 36,
          decoration: BoxDecoration(
              color: _c(d, _L.accent, _DK.accent).withOpacity(0.10),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: _c(d, _L.accent, _DK.accent))),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
            color: _c(d, _L.text, _DK.text))),
        Text(sub, style: TextStyle(fontSize: 11, color: _c(d, Colors.grey.shade500, _DK.sub))),
      ])),
      Row(children: [
        _sb(d, Icons.remove, val <= min ? null : () => onChange(val - 1)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('$val', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                color: _c(d, _L.text, _DK.text)))),
        _sb(d, Icons.add, val >= max ? null : () => onChange(val + 1)),
      ]),
    ]),
  );
  Widget _sb(bool d, IconData ic, VoidCallback? cb) => GestureDetector(onTap: cb,
      child: Container(width: 28, height: 28,
          decoration: BoxDecoration(
              color: cb == null ? _c(d, Colors.grey.shade100, _DK.inner)
                  : _c(d, _L.accent, _DK.accent).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(ic, size: 16,
              color: cb == null ? _c(d, Colors.grey.shade300, _DK.sub)
                  : _c(d, _L.accent, _DK.accent))));
}

class _ActionRow extends StatelessWidget {
  final bool d; final IconData icon; final String label;
  final Color color; final VoidCallback onTap;
  final String? badge, sublabel; final Color? badgeColor;
  const _ActionRow(this.d, this.icon, this.label, this.color,
      {required this.onTap, this.badge, this.sublabel, this.badgeColor});

  @override Widget build(BuildContext ctx) => GestureDetector(onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(width: 36, height: 36,
                decoration: BoxDecoration(color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: color)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: (badgeColor ?? Colors.orange).withOpacity(0.13),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(badge!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: badgeColor ?? Colors.orange))),
                ],
              ]),
              if (sublabel != null)
                Text(sublabel!, style: TextStyle(fontSize: 11,
                    color: _c(d, Colors.grey.shade500, _DK.sub), height: 1.4)),
            ])),
            Icon(Icons.chevron_right, color: color.withOpacity(0.5)),
          ])));
}

// ─────────────────────────────────────────────────────────────
// TOPBAR
// ─────────────────────────────────────────────────────────────

class _Topbar extends StatelessWidget {
  final bool isDark; final VoidCallback onMenuTap;
  const _Topbar({required this.isDark, required this.onMenuTap});

  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: SizedBox(height: 56, child: Stack(alignment: Alignment.center, children: [
      Align(alignment: Alignment.centerLeft,
          child: IconButton(onPressed: onMenuTap,
              icon: Icon(Icons.menu, color: _c(isDark, _L.text, _DK.accent)))),
      Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
          fontFamily: 'playwrite', color: _c(isDark, _L.text, _DK.accent))),
    ])),
  );
}
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────

class AppSettingsData {
  final bool soundEnabled;
  final bool receiptAutoPrint;
  final bool lowStockAlert;
  final bool darkMode;
  final int  lowStockThreshold;

  const AppSettingsData({
    this.soundEnabled      = true,
    this.receiptAutoPrint  = false,
    this.lowStockAlert     = true,
    this.darkMode          = false,
    this.lowStockThreshold = 5,
  });

  factory AppSettingsData.fromMap(Map<String, dynamic> s) => AppSettingsData(
    soundEnabled:      s['soundEnabled']     as bool? ?? true,
    receiptAutoPrint:  s['receiptAutoPrint']  as bool? ?? false,
    lowStockAlert:     s['lowStockAlert']     as bool? ?? true,
    darkMode:          s['darkMode']          as bool? ?? false,
    lowStockThreshold: s['lowStockThreshold'] as int?  ?? 5,
  );
}

// ─────────────────────────────────────────────────────────────
// INHERITED SCOPE
// ─────────────────────────────────────────────────────────────

class _AppSettingsScope extends InheritedWidget {
  final AppSettingsData data;
  const _AppSettingsScope({required this.data, required super.child});

  @override
  bool updateShouldNotify(_AppSettingsScope old) =>
      data.darkMode          != old.data.darkMode          ||
          data.soundEnabled      != old.data.soundEnabled      ||
          data.lowStockAlert     != old.data.lowStockAlert     ||
          data.lowStockThreshold != old.data.lowStockThreshold ||
          data.receiptAutoPrint  != old.data.receiptAutoPrint;
}

// ─────────────────────────────────────────────────────────────
// PROVIDER — wrap above MaterialApp
// ─────────────────────────────────────────────────────────────

class AppSettings extends StatefulWidget {
  final Widget child;
  const AppSettings({super.key, required this.child});

  static AppSettingsData of(BuildContext context) {
    final scope =
    context.dependOnInheritedWidgetOfExactType<_AppSettingsScope>();
    return scope?.data ?? const AppSettingsData();
  }

  /// Listen to this from MaterialApp to switch themes instantly
  static final ValueNotifier<ThemeMode> themeMode =
  ValueNotifier(ThemeMode.light);

  @override
  State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  AppSettingsData _data = const AppSettingsData();
  StreamSubscription? _authSub;
  StreamSubscription? _docSub;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _docSub?.cancel();
      if (user == null) {
        setState(() => _data = const AppSettingsData());
        AppSettings.themeMode.value = ThemeMode.light;
        return;
      }
      _docSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        final raw = snap.data() ?? {};
        final s   = (raw['settings'] as Map<String, dynamic>?) ?? {};
        final nd  = AppSettingsData.fromMap(s);
        setState(() => _data = nd);
        AppSettings.themeMode.value =
        nd.darkMode ? ThemeMode.dark : ThemeMode.light;
      });
    });
  }

  @override
  void dispose() {
    _docSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _AppSettingsScope(data: _data, child: widget.child);
}
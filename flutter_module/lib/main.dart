import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';

import 'app_settings.dart';
import 'hidden_drawer.dart';
import 'native_login.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'page/home.dart';
import 'page/catergories.dart';
import 'page/profile.dart';
import 'sound_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await SoundService.init();
  runApp(const MyApp());
}

// ─────────────────────────────────────────────────────────────
// COFFEE-SHOP COLOUR TOKENS
// ─────────────────────────────────────────────────────────────

abstract class BrewColors {
  // light
  static const espresso = Color(0xFF2C1A0E);
  static const roast    = Color(0xFF4E342E);
  static const caramel  = Color(0xFF8D6E63);
  static const latte    = Color(0xFFD4A373);
  static const cream    = Color(0xFFFDF6F1);
  static const steam    = Color(0xFFF5EDE4);
  // dark
  static const darkBg      = Color(0xFF1A0F0A);   // deep espresso
  static const darkSurface = Color(0xFF2C1A10);   // roast
  static const darkCard    = Color(0xFF3A2318);   // mocha
  static const darkText    = Color(0xFFF5EDE4);   // warm cream
  static const darkSub     = Color(0xFFB08B72);   // muted caramel
  static const darkAccent  = Color(0xFFD4A373);   // latte highlight
}

// ─────────────────────────────────────────────────────────────
// THEMES
// ─────────────────────────────────────────────────────────────

ThemeData _lightTheme() => ThemeData(
  useMaterial3:            true,
  brightness:              Brightness.light,
  scaffoldBackgroundColor: const Color(0xFFF6F6F6),
  colorScheme: ColorScheme.fromSeed(
    seedColor:  BrewColors.roast,
    brightness: Brightness.light,
    primary:    BrewColors.roast,
    secondary:  BrewColors.caramel,
    surface:    BrewColors.cream,
    onPrimary:  Colors.white,
    onSurface:  BrewColors.espresso,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: BrewColors.cream,
    foregroundColor: BrewColors.espresso,
    elevation: 0,
    centerTitle: true,
  ),
  cardTheme: CardThemeData(
    color: BrewColors.cream,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? BrewColors.roast : Colors.grey.shade400),
    trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
            ? BrewColors.caramel.withValues(alpha: 0.4) : Colors.grey.shade200),
  ),
  iconTheme:   const IconThemeData(color: BrewColors.roast),
  dividerColor: BrewColors.steam,
  fontFamily:  'Inter',
  textTheme: const TextTheme(
    displayLarge:  TextStyle(color: BrewColors.espresso, fontWeight: FontWeight.w800),
    displayMedium: TextStyle(color: BrewColors.espresso, fontWeight: FontWeight.w700),
    bodyLarge:     TextStyle(color: BrewColors.espresso),
    bodyMedium:    TextStyle(color: BrewColors.espresso),
    labelLarge:    TextStyle(color: BrewColors.espresso, fontWeight: FontWeight.w700),
  ),
);

ThemeData _darkTheme() => ThemeData(
  useMaterial3:            true,
  brightness:              Brightness.dark,
  scaffoldBackgroundColor: BrewColors.darkBg,
  colorScheme: ColorScheme.fromSeed(
    seedColor:   BrewColors.roast,
    brightness:  Brightness.dark,
    primary:     BrewColors.darkAccent,
    secondary:   BrewColors.caramel,
    surface:     BrewColors.darkSurface,
    onPrimary:   BrewColors.espresso,
    onSurface:   BrewColors.darkText,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: BrewColors.darkSurface,
    foregroundColor: BrewColors.darkText,
    elevation: 0,
    centerTitle: true,
  ),
  cardTheme: CardThemeData(
    color: BrewColors.darkCard,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? BrewColors.darkAccent : Colors.grey.shade600),
    trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
            ? BrewColors.caramel.withValues(alpha: 0.45) : Colors.grey.shade800),
  ),
  iconTheme:    const IconThemeData(color: BrewColors.darkAccent),
  dividerColor: BrewColors.darkCard,
  fontFamily:   'Inter',
  textTheme: const TextTheme(
    displayLarge:  TextStyle(color: BrewColors.darkText, fontWeight: FontWeight.w800),
    displayMedium: TextStyle(color: BrewColors.darkText, fontWeight: FontWeight.w700),
    bodyLarge:     TextStyle(color: BrewColors.darkText),
    bodyMedium:    TextStyle(color: BrewColors.darkText),
    labelLarge:    TextStyle(color: BrewColors.darkText, fontWeight: FontWeight.w700),
  ),
);

// ─────────────────────────────────────────────────────────────
// ROOT
// ─────────────────────────────────────────────────────────────

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSettings(
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: AppSettings.themeMode,
        builder: (_, mode, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme:     _lightTheme(),
          darkTheme: _darkTheme(),
          themeMode: mode,           // ← flips instantly on toggle
          home: const AuthGate(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AUTH GATE
// ─────────────────────────────────────────────────────────────

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasData) return const AppHiddenDrawer();
        Future.microtask(() => NativeLogin.openLogin());
        return const Scaffold(
            body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BOTTOM NAV HOST
// ─────────────────────────────────────────────────────────────

class BrewPosHome extends StatefulWidget {
  const BrewPosHome({super.key});

  @override
  State<BrewPosHome> createState() => _BrewPosHomeState();
}

class _BrewPosHomeState extends State<BrewPosHome> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [
    const Home(),
    const Categories(),
    const Profile(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.of(context).darkMode;
    return Scaffold(
      extendBody:      true,
      backgroundColor: Colors.transparent,
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: CurvedNavigationBar(
        index:    _selectedIndex,
        onTap:    (i) => setState(() => _selectedIndex = i),
        items: const [
          Icon(Icons.home,              color: Colors.white, size: 24),
          Icon(Icons.grid_view_rounded, color: Colors.white, size: 24),
          Icon(Icons.person_outline,    color: Colors.white, size: 24),
        ],
        color:                isDark ? BrewColors.darkCard : const Color(0xFF6F4E37),
        backgroundColor:      Colors.transparent,
        buttonBackgroundColor: isDark ? BrewColors.darkSurface : const Color(0xFF6F4E37),
      ),
    );
  }
}

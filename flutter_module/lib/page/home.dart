import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hidden_drawer_menu/hidden_drawer_menu.dart';
import 'package:intl/intl.dart';

import '../app_settings.dart';
import '../firestore_service.dart';

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
}

// ─────────────────────────────────────────────────────────────
// SOUND HELPER
// ─────────────────────────────────────────────────────────────
// Place assets/sounds/cart_add.mp3 and checkout.mp3 in your project
// and declare them under flutter > assets in pubspec.yaml.

class _Sound {
  static final _player = AudioPlayer();
  static Future<void> cartAdd()   async { try { await _player.play(AssetSource('sounds/cart_add.mp3'));   } catch (_) {} }
  static Future<void> checkout()  async { try { await _player.play(AssetSource('sounds/checkout.mp3'));   } catch (_) {} }
}

// ─────────────────────────────────────────────────────────────
// HOME PAGE
// ─────────────────────────────────────────────────────────────

class Home extends StatefulWidget {
  const Home({super.key});
  @override State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _fs  = FirestoreService();
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // sales
  double _totalSales = 0, _todaySales = 0, _last7Days = 0;
  bool   _salesLoading = true;

  // featured
  List<Map<String, dynamic>> _featured = [];
  bool _featuredLoading = true;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _featuredSub;

  // carousel
  final _pageCtrl = PageController(viewportFraction: 0.78);
  Timer? _scrollTimer;
  int _currentPage = 0;

  // low-stock alert (shown once per session)
  StreamSubscription<List<Map<String, dynamic>>>? _invSub;
  bool _alertShown = false;

  @override
  void initState() {
    super.initState();
    _loadSales();
    _subscribeToFeatured();
    _startAutoScroll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _invSub?.cancel();
    _subscribeToInventoryAlerts();
  }

  @override
  void dispose() {
    _featuredSub?.cancel();
    _invSub?.cancel();
    _scrollTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── inventory low-stock subscription ─────────────────────
  void _subscribeToInventoryAlerts() {
    final s = AppSettings.of(context);
    if (!s.lowStockAlert) return;

    _invSub = _fs.watchInventoryMerged(_uid).listen((items) {
      if (!mounted || _alertShown) return;
      final thr   = s.lowStockThreshold;
      final low   = items.where((d) { final q = (d['stockQty'] ?? 0) as int; return q > 0 && q <= thr; }).toList();
      final out   = items.where((d) { final q = (d['stockQty'] ?? 0) as int; return q <= 0; }).toList();
      if (low.isEmpty && out.isEmpty) return;
      _alertShown = true;
      final total = low.length + out.length;
      final label = total == 1
          ? '"${(low.isNotEmpty ? low : out).first['name']}"'
          : '$total items';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration:  const Duration(seconds: 6),
        behavior:  SnackBarBehavior.floating,
        margin:    const EdgeInsets.fromLTRB(16, 0, 16, 90),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFF4E342E),
        content: Row(children: [
          Container(padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFFFCC80), size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Low Stock Alert',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFFFFCC80))),
                Text('$label ${total == 1 ? 'is' : 'are'} running low.',
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ])),
        ]),
        action: SnackBarAction(label: 'Dismiss', textColor: const Color(0xFFD4A373), onPressed: () {}),
      ));
    });
  }

  // ── featured stream ───────────────────────────────────────
  void _subscribeToFeatured() {
    _featuredSub = _fs.watchProducts().listen((snap) {
      if (!mounted) return;
      final docs = snap.docs
          .where((d) => (d.data()['source'] ?? 'product').toString() != 'inventory')
          .take(10)
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
      setState(() {
        _featured = docs;
        _featuredLoading = false;
        if (_currentPage >= _featured.length && _featured.isNotEmpty)
          _currentPage = _featured.length - 1;
      });
    }, onError: (_) { if (mounted) setState(() => _featuredLoading = false); });
  }

  void _startAutoScroll() {
    _scrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _featured.isEmpty) return;
      _currentPage = (_currentPage + 1) % _featured.length;
      if (_pageCtrl.hasClients) {
        _pageCtrl.animateToPage(_currentPage,
            duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
      }
    });
  }

  Future<void> _loadSales() async {
    try {
      final now   = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final week  = today.subtract(const Duration(days: 7));
      final snap  = await FirebaseFirestore.instance
          .collection('users').doc(_uid).collection('sales').get();
      double tot = 0, tdy = 0, wk = 0;
      for (final d in snap.docs) {
        final data   = d.data();
        final amount = (data['total'] ?? data['amount'] ?? 0).toDouble();
        final ts     = (data['createdAt'] as Timestamp?)?.toDate();
        tot += amount;
        if (ts != null) {
          if (!ts.isBefore(today)) tdy += amount;
          if (!ts.isBefore(week))  wk  += amount;
        }
      }
      if (mounted) setState(() { _totalSales = tot; _todaySales = tdy; _last7Days = wk; _salesLoading = false; });
    } catch (_) { if (mounted) setState(() => _salesLoading = false); }
  }

  // Public helpers — call from cart/checkout buttons
  Future<void> playCartSound()     async { if (AppSettings.of(context).soundEnabled) await _Sound.cartAdd(); }
  Future<void> playCheckoutSound() async { if (AppSettings.of(context).soundEnabled) await _Sound.checkout(); }

  @override
  Widget build(BuildContext context) {
    final s    = AppSettings.of(context);
    final d    = s.darkMode;
    final bg   = _c(d, const Color(0xFFF6F6F6), _D.bg);
    final text = _c(d, const Color(0xFF2C1A0E), _D.text);
    final sub  = _c(d, Colors.grey.shade500, _D.sub);
    final bar  = _c(d, const Color(0xFFD4A373), const Color(0xFFC8A27A));

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 10),
          _TopBar(isDark: d,
              onMenuTap: () => SimpleHiddenDrawerController.of(context).toggle()),
          const SizedBox(height: 20),
          _HeroBanner(),
          const SizedBox(height: 24),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _SalesSection(isDark: d, loading: _salesLoading,
                  totalSales: _totalSales, todaySales: _todaySales, last7Days: _last7Days)),
          const SizedBox(height: 28),

          // Featured header
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                Container(width: 4, height: 20,
                    decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Text('Featured Products',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: text)),
                const Spacer(),
                if (!_featuredLoading) Row(children: [
                  Container(width: 7, height: 7,
                      decoration: const BoxDecoration(color: Color(0xFF6BCF7F), shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('Live', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sub)),
                ]),
              ])),
          const SizedBox(height: 16),

          // Featured carousel
          _featuredLoading
              ? SizedBox(height: 220, child: Center(child: CircularProgressIndicator(color: _c(d, const Color(0xFF4E342E), _D.accent))))
              : _featured.isEmpty
              ? SizedBox(height: 220, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('☕', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            Text('No products yet.\nAdd one in the Products tab.',
                textAlign: TextAlign.center, style: TextStyle(color: sub, fontSize: 13)),
          ])))
              : SizedBox(height: 220, child: PageView.builder(
              controller: _pageCtrl, itemCount: _featured.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) => _FeaturedCard(item: _featured[i]))),

          // dots
          if (_featured.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_featured.length, (i) {
                  final active = i == _currentPage;
                  return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 20 : 6, height: 6,
                      decoration: BoxDecoration(
                          color: active ? const Color(0xFF4E342E) : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(3)));
                })),
          ],
          const SizedBox(height: 28),

          // Quick Stats header
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                Container(width: 4, height: 20,
                    decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Text('Quick Stats', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: text)),
              ])),
          const SizedBox(height: 14),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                Expanded(child: _StatCard(isDark: d, icon: Icons.trending_up,
                    label: 'Best Day', value: 'Today', color: const Color(0xFF4E342E))),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(isDark: d, icon: Icons.coffee,
                    label: 'Top Category', value: 'Coffee', color: const Color(0xFF6A3FA6))),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(isDark: d, icon: Icons.star_outline,
                    label: 'Rating', value: '4.9 ★', color: const Color(0xFFE65100))),
              ])),
          const SizedBox(height: 100),
        ]),
      )),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool isDark; final VoidCallback onMenuTap;
  const _TopBar({required this.isDark, required this.onMenuTap});
  @override Widget build(_) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: SizedBox(height: 50, child: Stack(alignment: Alignment.center, children: [
        Align(alignment: Alignment.centerLeft,
            child: IconButton(onPressed: onMenuTap,
                icon: Icon(Icons.menu, color: _c(isDark, const Color(0xFF2C1A0E), _D.accent)))),
        Text('BrewPos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
            fontFamily: 'playwrite', color: _c(isDark, const Color(0xFF2C1A0E), _D.accent))),
      ])));
}

// ─────────────────────────────────────────────────────────────
// HERO BANNER
// ─────────────────────────────────────────────────────────────

class _HeroBanner extends StatefulWidget {
  const _HeroBanner({super.key});
  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  late Timer _timer;
@override
void initState() {
  super.initState();
  _timer = Timer.periodic(const Duration(minutes: 1),(_){
    if(mounted) setState(() {});
  });
}
  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _greeting(){
  final hour =DateTime.now().hour;
  if(hour<12) return '☕ Good Morning!';
  if(hour<17) return '☕ Good Afternoon!';
  if(hour<21) return '🌙 Good Evening!';
  return '🌙 Good Night!';

  }

  @override Widget build(_) => Container(
      height: 180,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: const Color(0xFF4E342E).withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8))]),
      child: ClipRRect(borderRadius: BorderRadius.circular(24),
          child: Stack(fit: StackFit.expand, children: [
            Image.network('https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=1200',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: const Color(0xFF4E342E))),
            Container(decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.centerLeft, end: Alignment.centerRight,
                colors: [const Color(0xFF2C1A0E).withOpacity(0.85), Colors.transparent]))),
            Padding(padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.brown.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(_greeting(),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
                      const SizedBox(height: 8),
                      const Text('Welcome to\nBrewPos', style: TextStyle(fontSize: 22,
                          fontWeight: FontWeight.w800, color: Colors.white, fontFamily: 'playwrite', height: 1.2)),
                      const SizedBox(height: 4),
                      Text('Your coffee shop dashboard',
                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.75))),
                    ])),
          ])));
}

// ─────────────────────────────────────────────────────────────
// SALES SECTION
// ─────────────────────────────────────────────────────────────

class _SalesSection extends StatelessWidget {
  final bool isDark, loading;
  final double totalSales, todaySales, last7Days;
  const _SalesSection({required this.isDark, required this.loading,
    required this.totalSales, required this.todaySales, required this.last7Days});

  @override Widget build(_) {
    final d = isDark;
    final text = _c(d, const Color(0xFF2C1A0E), _D.text);
    final bar  = _c(d, const Color(0xFFC8A27A), _D.accent);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 4, height: 20,
            decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text('Sales Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: text)),
      ]),
      const SizedBox(height: 14),
      _BigCard(d: d, loading: loading, value: totalSales, label: 'Total Sales (All Time)',
          icon: Icons.account_balance_wallet_outlined,
          gradient: const [Color(0xFF4E342E), Color(0xFF8D6E63)]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _SmallCard(d: d, loading: loading, value: todaySales,
            label: 'Today', icon: Icons.today_outlined, color: const Color(0xFF6BCF7F))),
        const SizedBox(width: 12),
        Expanded(child: _SmallCard(d: d, loading: loading, value: last7Days,
            label: 'Last 7 Days', icon: Icons.date_range_outlined,
            color: _c(d, const Color(0xFF4B2E2B), const Color(0xFF8D6E63)))),
      ]),
    ]);
  }
}

class _BigCard extends StatelessWidget {
  final bool d, loading; final double value; final String label;
  final IconData icon; final List<Color> gradient;
  const _BigCard({required this.d, required this.loading, required this.value,
    required this.label, required this.icon, required this.gradient});
  @override Widget build(_) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: gradient.first.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))]),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Colors.white, size: 28)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          loading
              ? Container(height: 28, width: 120,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)))
              : Text('₱ ${NumberFormat('#,##0.00').format(value)}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
        ])),
        Icon(Icons.trending_up, color: Colors.white.withOpacity(0.5), size: 32),
      ]));
}

class _SmallCard extends StatelessWidget {
  final bool d, loading; final double value; final String label;
  final IconData icon; final Color color;
  const _SmallCard({required this.d, required this.loading, required this.value,
    required this.label, required this.icon, required this.color});
  @override Widget build(_) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _c(d, Colors.white, _D.card),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: color.withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 5))],
          border: Border.all(color: color.withOpacity(0.15), width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 16)),
          const Spacer(),
          Icon(Icons.arrow_upward, size: 14, color: color.withOpacity(0.6)),
        ]),
        const SizedBox(height: 10),
        loading
            ? Container(height: 20, width: 80,
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)))
            : Text('₱${NumberFormat('#,##0.00').format(value)}',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11,
            color: _c(d, Colors.grey.shade500, _D.sub), fontWeight: FontWeight.w500)),
      ]));
}

// ─────────────────────────────────────────────────────────────
// FEATURED CARD
// ─────────────────────────────────────────────────────────────

class _FeaturedCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _FeaturedCard({required this.item});

  static const _fb = [
    'https://images.unsplash.com/photo-1541167760496-1628856ab772?w=800',
    'https://images.unsplash.com/photo-1511920170033-f8396924c348?w=800',
    'https://images.unsplash.com/photo-1542444459-db63c9d72f9c?w=800',
    'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=800',
  ];
  String _fallback(int i) => _fb[i % _fb.length];
  Color  _color(String s) { final l = s.toLowerCase(); if (l.contains('coffee')) return const Color(0xFF4E342E); if (l.contains('milktea')) return const Color(0xFF6A3FA6); if (l.contains('snack')) return const Color(0xFFE65100); return const Color(0xFF2E7D3A); }
  String _icon (String s) { final l = s.toLowerCase(); if (l.contains('coffee')) return '☕'; if (l.contains('milktea')) return '🧋'; if (l.contains('snack')) return '🍿'; return '🛍'; }

  @override Widget build(_) {
    final name  = (item['name']      ?? 'Product').toString();
    final sec   = (item['section']   ?? '').toString();
    final price = (item['sellPrice'] ?? item['price'] ?? 0).toDouble();
    final url   = (item['imageUrl']  ?? '').toString().trim();
    final color = _color(sec);
    final idx   = (item['id'] as String).hashCode.abs();
    return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8))]),
        child: ClipRRect(borderRadius: BorderRadius.circular(24),
            child: Stack(fit: StackFit.expand, children: [
              url.isEmpty
                  ? Image.network(_fallback(idx), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: color.withOpacity(0.3)))
                  : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Image.network(_fallback(idx), fit: BoxFit.cover)),
              Container(decoration: BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, color.withOpacity(0.92)], stops: const [0.4, 1.0]))),
              Padding(padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Align(alignment: Alignment.topRight,
                            child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white.withOpacity(0.3))),
                                child: Text('${_icon(sec)} $sec',
                                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)))),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                                  color: Colors.white, fontFamily: 'playwrite')),
                          const SizedBox(height: 6),
                          Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(color: const Color(0xFF4E342E).withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFD4A373).withOpacity(0.5))),
                              child: Text('₱ ${price.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFD4A373)))),
                        ]),
                      ])),
            ])));
  }
}

// ─────────────────────────────────────────────────────────────
// QUICK STAT CARD
// ─────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final bool isDark; final IconData icon; final String label, value; final Color color;
  const _StatCard({required this.isDark, required this.icon, required this.label, required this.value, required this.color});
  @override Widget build(_) => Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
          color: _c(isDark, Colors.white, _D.card),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18)),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: _c(isDark, Colors.grey.shade500, _D.sub))),
      ]));
}

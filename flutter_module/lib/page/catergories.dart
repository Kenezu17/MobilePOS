import 'dart:math';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hidden_drawer_menu/hidden_drawer_menu.dart';

import '../firestore_service.dart';
import '../app_settings.dart';
import '../api_service.dart';      // ← added for resolveImageUrl
import '../sound_service.dart';

// ─────────────────────────────────────────────────────────────
// DARK / LIGHT COLOR TOKENS
// ─────────────────────────────────────────────────────────────

Color _c(bool d, Color light, Color dark) => d ? dark : light;

abstract class _L {
  static const bg      = Color(0xFFF6F6F6);
  static const text    = Color(0xFF2C1A0E);
  static const accent  = Color(0xFF4E342E);
  static const divider = Color(0xFFF0E8E0);
  static const hint    = Color(0xFF8D6E63);
}

abstract class _D {
  static const bg      = Color(0xFF1A0F0A);
  static const surface = Color(0xFF2C1A10);
  static const card    = Color(0xFF3A2318);
  static const text    = Color(0xFFF5EDE4);
  static const sub     = Color(0xFFB08B72);
  static const accent  = Color(0xFFD4A373);
  static const divider = Color(0xFF4A2E1C);
  static const hint    = Color(0xFFB08B72);
}

// ─────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────

class Category {
  final String name;
  const Category(this.name);
  static const all     = Category('All');
  static const coffee  = Category('Coffee');
  static const milktea = Category('MilkTea');
  static const snacks  = Category('Snacks');
  static const list    = [all, coffee, milktea, snacks];
}

class Products {
  final String            id;
  final String            names;
  final Category          category;
  final int               price;
  final String            imageUrl;
  final Map<String, int>? sizePrice;

  const Products({
    required this.id,
    required this.names,
    required this.category,
    required this.price,
    required this.imageUrl,
    this.sizePrice,
  });

  bool get hasSizes =>
      sizePrice != null &&
          category.name.toLowerCase().replaceAll(' ', '') == 'milktea';

  factory Products.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawCat =
    (d['section'] as String? ?? d['category'] as String? ?? '')
        .trim()
        .toLowerCase();
    final catName = rawCat.replaceAll(' ', '');
    final cat = Category.list.firstWhere(
          (c) => c.name.toLowerCase().replaceAll(' ', '') == catName,
      orElse: () => Category.all,
    );
    final isMilkTea = catName == 'milktea';
    Map<String, int>? sizePrice;
    if (isMilkTea) {
      if (d['sizePrice'] is Map) {
        sizePrice = Map<String, int>.from(
          (d['sizePrice'] as Map)
              .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        );
      } else {
        final base =
            ((d['sellPrice'] ?? d['price']) as num?)?.toInt() ?? 0;
        sizePrice = {
          'S': (base * 0.75).round(),
          'M': base,
          'L': (base * 1.25).round(),
        };
      }
    }
    final basePrice =
        sizePrice?['M'] ??
            ((d['sellPrice'] ?? d['price']) as num?)?.toInt() ??
            0;
    return Products(
      id:        doc.id,
      names:     d['name']     as String? ?? d['names']      as String? ?? '',
      category:  cat,
      price:     basePrice,
      imageUrl:  d['imageUrl'] as String? ?? d['imageAsset'] as String? ?? '',
      sizePrice: sizePrice,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ORDER ITEM
// ─────────────────────────────────────────────────────────────

class OrderItem {
  final Products product;
  final String?  size;
  int            qty;

  OrderItem({required this.product, this.size, this.qty = 1});

  int get unitPrice =>
      (size != null && product.sizePrice != null)
          ? product.sizePrice![size] ?? product.price
          : product.price;

  int get subtotal => unitPrice * qty;

  String get label =>
      size != null ? '${product.names} ($size)' : product.names;
}

// ─────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────

class Categories extends StatefulWidget {
  const Categories({super.key});
  @override
  State<Categories> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<Categories> {
  Category               selectedCategory = Category.all;
  String                 _gcashNumber     = '';
  String                 _gcashQrUrl      = '';
  final List<OrderItem>  _cart            = [];
  final FirestoreService _fs              = FirestoreService();

  List<Products> _firestoreProducts = [];
  bool           _loadingProducts   = true;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _listenToGcash();
    _listenToProducts();
  }

  // Streams Firestore in real-time — any QR or GCash number change
  // saved from profile.dart instantly flows through here.
  void _listenToGcash() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      setState(() {
        _gcashNumber = doc.data()?['gcashNumber'] ?? '';
        _gcashQrUrl = doc.data()?['gcashQrUrl'] ?? '';
      });
    });
  }

  void _listenToProducts() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('products')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final docs = snapshot.docs
          .where((doc) =>
      (doc.data()['source'] ?? '').toString() != 'inventory')
          .toList();
      setState(() {
        _firestoreProducts =
            docs.map((doc) => Products.fromFirestore(doc)).toList();
        _loadingProducts = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loadingProducts = false);
    });
  }

  void _addToCart(Products p, {String? size}) {
    SoundService.setEnabled(AppSettings.of(context).soundEnabled);
    SoundService.play('cart_add');

    setState(() {
      final idx =
      _cart.indexWhere((o) => o.product.id == p.id && o.size == size);
      if (idx >= 0) {
        _cart[idx].qty++;
      } else {
        _cart.add(OrderItem(product: p, size: size));
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Added ${p.names}${size != null ? ' ($size)' : ''} to cart',
        style: const TextStyle(
            color: Colors.white,
          ),
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF4E342E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CartSheet(
        cart:         _cart,
        uid:          _uid,
        gcashNumber:  _gcashNumber,
        gcashQrUrl:   _gcashQrUrl,
        onClear:      () => setState(() => _cart.clear()),
        onQtyChanged: () => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d        = AppSettings.of(context).darkMode;
    final filtered = selectedCategory.name == 'All'
        ? _firestoreProducts
        : _firestoreProducts
        .where((p) => p.category.name == selectedCategory.name)
        .toList();
    final cartCount = _cart.fold(0, (sum, i) => sum + i.qty);

    return Scaffold(
      backgroundColor: _c(d, _L.bg, _D.bg),
      body: SafeArea(
        child: Column(
          children: [
            _Topbar(
              isDark:    d,
              onMenuTap: () =>
                  SimpleHiddenDrawerController.of(context).toggle(),
              cartCount: cartCount,
              onCartTap: _openCart,
            ),
            _CategoriesTabs(
              isDark:             d,
              categories:         Category.list,
              onCategorySelected: (cat) =>
                  setState(() => selectedCategory = cat),
            ),
            Expanded(
              child: _loadingProducts
                  ? Center(
                child: CircularProgressIndicator(
                    color: _c(d, const Color(0xFF4E342E), _D.accent)),
              )
                  : filtered.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🛍', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text('No products found',
                        style: TextStyle(
                            color: _c(d, _L.hint, _D.hint),
                            fontSize: 15)),
                  ],
                ),
              )
                  : GridView.builder(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
                itemCount: filtered.length,
                gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:   2,
                  mainAxisSpacing:  16,
                  crossAxisSpacing: 16,
                  mainAxisExtent:   220,
                ),
                itemBuilder: (context, index) => _ProductCard(
                  isDark:      d,
                  product:     filtered[index],
                  onAddToCart: _addToCart,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TOPBAR
// ─────────────────────────────────────────────────────────────

class _Topbar extends StatelessWidget {
  final bool isDark;
  final VoidCallback onMenuTap;
  final VoidCallback onCartTap;
  final int          cartCount;

  const _Topbar({
    required this.isDark,
    required this.onMenuTap,
    required this.onCartTap,
    required this.cartCount,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: SizedBox(
        height: 50,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: onMenuTap,
                icon: Icon(Icons.menu, color: _c(d, _L.accent, _D.accent)),
              ),
            ),
            Text('Products',
                style: TextStyle(
                  fontFamily:  'playwrite',
                  fontWeight:  FontWeight.bold,
                  fontSize:    20,
                  color:    _c(isDark, const Color(0xFF2C1A0E), _D.accent),
                )),
            Align(
              alignment: Alignment.centerRight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: onCartTap,
                    icon: Icon(Icons.shopping_bag_outlined,
                        color: _c(d, _L.accent, _D.accent)),
                  ),
                  if (cartCount > 0)
                    Positioned(
                      top: 4, right: 4,
                      child: Container(
                        width: 18, height: 18,
                        decoration: const BoxDecoration(
                            color: Color(0xFF6BCF7F),
                            shape: BoxShape.circle),
                        child: Center(
                          child: Text('$cartCount',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CATEGORY TABS
// ─────────────────────────────────────────────────────────────

class _CategoriesTabs extends StatefulWidget {
  final bool               isDark;
  final List<Category>     categories;
  final ValueChanged<Category> onCategorySelected;

  const _CategoriesTabs({
    required this.isDark,
    required this.categories,
    required this.onCategorySelected,
  });

  @override
  State<_CategoriesTabs> createState() => _CategoriesTabsState();
}

class _CategoriesTabsState extends State<_CategoriesTabs> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final d = widget.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: SizedBox(
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(widget.categories.length, (i) {
            final isActive = _selected == i;
            final cat      = widget.categories[i];
            return GestureDetector(
              onTap: () {
                setState(() => _selected = i);
                widget.onCategorySelected(cat);
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(cat.name,
                      style: TextStyle(
                        fontSize:   15,
                        fontWeight: FontWeight.bold,
                        color: isActive
                            ? _c(d, _L.text, _D.text)
                            : _c(d, _L.hint, _D.hint),
                      )),
                  const SizedBox(height: 5),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 2,
                    width:  isActive ? 24 : 0,
                    color:  _c(d, const Color(0xFFC8A27A), _D.accent),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PRODUCT IMAGE HELPER
// ─────────────────────────────────────────────────────────────

class _ProductImage extends StatelessWidget {
  final String url;
  final double height;
  final String fallback;

  const _ProductImage({
    required this.url,
    required this.height,
    required this.fallback,
  });

  bool get _isNetwork =>
      url.startsWith('http://') || url.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (_isNetwork) {
      return Image.network(
        url, height: height, fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : SizedBox(
          height: height,
          child: const Center(
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white54),
          ),
        ),
        errorBuilder: (_, __, ___) =>
            Text(fallback, style: TextStyle(fontSize: height * 0.65)),
      );
    }
    return Image.asset(url, height: height, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            Text(fallback, style: TextStyle(fontSize: height * 0.65)));
  }
}

// ─────────────────────────────────────────────────────────────
// PRODUCT CARD
// ─────────────────────────────────────────────────────────────

class _ProductCard extends StatefulWidget {
  final bool     isDark;
  final Products product;
  final void Function(Products, {String? size}) onAddToCart;

  const _ProductCard({
    required this.isDark,
    required this.product,
    required this.onAddToCart,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  String _selectedSize = 'M';

  Color _catColor() {
    switch (widget.product.category.name) {
      case 'Coffee':  return const Color(0xFF4E342E);
      case 'MilkTea': return const Color(0xFF6A3FA6);
      case 'Snacks':  return const Color(0xFFE65100);
      default:        return const Color(0xFF2E7D3A);
    }
  }

  String get _catIcon {
    switch (widget.product.category.name) {
      case 'Coffee':  return '☕';
      case 'MilkTea': return '🧋';
      case 'Snacks':  return '🍿';
      default:        return '🛍';
    }
  }

  int get _displayPrice {
    if (widget.product.hasSizes && widget.product.sizePrice != null) {
      return widget.product.sizePrice![_selectedSize] ?? widget.product.price;
    }
    return widget.product.price;
  }

  @override
  Widget build(BuildContext context) {
    final d         = widget.isDark;
    final p         = widget.product;
    final catColor  = _catColor();
    final priceCol  = d ? _D.accent : catColor;
    final addBtnCol = d ? _D.accent : catColor;
    final addIconCol = d ? const Color(0xFF1A0F0A) : Colors.white;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color:        _c(d, Colors.white, _D.card),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: catColor.withOpacity(0.15), blurRadius: 14, offset: const Offset(0, 5)),
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 110,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [catColor, catColor.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end:   Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Positioned(top: -12, right: -12,
                      child: Container(width: 45, height: 45,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.08)))),
                  Positioned(bottom: -8, left: -8,
                      child: Container(width: 32, height: 32,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.06)))),
                  Positioned(
                    top: 5, left: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_catIcon, style: const TextStyle(fontSize: 6)),
                        const SizedBox(width: 2),
                        Text(p.category.name,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                color: Colors.white, letterSpacing: 0.3)),
                      ]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: p.imageUrl.isNotEmpty
                        ? _ProductImage(url: p.imageUrl, height: double.infinity, fallback: _catIcon)
                        : Center(child: Text(_catIcon, style: const TextStyle(fontSize: 30))),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 10, 7, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.names,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                        color: _c(d, const Color(0xFF1A0E0A), _D.text), letterSpacing: 0.1)),
                const SizedBox(height: 4),
                if (p.hasSizes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: ['S', 'M', 'L'].map((s) {
                        final active = _selectedSize == s;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedSize = s),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(right: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color:  active ? catColor : catColor.withOpacity(0.09),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: active ? catColor : catColor.withOpacity(0.2), width: 1),
                            ),
                            child: Text(s,
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                                    color: active ? Colors.white : catColor)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('PRICE',
                              style: TextStyle(fontSize: 6, fontWeight: FontWeight.w600,
                                  color: _c(d, _L.hint, _D.hint), letterSpacing: 0.8)),
                          Text('₱$_displayPrice',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                                  color: priceCol, height: 1.1)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => widget.onAddToCart(p,
                          size: p.hasSizes ? _selectedSize : null),
                      child: Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color:        addBtnCol,
                          borderRadius: BorderRadius.circular(7),
                          boxShadow: [
                            BoxShadow(color: addBtnCol.withOpacity(0.4),
                                blurRadius: 6, offset: const Offset(0, 3)),
                          ],
                        ),
                        child: Icon(Icons.add, size: 13, color: addIconCol),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CART SHEET
// ─────────────────────────────────────────────────────────────

class _CartSheet extends StatefulWidget {
  final List<OrderItem> cart;
  final String          uid;
  final VoidCallback    onClear;
  final VoidCallback    onQtyChanged;
  final String          gcashNumber;
  final String          gcashQrUrl;

  const _CartSheet({
    required this.cart,
    required this.uid,
    required this.onClear,
    required this.onQtyChanged,
    required this.gcashNumber,
    required this.gcashQrUrl,
  });

  @override
  State<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<_CartSheet> {
  int get _total => widget.cart.fold(0, (sum, i) => sum + i.subtotal);

  void _removeItem(int index) {
    setState(() => widget.cart.removeAt(index));
    widget.onQtyChanged();
  }

  void _changeQty(int index, int delta) {
    setState(() {
      widget.cart[index].qty += delta;
      if (widget.cart[index].qty <= 0) widget.cart.removeAt(index);
    });
    widget.onQtyChanged();
  }

  void _checkout() {
    if (widget.cart.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentSheet(
        cart:        widget.cart,
        total:       _total,
        uid:         widget.uid,
        gcashNumber: widget.gcashNumber,
        gcashQrUrl:  widget.gcashQrUrl,
        onPaid: () {
          widget.onClear();
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d   = AppSettings.of(context).darkMode;
    final bg  = _c(d, _L.bg, _D.bg);
    final txt = _c(d, _L.text, _D.text);
    final sub = _c(d, _L.hint, _D.hint);
    final div = _c(d, _L.divider, _D.divider);
    final acc = _c(d, _L.accent, _D.accent);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 5,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: div, borderRadius: BorderRadius.circular(99)),
          ),
          Row(
            children: [
              Text('Your Order',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                      color: txt, fontFamily: 'playwrite')),
              const Spacer(),
              if (widget.cart.isNotEmpty)
                TextButton(
                  onPressed: () { setState(() => widget.cart.clear()); widget.onQtyChanged(); },
                  child: const Text('Clear all', style: TextStyle(color: Colors.red)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.cart.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(children: [
                const Text('🛍', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text('Your cart is empty', style: TextStyle(color: sub, fontSize: 15)),
              ]),
            )
          else ...[
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.cart.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = widget.cart[index];
                  return _CartItemRow(
                    isDark:   d,
                    item:     item,
                    onRemove: () => _removeItem(index),
                    onAdd:    () => _changeQty(index, 1),
                    onMinus:  () => _changeQty(index, -1),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Divider(color: div),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: txt)),
                const Spacer(),
                Text('₱$_total',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: acc)),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _checkout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: acc,
                  foregroundColor: d ? const Color(0xFF1A0F0A) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 0,
                ),
                child: const Text('Proceed to Checkout',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CART ITEM ROW
// ─────────────────────────────────────────────────────────────

class _CartItemRow extends StatelessWidget {
  final bool         isDark;
  final OrderItem    item;
  final VoidCallback onRemove;
  final VoidCallback onAdd;
  final VoidCallback onMinus;

  const _CartItemRow({
    required this.isDark,
    required this.item,
    required this.onRemove,
    required this.onAdd,
    required this.onMinus,
  });

  @override
  Widget build(BuildContext context) {
    final d   = isDark;
    final txt = _c(d, _L.text, _D.text);
    final sub = _c(d, _L.hint, _D.hint);
    final acc = _c(d, _L.accent, _D.accent);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        _c(d, Colors.white, _D.card),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              color: _c(d, const Color(0xFF4E342E).withOpacity(0.10), _D.card),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: item.product.imageUrl.isNotEmpty
                  ? _ProductImage(url: item.product.imageUrl, height: 36, fallback: '☕')
                  : const Text('☕', style: TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: txt)),
                Text('₱${item.unitPrice} each',
                    style: TextStyle(fontSize: 12, color: sub)),
              ],
            ),
          ),
          Row(
            children: [
              _qBtn(Icons.remove, onMinus, Colors.red.shade100, Colors.red),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('${item.qty}',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: txt)),
              ),
              _qBtn(Icons.add, onAdd,
                  const Color(0xFF6BCF7F).withOpacity(0.2), const Color(0xFF6BCF7F)),
            ],
          ),
          const SizedBox(width: 10),
          Text('₱${item.subtotal}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: acc)),
        ],
      ),
    );
  }

  Widget _qBtn(IconData icon, VoidCallback tap, Color bg, Color fg) => GestureDetector(
    onTap: tap,
    child: Container(
      width: 28, height: 28,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, size: 16, color: fg),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// PAYMENT SHEET
// ─────────────────────────────────────────────────────────────

class _PaymentSheet extends StatefulWidget {
  final List<OrderItem> cart;
  final int             total;
  final String          uid;
  final String          gcashNumber;
  final String          gcashQrUrl;
  final VoidCallback    onPaid;

  const _PaymentSheet({
    required this.cart,
    required this.total,
    required this.uid,
    required this.gcashNumber,
    required this.gcashQrUrl,
    required this.onPaid,
  });

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  String  _method = 'cash';
  bool    _saving = false;
  final _cashCtrl = TextEditingController();

  @override
  void dispose() { _cashCtrl.dispose(); super.dispose(); }

  String _genOrderId() {
    final rand = Random().nextInt(99999).toString().padLeft(5, '0');
    final ts   = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    return 'ORD-$ts$rand';
  }

  Future<void> _pay() async {
    setState(() => _saving = true);
    final orderId = _genOrderId();
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('sales')
          .doc(orderId)
          .set({
        'orderId':       orderId,
        'items': widget.cart.map((i) => {
          'name':      i.label,
          'productId': i.product.id,
          'price':     i.unitPrice,
          'qty':       i.qty,
          'subtotal':  i.subtotal,
        }).toList(),
        'total':         widget.total,
        'paymentMethod': _method,
        'createdAt':     FieldValue.serverTimestamp(),
        'status':        'completed',
      });

      SoundService.setEnabled(AppSettings.of(context).soundEnabled);
      SoundService.play('cashout');

      setState(() => _saving = false);
      if (mounted) {
        Navigator.pop(context);
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          isDismissible:   false,
          enableDrag:      false,
          backgroundColor: Colors.transparent,
          builder: (_) => _ReceiptSheet(
            orderId: orderId,
            cart:    List.from(widget.cart),
            total:   widget.total,
            method:  _method,
            onDone:  widget.onPaid,
          ),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Payment failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d       = AppSettings.of(context).darkMode;
    final bg      = _c(d, _L.bg, _D.bg);
    final card    = _c(d, Colors.white, _D.card);
    final txt     = _c(d, _L.text, _D.text);
    final sub     = _c(d, _L.hint, _D.hint);
    final div     = _c(d, _L.divider, _D.divider);
    final acc     = _c(d, _L.accent, _D.accent);
    final cashAmt = int.tryParse(_cashCtrl.text) ?? 0;
    final change  = cashAmt - widget.total;
    final gcash   = widget.gcashNumber.isEmpty ? 'Not set' : widget.gcashNumber;


    final resolvedQrUrl = widget.gcashQrUrl.isNotEmpty
        ? ApiService.resolveImageUrl(widget.gcashQrUrl)
        : '';

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 5,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: div, borderRadius: BorderRadius.circular(99)),
            ),
            Text('Payment',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                    color: txt, fontFamily: 'playwrite')),
            const SizedBox(height: 16),

            // Total banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: d
                      ? [_D.card, _D.surface]
                      : [const Color(0xFF4E342E), const Color(0xFF8D6E63)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Total Amount',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('₱ ${widget.total}',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 28, fontWeight: FontWeight.w900)),
                  ]),
                  const Icon(Icons.receipt_long_outlined, color: Colors.white54, size: 36),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Method buttons
            Row(
              children: [
                Expanded(child: _MethodBtn(
                  isDark:   d, label: 'Cash', icon: Icons.payments_outlined,
                  selected: _method == 'cash',
                  color:    _c(d, const Color(0xFF4E342E), _D.accent),
                  onTap:    () => setState(() => _method = 'cash'),
                )),
                const SizedBox(width: 12),
                Expanded(child: _MethodBtn(
                  isDark:       d, label: 'GCash', icon: Icons.phone_android_outlined,
                  selected:     _method == 'gcash',
                  color:        const Color(0xFF0074D9),
                  disabled:     gcash == 'Not set',
                  disabledHint: 'Add your GCash number in Profile settings first.',
                  onTap: gcash == 'Not set'
                      ? () {} : () => setState(() => _method = 'gcash'),
                )),
              ],
            ),
            const SizedBox(height: 18),

            // ── Cash ──
            if (_method == 'cash') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: card, borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))
                  ],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Cash Tendered',
                      style: TextStyle(fontWeight: FontWeight.w700, color: txt)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _cashCtrl, keyboardType: TextInputType.number,
                    onChanged:  (_) => setState(() {}), style: TextStyle(color: txt),
                    decoration: InputDecoration(
                      prefixText: '₱ ', hintText: 'Enter amount',
                      hintStyle: TextStyle(color: sub), filled: true, fillColor: bg,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  if (cashAmt >= widget.total) ...[
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Change', style: TextStyle(fontWeight: FontWeight.w600, color: txt)),
                      Text('₱ $change',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                              color: Color(0xFF6BCF7F))),
                    ]),
                  ],
                ]),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: (_saving || cashAmt < widget.total) ? null : _pay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: acc,
                    foregroundColor: d ? const Color(0xFF1A0F0A) : Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : const Text('Confirm Cash Payment',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],

            // ── GCash ──
            if (_method == 'gcash') ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: card, borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))
                  ],
                ),
                child: Column(children: [
                  Text('Scan to Pay via GCash',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: txt)),
                  const SizedBox(height: 4),
                  Text('Show this QR to the customer',
                      style: TextStyle(fontSize: 12, color: sub)),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: d ? Colors.white.withOpacity(0.05) : const Color(0xFFF0F7FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF0074D9).withOpacity(0.2)),
                    ),
                    // ── THE FIX: use resolvedQrUrl instead of raw widget.gcashQrUrl ──
                    child: resolvedQrUrl.isNotEmpty
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        resolvedQrUrl,
                        width: 180, height: 180, fit: BoxFit.contain,
                        loadingBuilder: (_, child, prog) => prog == null ? child
                            : const SizedBox(width: 180, height: 180,
                            child: Center(child: CircularProgressIndicator(
                                color: Color(0xFF0074D9), strokeWidth: 2))),
                        errorBuilder: (_, __, ___) => BarcodeWidget(
                          barcode: Barcode.qrCode(),
                          data:    'GCASH|$gcash|${widget.total}',
                          width: 180, height: 180,
                          color: const Color(0xFF0074D9), drawText: false,
                        ),
                      ),
                    )
                        : BarcodeWidget(
                      barcode: Barcode.qrCode(),
                      data:    'GCASH|$gcash|${widget.total}',
                      width: 180, height: 180,
                      color: const Color(0xFF0074D9), drawText: false,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0074D9).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Amount', style: TextStyle(fontSize: 11, color: sub)),
                        Text('₱ ${widget.total}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                                color: Color(0xFF0074D9))),
                      ]),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('GCash Number', style: TextStyle(fontSize: 11, color: sub)),
                        Text(gcash,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                                color: Color(0xFF0074D9))),
                      ]),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _pay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0074D9), foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : const Text('Confirm GCash Payment',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// METHOD BUTTON
// ─────────────────────────────────────────────────────────────

class _MethodBtn extends StatelessWidget {
  final bool         isDark;
  final String       label;
  final IconData     icon;
  final bool         selected;
  final Color        color;
  final VoidCallback onTap;
  final bool         disabled;
  final String?      disabledHint;

  const _MethodBtn({
    required this.isDark, required this.label, required this.icon,
    required this.selected, required this.color, required this.onTap,
    this.disabled = false, this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    final d       = isDark;
    final disCol  = _c(d, Colors.grey.shade400, _D.sub);
    final cardBg  = _c(d, Colors.white, _D.card);
    final divCol  = _c(d, Colors.grey.shade200, _D.divider);
    final iconCol = disabled ? disCol
        : selected ? (d ? const Color(0xFF1A0F0A) : Colors.white) : color;

    return Tooltip(
      message: disabled ? (disabledHint ?? '') : '',
      child: GestureDetector(
        onTap: disabled ? () {
          if (disabledHint != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Row(children: [
                const Icon(Icons.info_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(disabledHint!)),
              ]),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 3),
            ));
          }
        } : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: disabled ? disCol.withOpacity(0.1) : selected ? color : cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: disabled ? divCol : selected ? color : divCol, width: 1.5),
            boxShadow: (!disabled && selected)
                ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]
                : [],
          ),
          child: Column(children: [
            Icon(disabled ? Icons.lock_outline : icon, color: iconCol, size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: iconCol)),
            if (disabled) ...[
              const SizedBox(height: 2),
              Text('Setup required',
                  style: TextStyle(fontSize: 8, color: Colors.orange.shade400,
                      fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BLUETOOTH PRINTER SERVICE
// ─────────────────────────────────────────────────────────────

class _PrinterService {
  static final BlueThermalPrinter _bt = BlueThermalPrinter.instance;

  static Future<void> printReceipt({
    required BluetoothDevice device, required String orderId,
    required List<OrderItem> cart,   required int    total,
    required String method,          required String dateStr,
  }) async {
    await _bt.connect(device);
    _bt.printCustom('BrewPos', 2, 1);
    _bt.printCustom('Order Receipt', 1, 1);
    _bt.printNewLine();
    _bt.printCustom('--------------------------------', 1, 1);
    _bt.printLeftRight('Order ID:', orderId, 1);
    _bt.printLeftRight('Date:', dateStr, 1);
    _bt.printLeftRight('Payment:', method == 'gcash' ? 'GCash' : 'Cash', 1);
    _bt.printCustom('--------------------------------', 1, 1);
    for (final item in cart) {
      _bt.printLeftRight('${item.label} x${item.qty}', 'P${item.subtotal}', 1);
    }
    _bt.printCustom('--------------------------------', 1, 1);
    _bt.printLeftRight('TOTAL', 'P$total', 2);
    _bt.printCustom('--------------------------------', 1, 1);
    _bt.printNewLine();
    _bt.printCustom('Thank you for your purchase!', 1, 1);
    _bt.printCustom('Powered by BrewPos', 1, 1);
    _bt.printNewLine();
    _bt.printNewLine();
    _bt.printNewLine();
    await _bt.disconnect();
  }
}

// ─────────────────────────────────────────────────────────────
// PRINTER SELECT SHEET
// ─────────────────────────────────────────────────────────────

class _PrinterSelectSheet extends StatefulWidget {
  final String orderId; final List<OrderItem> cart;
  final int total; final String method; final String dateStr;

  const _PrinterSelectSheet({
    required this.orderId, required this.cart,
    required this.total,   required this.method, required this.dateStr,
  });

  @override
  State<_PrinterSelectSheet> createState() => _PrinterSelectSheetState();
}

class _PrinterSelectSheetState extends State<_PrinterSelectSheet> {
  final BlueThermalPrinter _bt = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devices  = [];
  bool                  _scanning = true;
  bool                  _printing = false;
  String?               _error;

  @override
  void initState() { super.initState(); _scan(); }

  Future<void> _scan() async {
    setState(() { _scanning = true; _error = null; });
    try {
      final paired = await _bt.getBondedDevices();
      if (mounted) setState(() { _devices = paired; _scanning = false; });
    } catch (e) {
      if (mounted) setState(() { _scanning = false; _error = e.toString(); });
    }
  }

  Future<void> _print(BluetoothDevice device) async {
    setState(() => _printing = true);
    try {
      await _PrinterService.printReceipt(
        device: device, orderId: widget.orderId, cart: widget.cart,
        total: widget.total, method: widget.method, dateStr: widget.dateStr,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Receipt printed successfully!'),
          backgroundColor: Color(0xFF6BCF7F), behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) setState(() { _printing = false; _error = 'Print failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d    = AppSettings.of(context).darkMode;
    final bg   = _c(d, _L.bg, _D.bg);
    final card = _c(d, Colors.white, _D.card);
    final txt  = _c(d, _L.text, _D.text);
    final sub  = _c(d, _L.hint, _D.hint);
    final div  = _c(d, _L.divider, _D.divider);
    final acc  = _c(d, _L.accent, _D.accent);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
          color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 5,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: div, borderRadius: BorderRadius.circular(99))),
          Row(children: [
            Icon(Icons.print_outlined, color: acc),
            const SizedBox(width: 10),
            Text('Select Printer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                    color: txt, fontFamily: 'playwrite')),
            const Spacer(),
            if (!_scanning)
              IconButton(onPressed: _scan, icon: Icon(Icons.refresh, color: acc), tooltip: 'Refresh'),
          ]),
          const SizedBox(height: 12),
          if (_scanning)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Column(children: [
                CircularProgressIndicator(color: acc), const SizedBox(height: 12),
                Text('Scanning for paired printers...', style: TextStyle(color: sub)),
              ]),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 36),
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _scan,
                    style: ElevatedButton.styleFrom(backgroundColor: acc),
                    child: const Text('Retry', style: TextStyle(color: Colors.white))),
              ]),
            )
          else if (_devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(children: [
                  const Icon(Icons.bluetooth_disabled, color: Colors.grey, size: 36),
                  const SizedBox(height: 8),
                  const Text('No paired Bluetooth printers found.',
                      style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text('Pair your printer in phone Settings first.',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                ]),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true, itemCount: _devices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final dev = _devices[i];
                    return GestureDetector(
                      onTap: _printing ? null : () => _print(dev),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: card, borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _c(d, Colors.grey.shade200, _D.divider)),
                          boxShadow: const [
                            BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))
                          ],
                        ),
                        child: Row(children: [
                          Container(padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: acc.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Icon(Icons.print_outlined, color: acc, size: 20)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(dev.name ?? 'Unknown Printer',
                                style: TextStyle(fontWeight: FontWeight.w700, color: txt)),
                            Text(dev.address ?? '', style: TextStyle(fontSize: 11, color: sub)),
                          ])),
                          _printing
                              ? SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: acc))
                              : Icon(Icons.chevron_right, color: acc),
                        ]),
                      ),
                    );
                  },
                ),
              ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// RECEIPT SHEET
// ─────────────────────────────────────────────────────────────

class _ReceiptSheet extends StatefulWidget {
  final String orderId; final List<OrderItem> cart;
  final int total; final String method; final VoidCallback onDone;

  const _ReceiptSheet({
    required this.orderId, required this.cart,
    required this.total,   required this.method, required this.onDone,
  });

  @override
  State<_ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<_ReceiptSheet> {
  late final String dateStr;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  void _openPrintSheet() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _PrinterSelectSheet(
        orderId: widget.orderId, cart: widget.cart,
        total: widget.total, method: widget.method, dateStr: dateStr,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d    = AppSettings.of(context).darkMode;
    final bg   = _c(d, _L.bg, _D.bg);
    final card = _c(d, Colors.white, _D.card);
    final txt  = _c(d, _L.text, _D.text);
    final sub  = _c(d, _L.hint, _D.hint);
    final div  = _c(d, _L.divider, _D.divider);
    final acc  = _c(d, _L.accent, _D.accent);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: BoxDecoration(
          color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(children: [
          Container(width: 40, height: 5,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: div, borderRadius: BorderRadius.circular(99))),
          Container(width: 70, height: 70,
              decoration: const BoxDecoration(color: Color(0xFF6BCF7F), shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Colors.white, size: 36)),
          const SizedBox(height: 12),
          Text('Payment Successful!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                  color: txt, fontFamily: 'playwrite')),
          const SizedBox(height: 4),
          Text(dateStr, style: TextStyle(fontSize: 12, color: sub)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: card, borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 4))
              ],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Column(children: [
                Text('☕ BrewPos',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                        color: acc, fontFamily: 'playwrite')),
                const SizedBox(height: 2),
                Text('Order Receipt', style: TextStyle(fontSize: 12, color: sub)),
              ])),
              const SizedBox(height: 12),
              Divider(color: div),
              const SizedBox(height: 8),
              _rRow('Order ID', widget.orderId, txt: txt, sub: sub, bold: true),
              const SizedBox(height: 4),
              _rRow('Payment', widget.method == 'gcash' ? 'GCash 💙' : 'Cash 💵', txt: txt, sub: sub),
              const SizedBox(height: 4),
              _rRow('Date', dateStr, txt: txt, sub: sub),
              const SizedBox(height: 10),
              Divider(color: div),
              const SizedBox(height: 8),
              ...widget.cart.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(child: Text('${item.label} x${item.qty}',
                      style: TextStyle(fontSize: 13, color: txt))),
                  Text('₱${item.subtotal}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: acc)),
                ]),
              )),
              Divider(color: div),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Text('TOTAL',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: txt))),
                Text('₱${widget.total}',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: acc)),
              ]),
              const SizedBox(height: 16),
              Center(
                child: BarcodeWidget(
                  barcode: Barcode.code128(), data: widget.orderId,
                  width: double.infinity, height: 60, drawText: true,
                  color: txt, style: TextStyle(fontSize: 10, color: txt),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: Text('Thank you for your purchase! ☕',
                  style: TextStyle(fontSize: 12, color: sub, fontStyle: FontStyle.italic))),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              onPressed: _openPrintSheet,
              icon:  const Icon(Icons.print_outlined),
              label: const Text('Print Receipt',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0074D9), foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: () { Navigator.pop(context); widget.onDone(); },
              style: ElevatedButton.styleFrom(
                backgroundColor: acc,
                foregroundColor: d ? const Color(0xFF1A0F0A) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _rRow(String label, String value,
      {bool bold = false, required Color txt, required Color sub}) =>
      Row(children: [
        Text(label, style: TextStyle(fontSize: 12, color: sub)),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 12,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: txt)),
      ]);
}
import 'package:flutter/material.dart';
import 'package:hidden_drawer_menu/controllers/simple_hidden_drawer_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../app_settings.dart';
import '../firestore_service.dart';
import '../api_service.dart';
import '../add_product.dart';
import '../add_inventory.dart';

// ─────────────────────────────────────────────────────────────
// DARK / LIGHT COLOR TOKENS
// ─────────────────────────────────────────────────────────────

Color _c(bool d, Color light, Color dark) => d ? dark : light;

abstract class _L {
  static const bg      = Color(0xFFFFFFFF);
  static const topbar  = Color(0xFFFFFFFF);
  static const text    = Color(0xFF2C1A0E);
  static const sub     = Color(0xFF8D6E63);
  static const accent  = Color(0xFF4E342E);
  static const latte   = Color(0xFFD4A373);
  static const caramel = Color(0xFF8D6E63);
  static const cream   = Color(0xFFFDF6F1);
  static const steam   = Color(0xFFF5EDE4);
  static const card    = Color(0xFFFDF6F1);
  static const espresso = Color(0xFF2C1A0E);
  static const roast   = Color(0xFF4E342E);
  static const matcha  = Color(0xFF6A994E);
  static const rust    = Color(0xFFC0392B);
  static const amber   = Color(0xFFE07B39);
}

abstract class _D {
  static const bg      = Color(0xFF1A0F0A);
  static const topbar  = Color(0xFF2C1A10);
  static const text    = Color(0xFFF5EDE4);
  static const sub     = Color(0xFFB08B72);
  static const accent  = Color(0xFFD4A373);
  static const latte   = Color(0xFFD4A373);
  static const caramel = Color(0xFFB08B72);
  static const cream   = Color(0xFF3A2318);
  static const steam   = Color(0xFF2C1A10);
  static const card    = Color(0xFF3A2318);
  static const divider = Color(0xFF4A2E1C);
}

// ─────────────────────────────────────────────────────────────
// CATEGORY  /  SECTIONS
// ─────────────────────────────────────────────────────────────

class Category {
  final String name;
  const Category(this.name);
  static const products  = Category('Products');
  static const inventory = Category('Inventory');
  static const list = [products, inventory];
  @override bool operator ==(Object o) => o is Category && o.name == name;
  @override int  get hashCode => name.hashCode;
}

class ProductSection {
  final String name;
  const ProductSection(this.name);
  static const all     = ProductSection('All');
  static const coffee  = ProductSection('Coffee');
  static const milktea = ProductSection('Milktea');
  static const snacks  = ProductSection('Snacks');
  static const list = [all, coffee, milktea, snacks];
}

class InventorySection {
  final String name;
  const InventorySection(this.name);
  static const all        = InventorySection('All');
  static const syrups     = InventorySection('Syrups');
  static const powder     = InventorySection('Powder');
  static const milkCream  = InventorySection('Milk & Cream');
  static const coffeeBase = InventorySection('Coffee / Tea Base');
  static const toppings   = InventorySection('Toppings');
  static const list = [all, syrups, powder, milkCream, coffeeBase, toppings];
}

// ─────────────────────────────────────────────────────────────
// PRODUCTS PAGE
// ─────────────────────────────────────────────────────────────

class Products extends StatefulWidget {
  const Products({super.key});
  @override State<Products> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<Products> {
  Category         selectedCategory  = Category.products;
  ProductSection   _productSection   = ProductSection.all;
  InventorySection _inventorySection = InventorySection.all;

  String _query      = '';
  bool   _searchOpen = false;

  final FirestoreService _fs  = FirestoreService();
  final ApiService       _api = ApiService();
  final TextEditingController _searchCtrl  = TextEditingController();
  final FocusNode             _searchFocus = FocusNode();

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _openAddForm(bool d) async {
    final isProd = selectedCategory == Category.products;
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _c(d, _L.cream, _D.card),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) =>
      isProd ? const AddProductSheet() : const AddInventorySheet(),
    );
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) { if (mounted) _searchFocus.requestFocus(); });
    } else {
      _searchCtrl.clear();
      setState(() => _query = '');
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _query = '');
    _searchFocus.requestFocus();
  }

  void _closeSearchIfOpen() { if (_searchOpen) _toggleSearch(); }

  // ── Products stream ───────────────────────────────────────
  Widget _buildProductsStream(bool d) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _fs.watchProducts(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}',
            style: TextStyle(color: _c(d, _L.caramel, _D.caramel))));
        if (snap.connectionState == ConnectionState.waiting)
          return Center(child: CircularProgressIndicator(
              color: _c(d, _L.roast, _D.accent)));

        final docs = snap.data?.docs ?? [];
        final filtered = docs.where((doc) {
          final data   = doc.data();
          final source = (data['source'] ?? 'product').toString();
          if (source == 'inventory') return false;
          final name    = (data['name']    ?? '').toString().toLowerCase();
          final section = (data['section'] ?? '').toString();
          final matchSection = _productSection == ProductSection.all ||
              section == _productSection.name;
          final matchQuery = _query.trim().isEmpty ||
              name.contains(_query.toLowerCase());
          return matchSection && matchQuery;
        }).toList();

        if (filtered.isEmpty) return _CafeEmptyState(isDark: d,
            icon: '☕', message: 'No products found',
            sub: 'Try a different filter or add a new item.');

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final data = filtered[i].data();
            final id   = filtered[i].id;
            return ProductCard(
              isDark:    d,
              productId: id,
              name:      data['name']                          ?? 'Unknown',
              section:   data['section']                       ?? 'General',
              price:     (data['sellPrice'] ?? data['price'] ?? 0).toDouble(),
              imageUrl:  data['imageUrl'],
              onBeforeMenuAction: _closeSearchIfOpen,
              onDeleted:      () => _fs.deleteProduct(id),
              onPriceUpdated: (p) => _fs.updateProduct(id, sellPrice: p),
            );
          },
        );
      },
    );
  }

  // ── Inventory stream ──────────────────────────────────────
  Widget _buildInventoryStream(bool d, int alertThreshold) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _fs.watchInventoryMerged(_uid),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}',
            style: TextStyle(color: _c(d, _L.caramel, _D.caramel))));
        if (snap.connectionState == ConnectionState.waiting)
          return Center(child: CircularProgressIndicator(
              color: _c(d, _L.roast, _D.accent)));

        final all = snap.data ?? [];
        final filtered = all.where((data) {
          final name    = (data['name']    ?? '').toString().toLowerCase();
          final section = (data['section'] ?? '').toString();
          final matchSection = _inventorySection == InventorySection.all ||
              section == _inventorySection.name;
          final matchQuery = _query.trim().isEmpty ||
              name.contains(_query.toLowerCase());
          return matchSection && matchQuery;
        }).toList();

        if (filtered.isEmpty) return _CafeEmptyState(isDark: d,
            icon: '🫙', message: 'No inventory found',
            sub: 'Add ingredients or supplies to get started.');

        final summaryItems = filtered.map((data) => _InvSummary(
          stockQty:     (data['stockQty']     ?? 0) as int,
          reorderLevel: (data['reorderLevel'] ?? 0) as int,
        )).toList();

        return Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: InventorySummaryFromFirestore(items: summaryItems, isDark: d),
          ),
          Expanded(child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final data = filtered[i];
              final id   = data['id'] as String;
              return InventoryCard(
                isDark:        d,
                alertThreshold: alertThreshold,
                name:         data['name']          ?? 'Unknown',
                section:      data['section']       ?? '',
                price:        (data['sellPrice']    ?? 0).toDouble(),
                imageUrl:     data['imageUrl'],
                barcode:      data['barcode'],
                quantity:     (data['stockQty']     ?? 0) as int,
                unit:         data['unit']           ?? 'pcs',
                reorderLevel: (data['reorderLevel']  ?? 0) as int,
                onBeforeMenuAction: _closeSearchIfOpen,
                onAddStock:    () async => _api.adjustStock(id,  1),
                onReduceStock: () async => _api.adjustStock(id, -1),
                onDeleted:     () => _fs.deleteInventoryItem(id),
              );
            },
          )),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s    = AppSettings.of(context);
    final d    = s.darkMode;
    final isProd = selectedCategory == Category.products;

    return Scaffold(
      backgroundColor: _c(d, _L.bg, _D.bg),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _CafeFAB(isDark: d, onPressed: () => _openAddForm(d)),
      body: SafeArea(child: Column(children: [
        _Topbar(
          isDark:         d,
          title:          selectedCategory.name,
          onMenuTap:      () => SimpleHiddenDrawerController.of(context).toggle(),
          isOpen:         _searchOpen,
          controller:     _searchCtrl,
          focusNode:      _searchFocus,
          onToggleSearch: _toggleSearch,
          onChanged:      (v) => setState(() => _query = v),
          hasQuery:       _query.trim().isNotEmpty,
          onClearQuery:   _clearSearch,
        ),
        CategoryTabs(
          isDark:     d,
          categories: Category.list,
          selected:   selectedCategory,
          onCategorySelected: (cat) {
            setState(() {
              selectedCategory  = cat;
              _productSection   = ProductSection.all;
              _inventorySection = InventorySection.all;
              _query            = '';
              _searchCtrl.clear();
            });
          },
        ),
        SectionChips(
          isDark:   d,
          sections: isProd
              ? ProductSection.list.map((s) => s.name).toList()
              : InventorySection.list.map((s) => s.name).toList(),
          selected: isProd ? _productSection.name : _inventorySection.name,
          onSectionSelected: (name) {
            setState(() {
              if (isProd) {
                _productSection =
                    ProductSection.list.firstWhere((s) => s.name == name);
              } else {
                _inventorySection =
                    InventorySection.list.firstWhere((s) => s.name == name);
              }
            });
          },
        ),
        const SizedBox(height: 6),
        Expanded(
          child: isProd
              ? _buildProductsStream(d)
              : _buildInventoryStream(d, s.lowStockThreshold),
        ),
      ])),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FAB
// ─────────────────────────────────────────────────────────────

class _CafeFAB extends StatelessWidget {
  final bool isDark; final VoidCallback onPressed;
  const _CafeFAB({required this.isDark, required this.onPressed});

  @override Widget build(BuildContext context) {
    final d = isDark;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [_c(d, _L.espresso, _D.caramel), _c(d, _L.accent, _D.latte)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [BoxShadow(
                color: _L.espresso.withOpacity(0.45),
                blurRadius: 16, offset: const Offset(0, 6))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
           Icon(Icons.add, color: _c(d, _L.bg, _D.bg), size: 20),
          const SizedBox(width: 8),
           Text('Add Item', style: TextStyle(
              color: _c(d, _L.bg, _D.topbar), fontWeight: FontWeight.w700,
              fontSize: 14, letterSpacing: 0.3)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TOPBAR
// ─────────────────────────────────────────────────────────────

class _Topbar extends StatelessWidget {
  final bool isDark, isOpen, hasQuery;
  final String title;
  final VoidCallback onMenuTap, onToggleSearch, onClearQuery;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _Topbar({
    required this.isDark, required this.title, required this.onMenuTap,
    required this.isOpen, required this.controller, required this.focusNode,
    required this.onToggleSearch, required this.onChanged,
    required this.hasQuery, required this.onClearQuery,
  });

  @override Widget build(BuildContext context) {
    final d = isDark;
    return Container(
      color: _c(d, _L.topbar, _D.bg),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: SizedBox(height: 56, child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(

              borderRadius: BorderRadius.circular(12)),
          child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: onMenuTap,
              icon: Icon(Icons.menu, size: 20,
                  color: _c(d, _L.espresso, _D.accent))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                fontFamily: 'playwrite',
                color: _c(d, _L.espresso, _D.accent)))),
        _SearchCapsule(
          isDark: d, isOpen: isOpen, controller: controller,
          focusNode: focusNode, onToggleSearch: onToggleSearch,
          onChanged: onChanged, hasQuery: hasQuery, onClearQuery: onClearQuery,
        ),
      ])),
    );
  }
}

class _SearchCapsule extends StatelessWidget {
  final bool isDark, isOpen, hasQuery;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onToggleSearch, onClearQuery;
  final ValueChanged<String> onChanged;

  const _SearchCapsule({
    required this.isDark, required this.isOpen, required this.controller,
    required this.focusNode, required this.onToggleSearch, required this.onChanged,
    required this.hasQuery, required this.onClearQuery,
  });

  @override Widget build(BuildContext context) {
    final d = isDark;
    return AnimatedSize(
      duration: const Duration(milliseconds: 280), curve: Curves.easeOut,
      alignment: Alignment.centerRight,
      child: Container(
        width: isOpen ? 160 : 40, height: 40,
        decoration: BoxDecoration(
          color: isOpen ? _c(d, _L.cream, _D.card) : _c(d, _L.steam, _D.topbar),
          borderRadius: BorderRadius.circular(20),
          border: isOpen ? Border.all(
              color: _c(d, _L.caramel, _D.caramel).withOpacity(0.4), width: 1.5)
              : null,
          boxShadow: isOpen ? [BoxShadow(
              color: _L.espresso.withOpacity(0.12),
              blurRadius: 8, offset: const Offset(0, 4))] : const [],
        ),
        child: Row(children: [
          SizedBox(width: 40, height: 40,
              child: Material(color: Colors.transparent,
                  child: IconButton(padding: EdgeInsets.zero, onPressed: onToggleSearch,
                      icon: Icon(Icons.search, size: 20,
                          color: _c(d, _L.roast, _D.accent))))),
          if (isOpen) Expanded(child: TextField(
              controller: controller, focusNode: focusNode,
              style: TextStyle(fontWeight: FontWeight.w600,
                  color: _c(d, _L.espresso, _D.text), fontSize: 13),
              decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(
                      color: _c(d, _L.caramel, _D.caramel).withOpacity(0.7),
                      fontSize: 13),
                  border: InputBorder.none, isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10)),
              onChanged: onChanged)),
          if (isOpen && hasQuery)
            Padding(padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(onTap: onClearQuery,
                    child: Container(width: 20, height: 20,
                        decoration: BoxDecoration(
                            color: _c(d, _L.caramel, _D.caramel).withOpacity(0.2),
                            shape: BoxShape.circle),
                        child: Icon(Icons.clear, size: 13,
                            color: _c(d, _L.roast, _D.accent))))),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CATEGORY TABS
// ─────────────────────────────────────────────────────────────

class CategoryTabs extends StatelessWidget {
  final bool isDark;
  final List<Category> categories;
  final Category       selected;
  final ValueChanged<Category> onCategorySelected;

  const CategoryTabs({super.key,
    required this.isDark, required this.categories,
    required this.selected, required this.onCategorySelected});

  @override Widget build(BuildContext context) {
    final d   = isDark;
    final idx = categories.indexWhere((c) => c == selected);
    return Container(
      color: _c(d, _L.topbar, _D.bg),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(children: [Expanded(child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(categories.length, (i) {
            final active = idx == i;
            final cat    = categories[i];
            return GestureDetector(onTap: () => onCategorySelected(cat),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(cat.name, style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold,
                      color: active ? _c(d, _L.espresso, _D.text)
                          : _c(d, _L.caramel, _D.caramel))),
                  const SizedBox(height: 6),
                  AnimatedContainer(duration: const Duration(milliseconds: 250),
                      height: 2.5, width: active ? 32 : 0,
                      decoration: BoxDecoration(
                          color: _c(d, _L.latte, _D.accent),
                          borderRadius: BorderRadius.circular(2))),
                ]));
          })))]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SECTION CHIPS
// ─────────────────────────────────────────────────────────────

class SectionChips extends StatelessWidget {
  final bool isDark;
  final List<String> sections;
  final String       selected;
  final ValueChanged<String> onSectionSelected;

  const SectionChips({super.key,
    required this.isDark, required this.sections,
    required this.selected, required this.onSectionSelected});

  @override Widget build(BuildContext context) {
    final d = isDark;
    return SizedBox(height: 44, child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final sec    = sections[i];
          final active = sec == selected;
          return GestureDetector(onTap: () => onSectionSelected(sec),
              child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                      color: active ? _c(d, _L.roast, _D.accent) : _c(d, _L.steam, _D.card),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: active ? [BoxShadow(
                          color: _L.espresso.withOpacity(0.25),
                          blurRadius: 8, offset: const Offset(0, 3))] : []),
                  child: Text(sec, style: TextStyle(
                      color: active
                          ? (d ? const Color(0xFF1A0F0A) : Colors.white)
                          : _c(d, _L.caramel, _D.caramel),
                      fontWeight: FontWeight.w700, fontSize: 13))));
        }));
  }
}

// ─────────────────────────────────────────────────────────────
// SECTION STYLE HELPER
// ─────────────────────────────────────────────────────────────

class _SectionStyle {
  final Color bg, accent; final String icon, label;
  const _SectionStyle({required this.bg, required this.accent,
    required this.icon, required this.label});
}

_SectionStyle _sStyle(String section) {
  final s = section.trim().toLowerCase();
  if (s.contains('coffee'))
    return const _SectionStyle(bg: _L.caramel, accent: _L.latte, icon: '☕', label: 'Coffee');
  if (s.contains('milktea') || s.contains('milk tea'))
    return const _SectionStyle(bg: Color(0xFF5C4A72), accent: Color(0xFFCEA8F0), icon: '🧋', label: 'Milk Tea');
  if (s.contains('snack'))
    return const _SectionStyle(bg: Color(0xFF7A3B1E), accent: Color(0xFFFFCC80), icon: '🍿', label: 'Snacks');
  return const _SectionStyle(bg: _L.caramel, accent: _L.steam, icon: '🛍', label: 'Other');
}

// ─────────────────────────────────────────────────────────────
// PRODUCT CARD
// ─────────────────────────────────────────────────────────────

class ProductCard extends StatefulWidget {
  final bool isDark;
  final String productId, name, section;
  final double price;
  final String? imageUrl;
  final VoidCallback onDeleted, onBeforeMenuAction;
  final Function(double) onPriceUpdated;

  const ProductCard({super.key,
    required this.isDark, required this.productId, required this.name,
    required this.section, required this.price, this.imageUrl,
    required this.onDeleted, required this.onPriceUpdated,
    required this.onBeforeMenuAction});

  @override State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 120),
      lowerBound: 0, upperBound: 0.03);
  late final Animation<double> _scale =
  Tween<double>(begin: 1.0, end: 0.97)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  void _showEdit() {
    final d    = widget.isDark;
    final ctrl = TextEditingController(text: widget.price.toStringAsFixed(0));
    showDialog(context: context, builder: (_) => AlertDialog(
        backgroundColor: _c(d, _L.cream, _D.card),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _L.latte.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.edit_outlined, color: _c(d, _L.roast, _D.text), size: 18)),
          const SizedBox(width: 10),
          Text('Update Price', style: TextStyle(fontSize: 16,
              fontWeight: FontWeight.w700, color: _c(d, _L.espresso, _D.text))),
        ]),
        content: TextField(
            controller: ctrl, autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                color: _c(d, _L.espresso, _D.text)),
            decoration: InputDecoration(
                prefixText: '₱ ',
                prefixStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                    color: _c(d, _L.caramel, _D.caramel)),
                filled: true, fillColor: _c(d, _L.steam, _D.topbar),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _L.latte, width: 2)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: _L.caramel))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _L.roast,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                final v = double.tryParse(ctrl.text.trim());
                if (v != null && v >= 0) widget.onPriceUpdated(v);
                Navigator.pop(context);
              },
              child:  Text('Save', style: TextStyle(color: _c(d, _L.roast, _D.text)),)),
        ]));
  }

  void _showDelete() {
    final d = widget.isDark;
    showDialog(context: context, builder: (_) => AlertDialog(
        backgroundColor: _c(d, _L.cream, _D.card),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _L.rust.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.delete_outline, color: _L.rust, size: 18)),
          const SizedBox(width: 10),
          Text('Remove Product', style: TextStyle(fontSize: 16,
              fontWeight: FontWeight.w700, color: _c(d, _L.espresso, _D.text))),
        ]),
        content: RichText(text: TextSpan(
            style: TextStyle(color: _c(d, _L.caramel, _D.caramel),
                fontSize: 14, height: 1.5),
            children: [
              const TextSpan(text: 'Remove '),
              TextSpan(text: '"${widget.name}"',
                  style: TextStyle(fontWeight: FontWeight.w700,
                      color: _c(d, _L.espresso, _D.text))),
              const TextSpan(text: " from the menu? This can't be undone."),
            ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: _L.caramel))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _L.rust,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () { widget.onDeleted(); Navigator.pop(context); },
              child: const Text('Remove')),
        ]));
  }

  @override Widget build(BuildContext context) {
    final d   = widget.isDark;
    final sty = _sStyle(widget.section);
    final url = (widget.imageUrl ?? '').trim();

    return GestureDetector(
        onTapDown: (_) => _ctrl.forward(), onTapUp: (_) => _ctrl.reverse(),
        onTapCancel: () => _ctrl.reverse(),
        child: AnimatedBuilder(animation: _scale,
            builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
            child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                    color: _c(d, _L.cream, _D.card), borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(
                        color: _L.espresso.withOpacity(d ? 0.25 : 0.08),
                        blurRadius: 18, offset: const Offset(0, 6))]),
                child: ClipRRect(borderRadius: BorderRadius.circular(22),
                    child: IntrinsicHeight(child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // accent stripe
                          Container(width: 5, decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                  colors: [sty.bg, sty.accent]))),
                          // image
                          Container(width: 88, height: 88,
                              margin: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: sty.bg.withOpacity(0.07)),
                              child: ClipRRect(borderRadius: BorderRadius.circular(16),
                                  child: url.isEmpty
                                      ? Center(child: Text(sty.icon,
                                      style: const TextStyle(fontSize: 30)))
                                      : Image.network(url, fit: BoxFit.cover,
                                      loadingBuilder: (_, c, p) => p == null ? c
                                          : Center(child: CircularProgressIndicator(
                                          strokeWidth: 2, color: sty.bg)),
                                      errorBuilder: (_, __, ___) => Center(
                                          child: Text(sty.icon,
                                              style: const TextStyle(fontSize: 30)))))),
                          // info
                          Expanded(child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 14, 4, 14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Container(padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: sty.bg.withOpacity(0.10),
                                            borderRadius: BorderRadius.circular(6)),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          Text(sty.icon, style: const TextStyle(fontSize: 9)),
                                          const SizedBox(width: 4),
                                          Text(sty.label.toUpperCase(), style: TextStyle(
                                              fontSize: 9, fontWeight: FontWeight.w800,
                                              color: sty.bg, letterSpacing: 0.8)),
                                        ])),
                                    const SizedBox(height: 6),
                                    Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                                            color: _c(d, _L.espresso, _D.text), height: 1.2)),
                                    const SizedBox(height: 8),
                                    Container(padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                            color: _L.latte.withOpacity(d ? 0.22 : 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: _L.latte.withOpacity(0.35))),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          const Text('₱', style: TextStyle(fontSize: 11,
                                              fontWeight: FontWeight.w700, color: _L.caramel)),
                                          const SizedBox(width: 2),
                                          Text(widget.price.toStringAsFixed(2),
                                              style: TextStyle(fontSize: 15,
                                                  fontWeight: FontWeight.w800,
                                                  color: _c(d, _L.roast, _D.accent))),
                                        ])),
                                  ]))),
                          // popup menu
                          Padding(padding: const EdgeInsets.only(top: 6, right: 4),
                              child: PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert, size: 20,
                                      color: _c(d, _L.caramel, _D.caramel).withOpacity(0.6)),
                                  color: _c(d, _L.cream, _D.card),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)), elevation: 6,
                                  onOpened: () {
                                    widget.onBeforeMenuAction();
                                    FocusManager.instance.primaryFocus?.unfocus();
                                  },
                                  onSelected: (v) {
                                    FocusManager.instance.primaryFocus?.unfocus();
                                    if (v == 'edit')   _showEdit();
                                    if (v == 'delete') _showDelete();
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(value: 'edit', child: Row(children: [
                                      Container(padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(color: _L.latte.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(8)),
                                          child:  Icon(Icons.edit_outlined, size: 16, color: _c(d, _L.roast, _D.text))),
                                      const SizedBox(width: 10),
                                      Text('Update Price', style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: _c(d, _L.espresso, _D.text))),
                                    ])),
                                    const PopupMenuDivider(),
                                    PopupMenuItem(value: 'delete', child: Row(children: [
                                      Container(padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(color: _L.rust.withOpacity(0.10),
                                              borderRadius: BorderRadius.circular(8)),
                                          child: const Icon(Icons.delete_outline, size: 16, color: _L.rust)),
                                      const SizedBox(width: 10),
                                      const Text('Remove', style: TextStyle(
                                          fontWeight: FontWeight.w600, color: _L.rust)),
                                    ])),
                                  ])),
                        ]))))));
    }
}

// ─────────────────────────────────────────────────────────────
// INVENTORY CARD
// ─────────────────────────────────────────────────────────────

class InventoryCard extends StatelessWidget {
  final bool isDark;
  final String name, section, unit;
  final double price;
  final String? imageUrl, barcode;
  final int quantity, reorderLevel, alertThreshold;
  final Future<void> Function() onAddStock, onReduceStock;
  final VoidCallback onDeleted, onBeforeMenuAction;

  const InventoryCard({super.key,
    required this.isDark, required this.name, required this.section,
    required this.price, this.imageUrl, this.barcode,
    required this.quantity, required this.unit, required this.reorderLevel,
    required this.alertThreshold, required this.onAddStock,
    required this.onReduceStock, required this.onDeleted,
    required this.onBeforeMenuAction});

  bool get isLow => quantity > 0 && quantity <= reorderLevel.clamp(1, alertThreshold + 1);
  bool get isOut => quantity <= 0;

  Color get _sc {
    if (isOut) return _L.rust;
    if (isLow) return _L.amber;
    return _L.matcha;
  }

  String get _sl {
    if (isOut) return 'Out of Stock';
    if (isLow) return 'Low Stock';
    return 'In Stock';
  }

  void _showDeleteDialog(BuildContext ctx) {
    final d = isDark;
    showDialog(context: ctx, builder: (_) => AlertDialog(
        backgroundColor: _c(d, _L.cream, _D.card),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove Item', style: TextStyle(
            color: _c(d, _L.espresso, _D.text), fontWeight: FontWeight.w700)),
        content: Text('Remove "$name" from inventory? This can\'t be undone.',
            style: TextStyle(color: _c(d, _L.caramel, _D.caramel))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: _L.caramel))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _L.rust,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () { onDeleted(); Navigator.pop(ctx); },
              child: const Text('Remove')),
        ]));
  }

  @override Widget build(BuildContext ctx) {
    final d   = isDark;
    final url = (imageUrl ?? '').trim();
    final bc  = (barcode  ?? '').trim();
    final nc  = _c(d, _L.espresso, _D.text);
    final sc  = _c(d, _L.caramel, _D.caramel);

    return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
            color: _c(d, _L.cream, _D.card), borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(
                color: _L.espresso.withOpacity(d ? 0.25 : 0.07),
                blurRadius: 14, offset: const Offset(0, 6))]),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(borderRadius: BorderRadius.circular(14),
                    child: url.isEmpty
                        ? Container(width: 68, height: 68,
                        color: _c(d, _L.steam, _D.topbar),
                        child: Icon(Icons.inventory_2_outlined, color: sc, size: 28))
                        : Image.network(url, width: 68, height: 68, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            width: 68, height: 68, color: _c(d, _L.steam, _D.topbar),
                            child: Icon(Icons.broken_image_outlined, color: sc)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                            color: nc, height: 1.2))),
                    const SizedBox(width: 6),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _sc.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(_sl, style: TextStyle(fontSize: 10,
                            fontWeight: FontWeight.bold, color: _sc))),
                  ]),
                  if (bc.isNotEmpty) ...[const SizedBox(height: 5),
                    Row(children: [
                      Icon(Icons.qr_code, size: 13, color: sc),
                      const SizedBox(width: 4),
                      Expanded(child: Text(bc, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: sc.withOpacity(0.8),
                              letterSpacing: 0.5, fontFamily: 'monospace'))),
                    ])],
                  const SizedBox(height: 5),
                  Row(children: [
                    Icon(Icons.payments_outlined, size: 13, color: sc),
                    const SizedBox(width: 4),
                    Text('₱${price.toStringAsFixed(2)}', style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: _c(d, _L.roast, _D.accent))),
                  ]),
                ])),
                PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_vert, size: 20,
                        color: sc.withOpacity(0.6)),
                    color: _c(d, _L.cream, _D.card),
                    onOpened: () {
                      onBeforeMenuAction();
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                    onSelected: (v) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      if (v == 'delete') _showDeleteDialog(ctx);
                    },
                    itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: Row(children: [
                      Container(padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: _L.rust.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.delete_outline, size: 16, color: _L.rust)),
                      const SizedBox(width: 10),
                      const Text('Remove', style: TextStyle(
                          fontWeight: FontWeight.w600, color: _L.rust)),
                    ]))]),
              ])),

          // stock row
          Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: _sc.withOpacity(d ? 0.12 : 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _sc.withOpacity(0.15))),
              child: Row(children: [
                Icon(Icons.inventory_2_outlined, size: 16, color: _sc),
                const SizedBox(width: 8),
                Text('Stock', style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600, color: sc)),
                const Spacer(),
                _sBtn(Icons.remove, onReduceStock),
                const SizedBox(width: 10),
                Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                        color: _c(d, _L.cream, _D.topbar),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _sc.withOpacity(0.35), width: 1.5)),
                    child: Text('$quantity $unit', style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: _sc))),
                const SizedBox(width: 10),
                _sBtn(Icons.add, onAddStock),
              ])),
        ]));
  }

  Widget _sBtn(IconData icon, Future<void> Function() onTap) =>
      InkWell(onTap: () => onTap(), borderRadius: BorderRadius.circular(10),
          child: Container(width: 32, height: 32,
              decoration: BoxDecoration(color: _sc.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 16, color: _sc)));
}

// ─────────────────────────────────────────────────────────────
// INVENTORY SUMMARY
// ─────────────────────────────────────────────────────────────

class _InvSummary {
  final int stockQty, reorderLevel;
  _InvSummary({required this.stockQty, required this.reorderLevel});
}

class InventorySummaryFromFirestore extends StatelessWidget {
  final List<_InvSummary> items; final bool isDark;
  const InventorySummaryFromFirestore({super.key,
    required this.items, required this.isDark});

  @override Widget build(BuildContext context) {
    final total = items.length;
    final out   = items.where((i) => i.stockQty <= 0).length;
    final low   = items.where((i) =>
    i.stockQty > 0 && i.stockQty <= i.reorderLevel).length;

    return Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [_L.espresso, _L.roast],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: _L.espresso.withOpacity(0.25),
                blurRadius: 12, offset: const Offset(0, 5))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _Stat('Total Items', '$total', Colors.white),
          Container(width: 1, height: 28, color: Colors.white.withOpacity(0.15)),
          _Stat('Low Stock', '$low', _L.amber),
          Container(width: 1, height: 28, color: Colors.white.withOpacity(0.15)),
          _Stat('Out of Stock', '$out', const Color(0xFFEF9A9A)),
        ]));
  }
}

class _Stat extends StatelessWidget {
  final String label, value; final Color vc;
  const _Stat(this.label, this.value, this.vc);
  @override Widget build(_) => Column(mainAxisSize: MainAxisSize.min, children: [
    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: vc)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
  ]);
}

// ─────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────

class _CafeEmptyState extends StatelessWidget {
  final bool isDark; final String icon, message, sub;
  const _CafeEmptyState({required this.isDark, required this.icon,
    required this.message, required this.sub});

  @override Widget build(BuildContext context) {
    final d = isDark;
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 80, height: 80,
          decoration: BoxDecoration(color: _c(d, _L.steam, _D.card), shape: BoxShape.circle),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 36)))),
      const SizedBox(height: 16),
      Text(message, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
          color: _c(d, _L.espresso, _D.text))),
      const SizedBox(height: 6),
      Text(sub, style: TextStyle(fontSize: 13,
          color: _c(d, _L.caramel, _D.caramel))),
    ]));
  }
}
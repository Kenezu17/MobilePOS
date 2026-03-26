import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? "";

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('users').doc(_uid).collection('products');

  CollectionReference<Map<String, dynamic>> get _inventory =>
      _db.collection('users').doc(_uid).collection('inventory');

  // ─── STREAMS ────────────────────────────────────────────────

  /// Products tab — no filter needed, products collection is products-only now
  Stream<QuerySnapshot<Map<String, dynamic>>> watchProducts() {
    return _products
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Inventory tab — single collection, no join needed
  Stream<List<Map<String, dynamic>>> watchInventoryMerged(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('inventory')
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
      final d = doc.data();
      return <String, dynamic>{
        'id':           doc.id,
        'name':         d['name']         ?? 'Unknown',
        'section':      d['section']      ?? '',
        'sellPrice':    d['sellPrice']    ?? 0,
        'imageUrl':     d['imageUrl']     ?? '',
        'barcode':      d['barcode']      ?? '',
        'buyPrice':     d['buyPrice']     ?? 0,
        'stockQty':     d['stockQty']     ?? 0,
        'unit':         d['unit']         ?? 'pcs',
        'reorderLevel': d['reorderLevel'] ?? 0,
      };
    }).toList());
  }

  // ─── PRODUCTS TAB ────────────────────────────────────────────

  /// Add to Products collection only
  Future<String> addProduct({
    required String name,
    required String section,
    required double price,
    String? imageUrl,
    String? barcode,
  }) async {
    final doc = _products.doc();
    await doc.set({
      'name':      name,
      'section':   section,
      'sellPrice': price,
      'imageUrl':  imageUrl ?? '',
      'barcode':   barcode  ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Delete from Products collection
  Future<void> deleteProduct(String productId) async {
    await _products.doc(productId).delete();
  }

  /// Update product fields
  Future<void> updateProduct(
      String productId, {
        String? name,
        String? section,
        double? sellPrice,
        String? imageUrl,
        String? barcode,
      }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name      != null) data['name']      = name;
    if (section   != null) data['section']   = section;
    if (sellPrice != null) data['sellPrice'] = sellPrice;
    if (imageUrl  != null) data['imageUrl']  = imageUrl;
    if (barcode   != null) data['barcode']   = barcode;

    await _products.doc(productId).set(data, SetOptions(merge: true));
  }

  // ─── INVENTORY TAB ───────────────────────────────────────────

  /// Add to Inventory collection only — all fields in one doc
  Future<String> addInventoryItem({
    required String name,
    required String section,
    required double price,
    String? imageUrl,
    String? barcode,
    int initialStock = 0,
    String unit = "pcs",
    int reorderLevel = 0,
  }) async {
    final doc = _inventory.doc();

    await doc.set({
      // display fields
      'name':         name,
      'section':      section,
      'sellPrice':    price,
      'imageUrl':     imageUrl ?? '',
      'barcode':      barcode  ?? '',
      // stock fields
      'stockQty':     initialStock < 0 ? 0 : initialStock,
      'unit':         unit,
      'reorderLevel': reorderLevel < 0 ? 0 : reorderLevel,
      'buyPrice':     0,
      // meta
      'createdAt':    FieldValue.serverTimestamp(),
      'updatedAt':    FieldValue.serverTimestamp(),
    });

    return doc.id;
  }

  /// Delete from Inventory — single doc delete
  Future<void> deleteInventoryItem(String productId) async {
    await _inventory.doc(productId).delete();
  }

  /// Update inventory — display + stock fields
  Future<void> updateInventory(
      String productId, {
        String? name,
        String? section,
        double? sellPrice,
        String? imageUrl,
        String? barcode,
        String? unit,
        int?    reorderLevel,
        int?    buyPrice,
        int?    stockQty,
      }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name         != null) data['name']         = name;
    if (section      != null) data['section']      = section;
    if (sellPrice    != null) data['sellPrice']    = sellPrice;
    if (imageUrl     != null) data['imageUrl']     = imageUrl;
    if (barcode      != null) data['barcode']      = barcode;
    if (unit         != null) data['unit']         = unit;
    if (reorderLevel != null) data['reorderLevel'] = reorderLevel < 0 ? 0 : reorderLevel;
    if (buyPrice     != null) data['buyPrice']     = buyPrice     < 0 ? 0 : buyPrice;
    if (stockQty     != null) data['stockQty']     = stockQty     < 0 ? 0 : stockQty;

    await _inventory.doc(productId).set(data, SetOptions(merge: true));
  }

  // ─── STOCK ──────────────────────────────────────────────────

  Future<void> setStock(String productId, int qty) async {
    await _inventory.doc(productId).update({
      'stockQty':  qty < 0 ? 0 : qty,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> adjustStock(String productId, int delta) async {
    final ref = _inventory.doc(productId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);

      if (!snap.exists) {
        tx.set(ref, {
          'stockQty':     delta < 0 ? 0 : delta,
          'unit':         'pcs',
          'reorderLevel': 0,
          'buyPrice':     0,
          'updatedAt':    FieldValue.serverTimestamp(),
        });
        return;
      }

      final current = (snap.data()?['stockQty'] ?? 0) as int;
      final next    = current + delta;

      tx.update(ref, {
        'stockQty':  next < 0 ? 0 : next,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ─── READ ───────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getInventoryItem(String productId) async {
    final snap = await _inventory.doc(productId).get();
    return snap.exists ? {'id': snap.id, ...snap.data()!} : null;
  }

  Future<Map<String, dynamic>?> getProduct(String productId) async {
    final snap = await _products.doc(productId).get();
    return snap.exists ? {'id': snap.id, ...snap.data()!} : null;
  }
}
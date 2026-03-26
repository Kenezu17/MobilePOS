import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ApiService {
  static const String baseUrl = "http://127.0.0.1:8081/api";

  // ← your remove.bg API key
  static const String _removeBgApiKey = "ihoP1uvKtZV8kQkDbi3PEG5k";

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? "GUEST";

  Map<String, String> get _headers => {
    "X-User-Id": _uid,
    "Content-Type": "application/json",
    "Accept": "application/json",
  };

  // ─────────────────────────────────────────
  // REMOVE BACKGROUND  →  remove.bg API
  // ─────────────────────────────────────────
  //
  // Uses size=preview (0.25 megapixel) which is FREE on the free plan.
  // Full-resolution costs credits — preview is fine for product thumbnails.

  Future<File?> removeBg(File imageFile) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.remove.bg/v1.0/removebg'),
      );

      request.headers['X-Api-Key'] = _removeBgApiKey;
      request.fields['size'] = 'preview'; // ← free tier, no credits used
      request.files.add(
        await http.MultipartFile.fromPath('image_file', imageFile.path),
      );

      final streamed = await request.send().timeout(const Duration(seconds: 60));

      if (streamed.statusCode == 200) {
        final bytes = await streamed.stream.toBytes();
        final tempDir = await getTemporaryDirectory();
        final outFile = File(
          '${tempDir.path}/rmbg_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await outFile.writeAsBytes(bytes);
        debugPrint('[removeBg] Success — saved to ${outFile.path}');
        return outFile;
      } else {
        final body = await streamed.stream.bytesToString();
        debugPrint('[removeBg] Failed — falling back to original image. Reason: remove.bg error: $body');
        return null;
      }
    } on SocketException {
      debugPrint('[removeBg] No internet — falling back to original image.');
      return null;
    } on TimeoutException {
      debugPrint('[removeBg] Timeout — falling back to original image.');
      return null;
    } catch (e) {
      debugPrint('[removeBg] Exception: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────
  // PROFILE IMAGE  →  local Spring Boot server
  // ─────────────────────────────────────────

  Future<String> uploadProfileImage(File file) async {
    try {
      final request = http.MultipartRequest(
          "POST", Uri.parse("$baseUrl/profile/image"))
        ..headers.addAll({"X-User-Id": _uid, "Accept": "application/json"})
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return toRelativePath(data['imageUrl'] as String);
      }
      throw "Profile image upload failed: ${response.statusCode} ${response.body}";
    } on SocketException {
      throw _connectionError();
    } on TimeoutException {
      throw "TIMEOUT: Server took too long uploading image.";
    }
  }

  // ─────────────────────────────────────────
  // GCASH QR IMAGE  →  local Spring Boot server
  // ─────────────────────────────────────────

  Future<String> uploadQrImage(File file) async {
    try {
      final request = http.MultipartRequest(
          "POST", Uri.parse("$baseUrl/profile/image"))
        ..headers.addAll({"X-User-Id": _uid, "Accept": "application/json"})
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return toRelativePath(data['imageUrl'] as String);
      }
      throw "QR image upload failed: ${response.statusCode} ${response.body}";
    } on SocketException {
      throw _connectionError();
    } on TimeoutException {
      throw "TIMEOUT: Server took too long uploading QR image.";
    }
  }

  // ─────────────────────────────────────────
  // IMAGE URL HELPERS
  // ─────────────────────────────────────────

  static String toRelativePath(String url) {
    if (url.isEmpty) return url;
    if (url.contains('127.0.0.1') || url.contains('localhost')) {
      try {
        return Uri.parse(url).path;
      } catch (_) {
        return url;
      }
    }
    return url;
  }

  static String resolveImageUrl(String storedPath) {
    if (storedPath.isEmpty) return storedPath;
    if (storedPath.startsWith('http')) return storedPath;
    final host = baseUrl.replaceFirst(RegExp(r'/api$'), '');
    return '$host$storedPath';
  }

  // ─────────────────────────────────────────
  // AUTH
  // ─────────────────────────────────────────

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .put(Uri.parse("$baseUrl/auth/change-password"),
          headers: _headers,
          body: jsonEncode({"oldPassword": oldPassword, "newPassword": newPassword}))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        debugPrint("[ApiService.changePassword] ${response.statusCode}: ${response.body}");
      }
    } on SocketException {
      debugPrint("[ApiService.changePassword] Server unreachable — skipped local sync.");
    } on TimeoutException {
      debugPrint("[ApiService.changePassword] TIMEOUT — skipped local sync.");
    } catch (e) {
      debugPrint("[ApiService.changePassword] Unexpected error: $e");
    }
  }

  // ─────────────────────────────────────────
  // PRODUCTS
  // ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getProducts() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/products"), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      }
      throw "Failed to load products: ${response.statusCode} ${response.body}";
    } on SocketException {
      throw _connectionError();
    } on TimeoutException {
      throw "TIMEOUT: Server is taking too long to respond.";
    }
  }

  Future<String> createProduct({
    required String name,
    required String section,
    required double sellPrice,
    String? imageUrl,
    String? barcode,
    int? initialStock,
    String? unit,
    int? reorderLevel,
  }) async {
    try {
      final body = {
        "name": name,
        "section": section,
        "sellPrice": sellPrice,
        if (imageUrl != null) "imageUrl": imageUrl,
        if (barcode != null) "barcode": barcode,
        if (initialStock != null) "initialStock": initialStock,
        if (unit != null) "unit": unit,
        if (reorderLevel != null) "reorderLevel": reorderLevel,
      };
      final response = await http
          .post(Uri.parse("$baseUrl/products"),
          headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body)['id'] as String;
      }
      throw "Failed to create product: ${response.statusCode} ${response.body}";
    } on SocketException {
      throw _connectionError();
    } on TimeoutException {
      throw "TIMEOUT: Server is taking too long to respond.";
    }
  }

  Future<void> updateProduct(String id, {
    String? name, String? section, double? sellPrice,
    String? imageUrl, String? barcode, String? unit, int? reorderLevel,
  }) async {
    try {
      final body = {
        if (name != null) "name": name,
        if (section != null) "section": section,
        if (sellPrice != null) "sellPrice": sellPrice,
        if (imageUrl != null) "imageUrl": imageUrl,
        if (barcode != null) "barcode": barcode,
        if (unit != null) "unit": unit,
        if (reorderLevel != null) "reorderLevel": reorderLevel,
      };
      final response = await http
          .put(Uri.parse("$baseUrl/products/$id"),
          headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw "Failed to update product: ${response.statusCode} ${response.body}";
      }
    } on SocketException {
      throw _connectionError();
    } on TimeoutException {
      throw "TIMEOUT: Server is taking too long to respond.";
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      final response = await http
          .delete(Uri.parse("$baseUrl/products/$id"), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw "Failed to delete product: ${response.statusCode} ${response.body}";
      }
    } on SocketException {
      throw _connectionError();
    } on TimeoutException {
      throw "TIMEOUT: Server is taking too long to respond.";
    }
  }

  Future<String> uploadProductImage(File file) async {
    try {
      final request = http.MultipartRequest(
          "POST", Uri.parse("$baseUrl/products/image"))
        ..headers.addAll({"X-User-Id": _uid, "Accept": "application/json"})
        ..files.add(await http.MultipartFile.fromPath('file', file.path));
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return resolveImageUrl(
            toRelativePath(jsonDecode(response.body)['imageUrl'] as String));
      }
      throw "Image upload failed: ${response.statusCode} ${response.body}";
    } on SocketException {
      throw _connectionError();
    } on TimeoutException {
      throw "TIMEOUT: Server took too long uploading image.";
    }
  }

  // ─────────────────────────────────────────
  // INVENTORY
  // ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getInventory() async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/inventory"), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      }
      throw "Failed to load inventory: ${response.statusCode} ${response.body}";
    } on SocketException {
      throw _connectionError();
    } on TimeoutException {
      throw "TIMEOUT: Server is taking too long to respond.";
    }
  }

  Future<void> updateInventory(String productId, {
    required int stock, int? reorderLevel, String? unit,
  }) async {
    try {
      final body = {
        "stock": stock,
        if (reorderLevel != null) "reorderLevel": reorderLevel,
        if (unit != null) "unit": unit,
      };
      final response = await http
          .put(Uri.parse("$baseUrl/inventory/$productId"),
          headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw "Failed to update inventory: ${response.statusCode} ${response.body}";
      }
    } on SocketException {
      throw _connectionError();
    } on TimeoutException {
      throw "TIMEOUT: Server is taking too long to respond.";
    }
  }

  Future<void> adjustStock(String productId, int delta) async {
    try {
      final response = await http
          .post(Uri.parse("$baseUrl/inventory/$productId/adjust?delta=$delta"),
          headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw "Failed to adjust stock: ${response.statusCode} ${response.body}";
      }
    } on SocketException {
      throw _connectionError();
    } on TimeoutException {
      throw "TIMEOUT: Server is taking too long to respond.";
    }
  }

  Future<void> deleteInventory(String productId) async {
    try {
      final response = await http
          .delete(Uri.parse("$baseUrl/inventory/$productId"), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw "Failed to delete inventory: ${response.statusCode} ${response.body}";
      }
    } on SocketException {
      throw _connectionError();
    } on TimeoutException {
      throw "TIMEOUT: Server is taking too long to respond.";
    }
  }

  // ─────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────

  String _connectionError() =>
      "CONNECTION REFUSED.\n\n"
          "1. Connect USB cable.\n"
          "2. Run 'adb reverse tcp:8081 tcp:8081' in terminal.\n"
          "3. Ensure Spring Boot is running on port 8081.";
}
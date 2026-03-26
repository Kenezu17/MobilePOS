import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? "unknown";

  /// Uploads an image to Firebase Storage.
  Future<String> uploadImage(File file) async {
    final uid = _uid;
    if (uid == "unknown") {
      throw Exception("User must be logged in to upload images.");
    }

    try {
      final fileName = "${DateTime.now().millisecondsSinceEpoch}.png";

      final ref = _storage.ref()
          .child('users')
          .child(uid)
          .child('products')
          .child(fileName);
      
      // Start upload
      final UploadTask uploadTask = ref.putFile(
        file,
        SettableMetadata(contentType: 'image/png'),
      );

      // Await completion snapshot
      final TaskSnapshot snapshot = await uploadTask;
      
      // Get the URL from the snapshot reference
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      
      return downloadUrl;
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') {
        throw Exception("Storage bucket error: Please ensure Firebase Storage is enabled in the Console.");
      }
      throw Exception("Upload failed: ${e.message}");
    } catch (e) {
      throw Exception("An unexpected error occurred: $e");
    }
  }
}

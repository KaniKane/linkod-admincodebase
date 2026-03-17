import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

/// Service for managing barangay information postings within categories
class BarangayPostingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static const String _collection = 'barangayPostings';

  /// Get all postings for a category stream
  static Stream<List<Map<String, dynamic>>> getPostingsStream(
    String categoryId,
  ) {
    return _firestore
        .collection(_collection)
        .where('categoryId', isEqualTo: categoryId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            return {'id': doc.id, ...data};
          }).toList(),
        );
  }

  /// Get all postings for a category (one-time)
  static Future<List<Map<String, dynamic>>> getPostings(
    String categoryId,
  ) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('categoryId', isEqualTo: categoryId)
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {'id': doc.id, ...data};
    }).toList();
  }

  /// Upload image file to Firebase Storage
  static Future<String> uploadImage(
    File imageFile,
    String categoryId,
    String postingId,
  ) async {
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${path.basename(imageFile.path)}';
    final ref = _storage.ref().child(
      'barangay_postings/$categoryId/$postingId/$fileName',
    );
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {'uploadedBy': 'admin'},
    );
    await ref.putFile(imageFile, metadata);
    return await ref.getDownloadURL();
  }

  /// Upload PDF file to Firebase Storage
  static Future<String> uploadPdf(
    File pdfFile,
    String categoryId,
    String postingId,
  ) async {
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${path.basename(pdfFile.path)}';
    final ref = _storage.ref().child(
      'barangay_postings/$categoryId/$postingId/$fileName',
    );
    final metadata = SettableMetadata(
      contentType: 'application/pdf',
      customMetadata: {'uploadedBy': 'admin'},
    );
    await ref.putFile(pdfFile, metadata);
    return await ref.getDownloadURL();
  }

  /// Upload multiple image files to Firebase Storage
  static Future<List<String>> uploadMultipleImages(
    List<File> imageFiles,
    String categoryId,
    String postingId,
  ) async {
    final urls = <String>[];
    for (final imageFile in imageFiles) {
      final url = await uploadImage(imageFile, categoryId, postingId);
      urls.add(url);
    }
    return urls;
  }

  /// Create a new posting with multiple images
  static Future<String> createPosting({
    required String categoryId,
    required String title,
    required String description,
    List<String>? imageUrls,
    String? pdfUrl,
    String? pdfName,
    String? imageUrl,
  }) async {
    final docRef = await _firestore.collection(_collection).add({
      'categoryId': categoryId,
      'title': title,
      'description': description,
      'imageUrls': imageUrls ?? [],
      'pdfUrl': pdfUrl,
      'pdfName': pdfName,
      'date': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Update an existing posting with multiple images
  static Future<void> updatePosting({
    required String postingId,
    required String title,
    required String description,
    List<String>? imageUrls,
    String? pdfUrl,
    String? pdfName,
    bool removePdf = false,
    String? imageUrl,
  }) async {
    final updateData = <String, dynamic>{
      'title': title,
      'description': description,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (imageUrls != null) {
      updateData['imageUrls'] = imageUrls;
    }
    if (pdfUrl != null) {
      updateData['pdfUrl'] = pdfUrl;
    } else if (removePdf) {
      updateData['pdfUrl'] = FieldValue.delete();
      updateData['pdfName'] = FieldValue.delete();
    }
    if (pdfName != null && !removePdf) {
      updateData['pdfName'] = pdfName;
    }

    await _firestore.collection(_collection).doc(postingId).update(updateData);
  }

  /// Delete a posting
  static Future<void> deletePosting(String postingId) async {
    await _firestore.collection(_collection).doc(postingId).delete();
  }
}

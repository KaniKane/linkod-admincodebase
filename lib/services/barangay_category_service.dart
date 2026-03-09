import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for managing barangay information categories in Firestore
class BarangayCategoryService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'barangayCategories';

  /// Get all categories stream
  static Stream<List<Map<String, dynamic>>> getCategoriesStream() {
    return _firestore
        .collection(_collection)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return {
                'id': doc.id,
                ...data,
              };
            }).toList());
  }

  /// Get all categories (one-time)
  static Future<List<Map<String, dynamic>>> getCategories() async {
    final snapshot = await _firestore
        .collection(_collection)
        .orderBy('createdAt', descending: false)
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        ...data,
      };
    }).toList();
  }

  /// Create a new category
  static Future<String> createCategory({
    required String title,
    required String description,
    required int iconCodePoint,
    required String iconFontFamily,
    required String iconPackage,
  }) async {
    final docRef = await _firestore.collection(_collection).add({
      'title': title,
      'description': description,
      'iconCodePoint': iconCodePoint,
      'iconFontFamily': iconFontFamily,
      'iconPackage': iconPackage,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Update an existing category
  static Future<void> updateCategory({
    required String categoryId,
    required String title,
    required String description,
    required int iconCodePoint,
    required String iconFontFamily,
    required String iconPackage,
  }) async {
    await _firestore.collection(_collection).doc(categoryId).update({
      'title': title,
      'description': description,
      'iconCodePoint': iconCodePoint,
      'iconFontFamily': iconFontFamily,
      'iconPackage': iconPackage,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete a category
  static Future<void> deleteCategory(String categoryId) async {
    await _firestore.collection(_collection).doc(categoryId).delete();
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

/// Service for managing barangay branding assets (logo and cover image)
class BarangayBrandingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static const String _collection = 'barangaySettings';
  static const String _documentId = 'branding';

  /// Get the branding settings document
  static Future<Map<String, dynamic>?> getBranding() async {
    final doc = await _firestore.collection(_collection).doc(_documentId).get();
    if (doc.exists) {
      return doc.data();
    }
    return null;
  }

  /// Stream of branding settings for real-time updates
  static Stream<Map<String, dynamic>?> getBrandingStream() {
    return _firestore
        .collection(_collection)
        .doc(_documentId)
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  /// Upload logo image to Firebase Storage
  static Future<String> uploadLogo(File imageFile) async {
    final fileName = 'logo_${DateTime.now().millisecondsSinceEpoch}_${path.basename(imageFile.path)}';
    final ref = _storage.ref().child('barangay_branding/logo/$fileName');
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {'uploadedBy': 'admin', 'type': 'logo'},
    );
    await ref.putFile(imageFile, metadata);
    return await ref.getDownloadURL();
  }

  /// Upload cover image to Firebase Storage
  static Future<String> uploadCoverImage(File imageFile) async {
    final fileName = 'cover_${DateTime.now().millisecondsSinceEpoch}_${path.basename(imageFile.path)}';
    final ref = _storage.ref().child('barangay_branding/cover/$fileName');
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {'uploadedBy': 'admin', 'type': 'cover'},
    );
    await ref.putFile(imageFile, metadata);
    return await ref.getDownloadURL();
  }

  /// Update branding settings with new URLs
  static Future<void> updateBranding({
    String? logoUrl,
    String? coverImageUrl,
    String? displayName,
  }) async {
    final updateData = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (logoUrl != null) {
      updateData['barangayLogoUrl'] = logoUrl;
    }
    if (coverImageUrl != null) {
      updateData['barangayCoverImageUrl'] = coverImageUrl;
    }
    if (displayName != null) {
      updateData['barangayDisplayName'] = displayName;
    }

    await _firestore.collection(_collection).doc(_documentId).set(
      updateData,
      SetOptions(merge: true),
    );
  }

  /// Get the barangay display name
  static Future<String?> getBarangayDisplayName() async {
    final branding = await getBranding();
    return branding?['barangayDisplayName'] as String?;
  }

  /// Update only the barangay display name
  static Future<void> updateBarangayDisplayName(String displayName) async {
    await _firestore.collection(_collection).doc(_documentId).set(
      {
        'barangayDisplayName': displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Delete old image from storage if URL exists
  static Future<void> deleteOldImage(String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) return;
    try {
      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      // Ignore deletion errors (e.g., if file doesn't exist)
    }
  }
}

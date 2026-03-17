import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../widgets/app_sidebar.dart';
import '../services/barangay_category_service.dart';
import '../services/barangay_posting_service.dart';
import '../services/barangay_branding_service.dart';
import '../widgets/category_edit_dialog.dart';
import '../widgets/posting_edit_dialog.dart';
import '../utils/app_colors.dart';
import '../widgets/success_notification.dart';
import '../widgets/draft_saved_notification.dart';
import '../widgets/error_notification.dart';
import 'dashboard_screen.dart';
import 'announcements_screen.dart';
import 'approvals_screen.dart';
import 'user_management_screen.dart';

class BarangayInformationScreen extends StatefulWidget {
  const BarangayInformationScreen({super.key});

  @override
  State<BarangayInformationScreen> createState() =>
      _BarangayInformationScreenState();
}

class _BarangayInformationScreenState extends State<BarangayInformationScreen> {
  String? _currentUserRole;
  int _pendingApprovalsCount = 0;
  int _pendingUsersCount = 0;
  bool _isLoading = true;
  String? _loadError;
  List<Map<String, dynamic>> _categories = const [];

  // Selected category for inline postings view
  Map<String, dynamic>? _selectedCategory;

  // Branding state variables
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _displayNameController = TextEditingController();
  String? _currentLogoUrl;
  String? _currentCoverUrl;
  String? _currentDisplayName;
  File? _pendingLogoFile;
  File? _pendingCoverFile;
  bool _isUploadingBranding = false;
  bool _isSavingDisplayName = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      await Future.wait([
        _loadCurrentUserRole(),
        _loadPendingCounts(),
        _loadCategoriesOnce(),
        _loadBranding(),
      ]);
    } catch (e) {
      _loadError = 'Failed to load: $e';
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadCurrentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (mounted) {
        setState(() {
          _currentUserRole = userDoc.data()?['role'] as String?;
        });
      }
    }
  }

  Future<void> _loadPendingCounts() async {
    final firestore = FirebaseFirestore.instance;

    int pendingAnnouncements = 0;
    int pendingProducts = 0;
    int pendingUsers = 0;

    try {
      final results = await Future.wait([
        firestore
            .collection('announcements')
            .where('approvalStatus', isEqualTo: 'Pending')
            .count()
            .get(),
        firestore
            .collection('products')
            .where('status', isEqualTo: 'Pending')
            .count()
            .get(),
        firestore.collection('awaitingApproval').count().get(),
      ]);
      pendingAnnouncements = results[0].count ?? 0;
      pendingProducts = results[1].count ?? 0;
      pendingUsers = results[2].count ?? 0;
    } catch (_) {
      // Leave as 0 if counts fail (do not block screen).
    }

    if (!mounted) return;
    setState(() {
      _pendingApprovalsCount = pendingAnnouncements + pendingProducts;
      _pendingUsersCount = pendingUsers;
    });
  }

  Future<void> _loadCategoriesOnce() async {
    final categories = await BarangayCategoryService.getCategories();
    if (!mounted) return;
    setState(() {
      _categories = categories;
    });
  }

  // Branding methods
  Future<void> _loadBranding() async {
    final branding = await BarangayBrandingService.getBranding();
    if (!mounted) return;
    setState(() {
      _currentLogoUrl = branding?['barangayLogoUrl'] as String?;
      _currentCoverUrl = branding?['barangayCoverImageUrl'] as String?;
      _currentDisplayName = branding?['barangayDisplayName'] as String?;
      _displayNameController.text = _currentDisplayName ?? '';
    });
  }

  Future<void> _pickLogo() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );
    if (image != null) {
      setState(() {
        _pendingLogoFile = File(image.path);
      });
      await _uploadBranding(logoFile: _pendingLogoFile);
    }
  }

  Future<void> _pickCoverImage() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );
    if (image != null) {
      setState(() {
        _pendingCoverFile = File(image.path);
      });
      await _uploadBranding(coverFile: _pendingCoverFile);
    }
  }

  Future<void> _uploadBranding({File? logoFile, File? coverFile}) async {
    setState(() {
      _isUploadingBranding = true;
    });

    try {
      String? newLogoUrl;
      String? newCoverUrl;

      if (logoFile != null) {
        // Delete old logo if exists
        if (_currentLogoUrl != null) {
          await BarangayBrandingService.deleteOldImage(_currentLogoUrl);
        }
        newLogoUrl = await BarangayBrandingService.uploadLogo(logoFile);
      }

      if (coverFile != null) {
        // Delete old cover if exists
        if (_currentCoverUrl != null) {
          await BarangayBrandingService.deleteOldImage(_currentCoverUrl);
        }
        newCoverUrl = await BarangayBrandingService.uploadCoverImage(coverFile);
      }

      // Update Firestore with new URLs
      await BarangayBrandingService.updateBranding(
        logoUrl: newLogoUrl,
        coverImageUrl: newCoverUrl,
      );

      // Update local state
      setState(() {
        if (newLogoUrl != null) _currentLogoUrl = newLogoUrl;
        if (newCoverUrl != null) _currentCoverUrl = newCoverUrl;
        _pendingLogoFile = null;
        _pendingCoverFile = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: SuccessNotification(
              message: 'Branding updated successfully',
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ErrorNotification(
              message: 'Failed to update branding: $e',
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() {
        _isUploadingBranding = false;
      });
    }
  }

  Future<void> _removeLogo() async {
    if (_currentLogoUrl == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Logo'),
        content: const Text(
          'Are you sure you want to remove the barangay logo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.deleteRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await BarangayBrandingService.deleteOldImage(_currentLogoUrl);
        await BarangayBrandingService.updateBranding(logoUrl: '');
        setState(() {
          _currentLogoUrl = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: SuccessNotification(
                message: 'Logo removed successfully',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: ErrorNotification(message: 'Failed to remove logo: $e'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _removeCoverImage() async {
    if (_currentCoverUrl == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Cover Image'),
        content: const Text(
          'Are you sure you want to remove the barangay cover image?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.deleteRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await BarangayBrandingService.deleteOldImage(_currentCoverUrl);
        await BarangayBrandingService.updateBranding(coverImageUrl: '');
        setState(() {
          _currentCoverUrl = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: SuccessNotification(
                message: 'Cover image removed successfully',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: ErrorNotification(
                message: 'Failed to remove cover image: $e',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _saveDisplayName() async {
    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) return;

    setState(() {
      _isSavingDisplayName = true;
    });

    try {
      await BarangayBrandingService.updateBarangayDisplayName(displayName);
      setState(() {
        _currentDisplayName = displayName;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: SuccessNotification(
              message: 'Display name updated successfully',
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ErrorNotification(
              message: 'Failed to update display name: $e',
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() {
        _isSavingDisplayName = false;
      });
    }
  }

  void _navigateTo(String route) {
    if ((_currentUserRole ?? '').toLowerCase() != 'super_admin' &&
        (route == '/approvals' || route == '/user-management')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: DraftSavedNotification(
            message: 'Only Super Admin can access this.',
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (route == '/dashboard') {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const DashboardScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        ),
      );
    } else if (route == '/announcements') {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const AnnouncementsScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        ),
      );
    } else if (route == '/approvals') {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const ApprovalsScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        ),
      );
    } else if (route == '/user-management') {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const UserManagementScreen(initialTabIndex: 2),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        ),
      );
    }
  }

  Future<void> _createCategory() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const CategoryEditDialog(),
    );

    if (result != null) {
      try {
        await BarangayCategoryService.createCategory(
          title: result['title'] as String,
          description: result['description'] as String,
          iconCodePoint: result['iconCodePoint'] as int,
          iconFontFamily: result['iconFontFamily'] as String,
          iconPackage: result['iconPackage'] as String? ?? '',
        );
        await _loadCategoriesOnce();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const SuccessNotification(
                message: 'Category created successfully',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: ErrorNotification(
                message: 'Failed to create category: $e',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _editCategory(Map<String, dynamic> category) async {
    IconData? iconData;
    try {
      final codePoint = int.tryParse(
        category['iconCodePoint'] as String? ?? '',
      );
      if (codePoint != null) {
        var fontFamily = category['iconFontFamily'] as String?;
        // Material Symbols icons need correct font family
        if (fontFamily == 'MaterialIcons' &&
            (category['iconPackage'] as String? ?? '').isEmpty) {
          fontFamily = 'Material Symbols Outlined';
        }
        iconData = IconData(
          codePoint,
          fontFamily: fontFamily?.isNotEmpty == true
              ? fontFamily
              : 'MaterialIcons',
          fontPackage: category['iconPackage'] as String?,
        );
      }
    } catch (e) {
      // Use default icon if parsing fails
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CategoryEditDialog(
        categoryId: category['id'] as String,
        initialTitle: category['title'] as String?,
        initialDescription: category['description'] as String?,
        initialIcon: iconData,
      ),
    );

    if (result != null) {
      try {
        await BarangayCategoryService.updateCategory(
          categoryId: category['id'] as String,
          title: result['title'] as String,
          description: result['description'] as String,
          iconCodePoint: result['iconCodePoint'] as int,
          iconFontFamily: result['iconFontFamily'] as String,
          iconPackage: result['iconPackage'] as String? ?? '',
        );
        await _loadCategoriesOnce();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const SuccessNotification(
                message: 'Category updated successfully',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: ErrorNotification(
                message: 'Failed to update category: $e',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteCategory(String categoryId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: const Text(
          'Are you sure you want to delete this category? All postings in this category will also be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.deleteRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await BarangayCategoryService.deleteCategory(categoryId);
        await _loadCategoriesOnce();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const SuccessNotification(
                message: 'Category deleted successfully',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: ErrorNotification(
                message: 'Failed to delete category: $e',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  IconData _getIconFromCategory(Map<String, dynamic> category) {
    try {
      // Handle both integer and string codePoint formats for backward compatibility
      final dynamic rawCodePoint = category['iconCodePoint'];
      int? codePoint;
      if (rawCodePoint is int) {
        codePoint = rawCodePoint;
      } else if (rawCodePoint is String) {
        codePoint = int.tryParse(rawCodePoint);
      }
      if (codePoint != null) {
        // Force MaterialIcons font family - ignore stored fontFamily for safety
        return IconData(codePoint, fontFamily: 'MaterialIcons');
      }
    } catch (e) {
      // Fall through to default
    }
    return Icons.info_outline;
  }

  void _selectCategory(Map<String, dynamic> category) {
    setState(() {
      _selectedCategory = category;
    });
  }

  void _deselectCategory() {
    setState(() {
      _selectedCategory = null;
    });
  }

  Future<void> _createPosting() async {
    if (_selectedCategory == null) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          PostingEditDialog(categoryId: _selectedCategory!['id'] as String),
    );

    if (result != null) {
      try {
        List<String> imageUrls =
            (result['existingImageUrls'] as List<dynamic>?)?.cast<String>() ??
            [];
        String? pdfUrl = result['existingPdfUrl'] as String?;
        String? pdfName = result['pdfName'] as String?;

        // Upload new images
        final newImageFiles = result['imageFiles'] as List<dynamic>?;
        if (newImageFiles != null && newImageFiles.isNotEmpty) {
          final postingId = DateTime.now().millisecondsSinceEpoch.toString();
          final newUrls = await BarangayPostingService.uploadMultipleImages(
            newImageFiles.cast<File>(),
            _selectedCategory!['id'] as String,
            postingId,
          );
          imageUrls.addAll(newUrls);
        }

        if (result['pdfFile'] != null) {
          final postingId = DateTime.now().millisecondsSinceEpoch.toString();
          pdfUrl = await BarangayPostingService.uploadPdf(
            result['pdfFile'] as File,
            _selectedCategory!['id'] as String,
            postingId,
          );
          pdfName = result['pdfName'] as String?;
        }

        await BarangayPostingService.createPosting(
          categoryId: _selectedCategory!['id'] as String,
          title: result['title'] as String,
          description: result['description'] as String,
          imageUrls: imageUrls.isNotEmpty ? imageUrls : null,
          pdfUrl: pdfUrl,
          pdfName: pdfName,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const SuccessNotification(
                message: 'Post created successfully',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: ErrorNotification(message: 'Failed to create post: $e'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _editPosting(Map<String, dynamic> posting) async {
    if (_selectedCategory == null) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PostingEditDialog(
        categoryId: _selectedCategory!['id'] as String,
        initialPosting: posting,
      ),
    );

    if (result != null) {
      try {
        List<String> imageUrls =
            (result['existingImageUrls'] as List<dynamic>?)?.cast<String>() ??
            [];
        String? pdfUrl = result['existingPdfUrl'] as String?;
        String? pdfName = result['pdfName'] as String?;

        // Upload new images
        final newImageFiles = result['imageFiles'] as List<dynamic>?;
        if (newImageFiles != null && newImageFiles.isNotEmpty) {
          final newUrls = await BarangayPostingService.uploadMultipleImages(
            newImageFiles.cast<File>(),
            _selectedCategory!['id'] as String,
            posting['id'] as String,
          );
          imageUrls.addAll(newUrls);
        }

        if (result['pdfFile'] != null) {
          pdfUrl = await BarangayPostingService.uploadPdf(
            result['pdfFile'] as File,
            _selectedCategory!['id'] as String,
            posting['id'] as String,
          );
          pdfName = result['pdfName'] as String?;
        }

        await BarangayPostingService.updatePosting(
          postingId: posting['id'] as String,
          title: result['title'] as String,
          description: result['description'] as String,
          imageUrls: imageUrls.isNotEmpty ? imageUrls : null,
          pdfUrl: pdfUrl,
          pdfName: pdfName,
          removePdf:
              pdfUrl == null &&
              result['existingPdfUrl'] == null &&
              result['pdfFile'] == null,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const SuccessNotification(
                message: 'Post updated successfully',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: ErrorNotification(message: 'Failed to update post: $e'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _deletePosting(String postingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.deleteRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await BarangayPostingService.deletePosting(postingId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const SuccessNotification(
                message: 'Post deleted successfully',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: ErrorNotification(message: 'Failed to delete post: $e'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'No date';
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is DateTime) {
      date = timestamp;
    } else {
      return 'Invalid date';
    }
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Row(
        children: [
          AppSidebar(
            currentRoute: '/barangay-information',
            currentUserRole: _currentUserRole,
            pendingApprovalsCount: _pendingApprovalsCount,
            pendingUsersCount: _pendingUsersCount,
            onNavigate: _navigateTo,
          ),
          Expanded(
            child: Container(
              color: AppColors.white,
              child: Column(
                children: [
                  Container(
                    color: AppColors.white,
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            if (_selectedCategory != null)
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: _deselectCategory,
                              ),
                            Text(
                              _selectedCategory != null
                                  ? _selectedCategory!['title'] as String? ??
                                        'Category'
                                  : 'Barangay Informations',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkGrey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.dashboardInnerBg,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _loadError != null
                          ? Center(
                              child: Text(
                                _loadError!,
                                style: const TextStyle(
                                  color: AppColors.deleteRed,
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : _selectedCategory != null
                          ? _buildPostingsView()
                          : _buildCategoriesView(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final crossAxisCount = w >= 1200 ? 4 : (w >= 900 ? 3 : 2);

        return CustomScrollView(
          slivers: [
            // Branding Section
            SliverToBoxAdapter(child: _buildBrandingSection()),
            // Public Informations Label
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                child: Text(
                  'Public Informations',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkGrey,
                  ),
                ),
              ),
            ),
            // Categories Grid
            SliverPadding(
              padding: const EdgeInsets.all(32),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: 1.1,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index == _categories.length) {
                    return _buildAddCategoryCard();
                  }
                  final category = _categories[index];
                  return _buildCategoryCard(category);
                }, childCount: _categories.length + 1),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBrandingSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.palette_outlined,
                color: AppColors.primaryGreen,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Barangay Branding',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkGrey,
                ),
              ),
              const Spacer(),
              if (_isUploadingBranding)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryGreen,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Manage the logo and cover image shown on the mobile app.',
            style: TextStyle(fontSize: 14, color: AppColors.mediumGrey),
          ),
          const SizedBox(height: 20),
          // Display Name Row
          _buildDisplayNameRow(),
          const Divider(height: 32),
          // Logo Row
          _buildLogoUploadRow(),
          const Divider(height: 32),
          // Cover Row
          _buildCoverUploadRow(),
        ],
      ),
    );
  }

  Widget _buildDisplayNameRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and Description
        const Text(
          'Barangay Display Name',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.darkGrey,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Displayed in the mobile app header',
          style: TextStyle(fontSize: 13, color: AppColors.mediumGrey),
        ),
        const SizedBox(height: 12),
        // Text Field
        TextField(
          controller: _displayNameController,
          minLines: 1,
          maxLines: 3,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: 'Barangay Cagbaoto\nBayabas, Surigao del Sur',
            hintStyle: TextStyle(
              fontSize: 14,
              color: AppColors.lightGrey,
              height: 1.4,
            ),
            filled: true,
            fillColor: AppColors.inputBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: AppColors.primaryGreen,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.darkGrey,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        // Save Button
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isSavingDisplayName ? null : _saveDisplayName,
              icon: _isSavingDisplayName
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 16),
              label: const Text('Save Display Name'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLogoUploadRow() {
    final hasLogo = _currentLogoUrl != null && _currentLogoUrl!.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Circular Logo Preview
        _buildCircularLogoPreview(hasLogo),
        const SizedBox(width: 20),
        // Info and Actions
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Barangay Logo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkGrey,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Used as the circular logo on the mobile app',
                style: TextStyle(fontSize: 13, color: AppColors.mediumGrey),
              ),
              const SizedBox(height: 4),
              Text(
                'Recommended: square PNG, 512×512',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.lightGrey,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 12),
              // Action Buttons
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _isUploadingBranding ? null : _pickLogo,
                    icon: Icon(
                      hasLogo ? Icons.refresh : Icons.upload_outlined,
                      size: 16,
                    ),
                    label: Text(hasLogo ? 'Replace Logo' : 'Upload Logo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (hasLogo) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _isUploadingBranding ? null : _removeLogo,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Remove'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.deleteRed,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(
                          color: AppColors.deleteRed.withOpacity(0.5),
                        ),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCircularLogoPreview(bool hasLogo) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: hasLogo ? AppColors.primaryGreen : Colors.grey.shade300,
          width: hasLogo ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: hasLogo
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Image.network(
                _currentLogoUrl!,
                fit: BoxFit.contain,
                alignment: Alignment.center,
              ),
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.account_balance,
                    size: 36,
                    color: AppColors.lightGrey,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'No logo',
                    style: TextStyle(fontSize: 11, color: AppColors.lightGrey),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCoverUploadRow() {
    final hasCover = _currentCoverUrl != null && _currentCoverUrl!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and Description
        const Text(
          'Cover Image',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.darkGrey,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Displayed at the top of the mobile Barangay Information screen',
          style: TextStyle(fontSize: 13, color: AppColors.mediumGrey),
        ),
        const SizedBox(height: 4),
        Text(
          'Recommended: 1200×600 JPG or PNG',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.lightGrey,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 12),
        // Cover Preview
        _buildCoverPreview(hasCover),
        const SizedBox(height: 12),
        // Action Buttons
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isUploadingBranding ? null : _pickCoverImage,
              icon: Icon(
                hasCover ? Icons.refresh : Icons.upload_outlined,
                size: 16,
              ),
              label: Text(hasCover ? 'Replace Cover' : 'Upload Cover'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
            if (hasCover) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _isUploadingBranding ? null : _removeCoverImage,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Remove'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.deleteRed,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  side: BorderSide(color: AppColors.deleteRed.withOpacity(0.5)),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildCoverPreview(bool hasCover) {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasCover ? AppColors.primaryGreen : Colors.grey.shade300,
          width: hasCover ? 2 : 1,
        ),
        image: hasCover
            ? DecorationImage(
                image: NetworkImage(_currentCoverUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: !hasCover
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_city_outlined,
                    size: 48,
                    color: AppColors.lightGrey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No cover image uploaded',
                    style: TextStyle(fontSize: 13, color: AppColors.lightGrey),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildPostingsView() {
    return Column(
      children: [
        // Header with back button and create post button
        Container(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedCategory!['description'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.mediumGrey,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _createPosting,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Post'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
        // Postings list
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: BarangayPostingService.getPostingsStream(
                _selectedCategory!['id'] as String,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final postings = snapshot.data ?? [];

                if (postings.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.inputBackground,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.campaign_outlined,
                            size: 64,
                            color: AppColors.lightGrey,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'No posts yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: AppColors.darkGrey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start sharing updates with residents',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.mediumGrey,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _createPosting,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Create First Post'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth >= 1200
                        ? 3
                        : (constraints.maxWidth >= 800 ? 2 : 1);
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: postings.length,
                      itemBuilder: (context, index) {
                        final posting = postings[index];
                        return _buildPostingCard(posting);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPostingCard(Map<String, dynamic> posting) {
    final imageUrls =
        (posting['imageUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    // Fallback to old single imageUrl for backward compatibility
    final singleImageUrl = posting['imageUrl'] as String?;
    if (singleImageUrl != null && imageUrls.isEmpty) {
      imageUrls.add(singleImageUrl);
    }
    final hasImages = imageUrls.isNotEmpty;
    final hasPdf = posting['pdfUrl'] != null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image section
          if (hasImages)
            _buildMultiImageSection(imageUrls)
          else
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.inputBackground,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.article_outlined,
                  size: 40,
                  color: AppColors.lightGrey,
                ),
              ),
            ),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    posting['title'] as String? ?? 'Untitled',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Date
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 12,
                        color: AppColors.mediumGrey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(posting['date']),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.mediumGrey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Description preview
                  Expanded(
                    child: Text(
                      posting['description'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color: const Color(0xFF6B7280),
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // PDF indicator
                  if (hasPdf) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.deleteRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.picture_as_pdf,
                            size: 14,
                            color: AppColors.deleteRed,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              posting['pdfName'] as String? ?? 'PDF',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.deleteRed,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Action buttons
                  Row(
                    children: [
                      _buildActionButton(
                        icon: Icons.edit_outlined,
                        label: 'Edit',
                        onTap: () => _editPosting(posting),
                      ),
                      const SizedBox(width: 8),
                      _buildActionButton(
                        icon: Icons.delete_outline,
                        label: 'Delete',
                        onTap: () => _deletePosting(posting['id'] as String),
                        isDestructive: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiImageSection(List<String> imageUrls) {
    if (imageUrls.length == 1) {
      // Single image - full width
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Image.network(
          imageUrls[0],
          height: 140,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: 140,
            color: AppColors.inputBackground,
            child: const Center(
              child: Icon(
                Icons.image_not_supported,
                color: AppColors.lightGrey,
              ),
            ),
          ),
        ),
      );
    } else {
      // Multiple images - horizontal scroll
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: AppColors.inputBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: imageUrls.length,
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrls[index],
                    width: 140,
                    height: 124,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 140,
                      height: 124,
                      color: Colors.grey.shade300,
                      child: const Icon(
                        Icons.image_not_supported,
                        color: AppColors.lightGrey,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isDestructive
                ? AppColors.deleteRed.withOpacity(0.08)
                : AppColors.primaryGreen.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isDestructive
                    ? AppColors.deleteRed
                    : AppColors.primaryGreen,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDestructive
                      ? AppColors.deleteRed
                      : AppColors.primaryGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddCategoryCard() {
    return GestureDetector(
      onTap: _createCategory,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1,
            style: BorderStyle.solid,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 40, color: Colors.grey.shade600),
              const SizedBox(height: 12),
              Text(
                'Create Category',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> category) {
    final icon = _getIconFromCategory(category);
    return Card(
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withOpacity(0.15), width: 1),
      ),
      color: Colors.white,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectCategory(category),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 60, color: AppColors.primaryGreen),
                  const SizedBox(height: 16),
                  Text(
                    category['title'] as String? ?? 'Untitled',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Text(
                      category['description'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.mediumGrey,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      Icons.more_vert,
                      size: 24,
                      color: AppColors.mediumGrey,
                    ),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editCategory(category);
                      } else if (value == 'delete') {
                        _deleteCategory(category['id'] as String);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete',
                          style: TextStyle(color: AppColors.deleteRed),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

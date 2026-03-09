import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/barangay_posting_service.dart';
import '../services/barangay_category_service.dart';
import '../widgets/posting_edit_dialog.dart';
import '../utils/app_colors.dart';
import '../widgets/success_notification.dart';
import '../widgets/error_notification.dart';
import '../widgets/custom_button.dart';
import '../widgets/outline_button.dart';

class CategoryDetailScreen extends StatefulWidget {
  final Map<String, dynamic> category;

  const CategoryDetailScreen({
    super.key,
    required this.category,
  });

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  IconData _getIconFromCategory() {
    try {
      final dynamic rawCodePoint = widget.category['iconCodePoint'];
      int? codePoint;
      if (rawCodePoint is int) {
        codePoint = rawCodePoint;
      } else if (rawCodePoint is String) {
        codePoint = int.tryParse(rawCodePoint);
      }
      if (codePoint != null) {
        return IconData(
          codePoint,
          fontFamily: 'MaterialIcons',
        );
      }
    } catch (e) {
      // Fall through to default
    }
    return Icons.info_outline;
  }

  Future<void> _createPosting() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PostingEditDialog(
        categoryId: widget.category['id'] as String,
      ),
    );

    if (result != null) {
      try {
        String? imageUrl = result['existingImageUrl'] as String?;
        String? pdfUrl = result['existingPdfUrl'] as String?;
        String? pdfName = result['pdfName'] as String?;

        // Upload new image if selected
        if (result['imageFile'] != null) {
          final postingId = DateTime.now().millisecondsSinceEpoch.toString();
          imageUrl = await BarangayPostingService.uploadImage(
            result['imageFile'] as File,
            widget.category['id'] as String,
            postingId,
          );
        }

        // Upload new PDF if selected
        if (result['pdfFile'] != null) {
          final postingId = DateTime.now().millisecondsSinceEpoch.toString();
          pdfUrl = await BarangayPostingService.uploadPdf(
            result['pdfFile'] as File,
            widget.category['id'] as String,
            postingId,
          );
          pdfName = result['pdfName'] as String?;
        }

        await BarangayPostingService.createPosting(
          categoryId: widget.category['id'] as String,
          title: result['title'] as String,
          description: result['description'] as String,
          imageUrl: imageUrl,
          pdfUrl: pdfUrl,
          pdfName: pdfName,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const SuccessNotification(
                message: 'Posting created successfully',
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
                message: 'Failed to create posting: $e',
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

  Future<void> _editPosting(Map<String, dynamic> posting) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PostingEditDialog(
        categoryId: widget.category['id'] as String,
        initialPosting: posting,
      ),
    );

    if (result != null) {
      try {
        String? imageUrl = result['existingImageUrl'] as String?;
        String? pdfUrl = result['existingPdfUrl'] as String?;
        String? pdfName = result['pdfName'] as String?;

        // Upload new image if selected
        if (result['imageFile'] != null) {
          imageUrl = await BarangayPostingService.uploadImage(
            result['imageFile'] as File,
            widget.category['id'] as String,
            posting['id'] as String,
          );
        }

        // Upload new PDF if selected
        if (result['pdfFile'] != null) {
          pdfUrl = await BarangayPostingService.uploadPdf(
            result['pdfFile'] as File,
            widget.category['id'] as String,
            posting['id'] as String,
          );
          pdfName = result['pdfName'] as String?;
        }

        await BarangayPostingService.updatePosting(
          postingId: posting['id'] as String,
          title: result['title'] as String,
          description: result['description'] as String,
          imageUrl: imageUrl,
          pdfUrl: pdfUrl,
          pdfName: pdfName,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const SuccessNotification(
                message: 'Posting updated successfully',
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
                message: 'Failed to update posting: $e',
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

  Future<void> _deletePosting(String postingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Posting'),
        content: const Text(
          'Are you sure you want to delete this posting?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.deleteRed,
            ),
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
                message: 'Posting deleted successfully',
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
                message: 'Failed to delete posting: $e',
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Column(
        children: [
          // Header
          Container(
            color: AppColors.white,
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
                Icon(
                  _getIconFromCategory(),
                  size: 32,
                  color: AppColors.primaryGreen,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.category['title'] as String? ?? 'Category',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkGrey,
                        ),
                      ),
                      Text(
                        widget.category['description'] as String? ?? '',
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
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
            child: Container(
              color: AppColors.dashboardInnerBg,
              padding: const EdgeInsets.all(24),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: BarangayPostingService.getPostingsStream(
                  widget.category['id'] as String,
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
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
      ),
    );
  }

  Widget _buildPostingCard(Map<String, dynamic> posting) {
    final hasImage = posting['imageUrl'] != null;
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
          // Image thumbnail
          if (hasImage)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.network(
                posting['imageUrl'] as String,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 140,
                  color: AppColors.inputBackground,
                  child: const Center(
                    child: Icon(Icons.image_not_supported, color: AppColors.lightGrey),
                  ),
                ),
              ),
            )
          else
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.inputBackground,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                color: isDestructive ? AppColors.deleteRed : AppColors.primaryGreen,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDestructive ? AppColors.deleteRed : AppColors.primaryGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

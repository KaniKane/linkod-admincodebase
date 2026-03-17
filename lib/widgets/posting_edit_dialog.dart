import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/app_colors.dart';

/// Represents an image item that can be either a URL or a File
class _ImageItem {
  final String? url;
  final File? file;
  final String id;

  _ImageItem({this.url, this.file, required this.id});

  bool get isFile => file != null;
  bool get isUrl => url != null;
}

/// Dialog for creating or editing a barangay information posting
class PostingEditDialog extends StatefulWidget {
  final String categoryId;
  final Map<String, dynamic>? initialPosting;

  const PostingEditDialog({
    super.key,
    required this.categoryId,
    this.initialPosting,
  });

  @override
  State<PostingEditDialog> createState() => _PostingEditDialogState();
}

class _PostingEditDialogState extends State<PostingEditDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  final List<_ImageItem> _imageItems = [];
  File? _selectedPdf;
  String? _existingPdfUrl;
  String? _existingPdfName;
  bool _isLoading = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.initialPosting?['title'] as String? ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.initialPosting?['description'] as String? ?? '',
    );
    // Handle both old single imageUrl and new multiple imageUrls
    final imageUrls = widget.initialPosting?['imageUrls'] as List<dynamic>?;
    if (imageUrls != null) {
      for (final url in imageUrls) {
        _imageItems.add(
          _ImageItem(url: url as String, id: 'url_${_imageItems.length}'),
        );
      }
    }
    // Fallback to old single imageUrl for backward compatibility
    final singleImageUrl = widget.initialPosting?['imageUrl'] as String?;
    if (singleImageUrl != null && _imageItems.isEmpty) {
      _imageItems.add(
        _ImageItem(url: singleImageUrl, id: 'url_${_imageItems.length}'),
      );
    }
    _existingPdfUrl = widget.initialPosting?['pdfUrl'] as String?;
    _existingPdfName = widget.initialPosting?['pdfName'] as String?;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final List<XFile> images = await _imagePicker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        for (final image in images) {
          _imageItems.add(
            _ImageItem(
              file: File(image.path),
              id: 'file_${_imageItems.length}_${DateTime.now().millisecondsSinceEpoch}',
            ),
          );
        }
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageItems.removeAt(index);
    });
  }

  void _reorderImages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _imageItems.removeAt(oldIndex);
      _imageItems.insert(newIndex, item);
    });
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedPdf = File(result.files.single.path!);
        _existingPdfUrl = null;
        _existingPdfName = result.files.single.name;
      });
    }
  }

  void _removePdf() {
    setState(() {
      _selectedPdf = null;
      _existingPdfUrl = null;
      _existingPdfName = null;
    });
  }

  Widget _buildImagesSection() {
    final totalImages = _imageItems.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reorderable image grid with add button at the end
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            // Image items with drag handles
            ..._imageItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return _buildDraggableImageThumbnail(
                item: item,
                index: index,
                onRemove: () => _removeImage(index),
              );
            }),
            // Add button at the end
            _buildAddImagesButton(),
          ],
        ),
        if (totalImages > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Long press and drag to reorder images',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.mediumGrey,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDraggableImageThumbnail({
    required _ImageItem item,
    required int index,
    required VoidCallback onRemove,
  }) {
    return LongPressDraggable<int>(
      data: index,
      delay: const Duration(milliseconds: 200),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 100,
            height: 100,
            color: AppColors.inputBackground,
            child: item.isFile
                ? Image.file(item.file!, fit: BoxFit.cover)
                : Image.network(item.url!, fit: BoxFit.cover),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildImageThumbnailContent(item: item, onRemove: onRemove),
      ),
      child: DragTarget<int>(
        onAcceptWithDetails: (details) {
          final oldIndex = details.data;
          if (oldIndex != index) {
            _reorderImages(oldIndex, index);
          }
        },
        builder: (context, candidateData, rejectedData) {
          return _buildImageThumbnailContent(item: item, onRemove: onRemove);
        },
      ),
    );
  }

  Widget _buildImageThumbnailContent({
    required _ImageItem item,
    required VoidCallback onRemove,
  }) {
    return Stack(
      children: [
        InkWell(
          onTap: () => _showFullScreenImage(item: item),
          borderRadius: BorderRadius.circular(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 100,
              height: 100,
              color: AppColors.inputBackground,
              child: item.isFile
                  ? Image.file(item.file!, fit: BoxFit.cover)
                  : Image.network(
                      item.url!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Center(child: Icon(Icons.image_not_supported)),
                    ),
            ),
          ),
        ),
        // Drag handle indicator
        Positioned(
          top: 4,
          left: 4,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.drag_handle, size: 12, color: Colors.white),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddImagesButton() {
    return InkWell(
      onTap: _pickImages,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 28,
              color: AppColors.mediumGrey,
            ),
            const SizedBox(height: 6),
            Text(
              'Add',
              style: TextStyle(fontSize: 12, color: AppColors.mediumGrey),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreenImage({
    _ImageItem? item,
    String? imageUrl,
    File? imageFile,
  }) {
    // Support both old and new calling patterns
    final File? file = item?.file ?? imageFile;
    final String? url = item?.url ?? imageUrl;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black.withOpacity(0.9),
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Full screen image
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: file != null
                    ? Image.file(file, fit: BoxFit.contain)
                    : Image.network(
                        url!,
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: progress.expectedTotalBytes != null
                                  ? progress.cumulativeBytesLoaded /
                                        progress.expectedTotalBytes!
                                  : null,
                              color: Colors.white,
                            ),
                          );
                        },
                      ),
              ),
            ),
            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.initialPosting == null
                              ? 'Create New Item'
                              : 'Edit Item',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Share updates with residents',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.mediumGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close,
                      size: 22,
                      color: Color(0xFF6B7280),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    _buildLabel('Title'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleController,
                      decoration: _buildInputDecoration(
                        hintText: 'Enter post title...',
                      ),
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 20),
                    // Description
                    _buildLabel('Description'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descriptionController,
                      maxLines: 8,
                      minLines: 4,
                      decoration: _buildInputDecoration(
                        hintText: 'Enter post description...',
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    // Image upload
                    _buildLabel('Upload Images'),
                    const SizedBox(height: 8),
                    _buildImagesSection(),
                    const SizedBox(height: 20),
                    // PDF upload
                    _buildLabel('Attach PDF (optional)'),
                    const SizedBox(height: 8),
                    if (_existingPdfUrl != null || _selectedPdf != null)
                      _buildPdfPreview()
                    else
                      _buildPdfUploadZone(),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _handleSave,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(
                      widget.initialPosting == null
                          ? 'Publish Post'
                          : 'Update Post',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
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

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Color(0xFF374151),
      ),
    );
  }

  InputDecoration _buildInputDecoration({required String hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(fontSize: 14, color: AppColors.lightGrey),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.primaryGreen, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildPdfUploadZone() {
    return InkWell(
      onTap: _pickPdf,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.attach_file, size: 20, color: AppColors.mediumGrey),
            const SizedBox(width: 12),
            Text(
              'Choose File',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.mediumGrey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.deleteRed.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.deleteRed.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.picture_as_pdf,
            color: AppColors.deleteRed,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _existingPdfName ?? 'PDF Document',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF374151),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'PDF Attached',
                  style: TextStyle(fontSize: 12, color: AppColors.deleteRed),
                ),
              ],
            ),
          ),
          Row(
            children: [
              InkWell(
                onTap: _pickPdf,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: AppColors.mediumGrey,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: _removePdf,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.deleteRed,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleSave() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a title'),
          backgroundColor: AppColors.deleteRed,
        ),
      );
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a description'),
          backgroundColor: AppColors.deleteRed,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    Navigator.of(context).pop({
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'imageFiles': _imageItems
          .where((item) => item.isFile)
          .map((item) => item.file)
          .toList(),
      'existingImageUrls': _imageItems
          .where((item) => item.isUrl)
          .map((item) => item.url)
          .toList(),
      'pdfFile': _selectedPdf,
      'pdfName': _existingPdfName,
      'existingPdfUrl': _existingPdfUrl,
    });
  }
}

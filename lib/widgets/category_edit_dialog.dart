import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/custom_button.dart';
import '../widgets/outline_button.dart';
import '../widgets/dialog_container.dart';

/// Dialog for creating or editing a barangay information category
class CategoryEditDialog extends StatefulWidget {
  final String? categoryId;
  final String? initialTitle;
  final String? initialDescription;
  final IconData? initialIcon;

  const CategoryEditDialog({
    super.key,
    this.categoryId,
    this.initialTitle,
    this.initialDescription,
    this.initialIcon,
  });

  @override
  State<CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<CategoryEditDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  IconData _selectedIcon = Icons.info;
  bool _isLoading = false;

  // Icon options - 40 icons in visual grid
  final List<_IconOption> _iconOptions = const [
    _IconOption('Information', Icons.info),
    _IconOption('History', Icons.menu_book),
    _IconOption('People', Icons.people),
    _IconOption('Health', Icons.local_hospital),
    _IconOption('Phone', Icons.local_phone),
    _IconOption('Document', Icons.description),
    _IconOption('Map', Icons.map),
    _IconOption('Calendar', Icons.calendar_today),
    _IconOption('Location', Icons.location_on),
    _IconOption('Email', Icons.email),
    _IconOption('Home', Icons.home),
    _IconOption('School', Icons.school),
    _IconOption('Work', Icons.work),
    _IconOption('Shopping', Icons.shopping_cart),
    _IconOption('Food', Icons.restaurant),
    _IconOption('Car', Icons.directions_car),
    _IconOption('Build', Icons.build),
    _IconOption('Security', Icons.security),
    _IconOption('Emergency', Icons.emergency),
    _IconOption('Warning', Icons.warning),
    _IconOption('Check', Icons.check_circle),
    _IconOption('Help', Icons.help),
    _IconOption('Event', Icons.event),
    _IconOption('Notifications', Icons.notifications),
    _IconOption('Star', Icons.star),
    _IconOption('Favorite', Icons.favorite),
    _IconOption('Heart', Icons.favorite_border),
    _IconOption('Settings', Icons.settings),
    _IconOption('Search', Icons.search),
    _IconOption('Photo', Icons.photo),
    _IconOption('Camera', Icons.camera_alt),
    _IconOption('Music', Icons.music_note),
    _IconOption('Video', Icons.videocam),
    _IconOption('Chat', Icons.chat),
    _IconOption('Call', Icons.call),
    _IconOption('Message', Icons.message),
    _IconOption('Time', Icons.access_time),
    _IconOption('Money', Icons.attach_money),
    _IconOption('Gift', Icons.card_giftcard),
    _IconOption('Flag', Icons.flag),
  ];

  _IconOption get _selectedOption {
    return _iconOptions.firstWhere(
      (o) => o.icon == _selectedIcon,
      orElse: () => _iconOptions.first,
    );
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _descriptionController = TextEditingController(text: widget.initialDescription ?? '');
    _selectedIcon = widget.initialIcon ?? Icons.info_outline;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DialogContainer(
      title: widget.categoryId == null ? 'Create Category' : 'Edit Category',
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlineButton(
            text: 'Cancel',
            onPressed: _isLoading
                ? null
                : () => Navigator.of(context).pop(),
            isFullWidth: false,
          ),
          const SizedBox(width: 12),
          CustomButton(
            text: widget.categoryId == null ? 'Create' : 'Update',
            onPressed: _isLoading ? null : _handleSave,
            isLoading: _isLoading,
            isFullWidth: false,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            CustomTextField(
              label: 'Category Title',
              hintText: 'Enter category title',
              controller: _titleController,
            ),
            const SizedBox(height: 20),
            CustomTextField(
              label: 'Description',
              hintText: 'Enter category description',
              controller: _descriptionController,
            ),
            const SizedBox(height: 20),
            const Text(
              'Select Icon',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.inputBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(12),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _iconOptions.length,
                itemBuilder: (context, index) {
                  final option = _iconOptions[index];
                  final isSelected = _selectedIcon == option.icon;
                  return Tooltip(
                    message: option.label,
                    child: InkWell(
                      onTap: _isLoading
                          ? null
                          : () => setState(() => _selectedIcon = option.icon),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primaryGreen.withOpacity(0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primaryGreen
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          option.icon,
                          color: isSelected
                              ? AppColors.primaryGreen
                              : AppColors.darkGrey,
                          size: 28,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleSave() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a category title'),
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

    // Get icon metadata - save codePoint as integer for compatibility
    final iconCodePoint = _selectedIcon.codePoint; // Save as int, not string
    final iconFontFamily = 'MaterialIcons';
    final iconPackage = _selectedIcon.fontPackage;

    // Return the result to the caller
    Navigator.of(context).pop({
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'iconCodePoint': iconCodePoint,
      'iconFontFamily': iconFontFamily,
      'iconPackage': iconPackage,
      'iconData': _selectedIcon,
    });
  }
}

class _IconOption {
  final String label;
  final IconData icon;
  const _IconOption(this.label, this.icon);
}

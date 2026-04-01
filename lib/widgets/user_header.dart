import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/app_colors.dart';
import '../screens/login_screen.dart';
import '../widgets/full_screen_image_viewer.dart';

class UserHeader extends StatefulWidget {
  const UserHeader({super.key, this.compact = false});

  final bool compact;

  @override
  State<UserHeader> createState() => _UserHeaderState();
}

class _UserHeaderState extends State<UserHeader> {
  static String? _cachedProfileImageUrl;
  static String? _cachedFullName;
  static String? _cachedUserPosition;
  static DateTime? _lastProfileFetchAt;
  static const Duration _cacheTtl = Duration(minutes: 10);

  bool _isHovered = false;
  String? _profileImageUrl;
  String? _fullName;
  String? _userPosition;
  bool _isLoading = true;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _hydrateFromCache();
    _loadAdminProfile();
  }

  void _hydrateFromCache() {
    final hasUsableCache =
        _lastProfileFetchAt != null &&
        DateTime.now().difference(_lastProfileFetchAt!) <= _cacheTtl;
    if (!hasUsableCache) {
      return;
    }

    _profileImageUrl = _cachedProfileImageUrl;
    _fullName = _cachedFullName;
    _userPosition = _cachedUserPosition;
    _isLoading = false;
  }

  void _precacheProfileImage(String url) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(precacheImage(NetworkImage(url), context));
    });
  }

  Future<void> _loadAdminProfile() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data();
        final nextFullName = data?['fullName'] as String?;
        final nextProfileImageUrl = data?['profileImageUrl'] as String?;
        final nextUserPosition = data?['position'] as String?;

        _cachedFullName = nextFullName;
        _cachedProfileImageUrl = nextProfileImageUrl;
        _cachedUserPosition = nextUserPosition;
        _lastProfileFetchAt = DateTime.now();

        if (nextProfileImageUrl != null && nextProfileImageUrl.isNotEmpty) {
          _precacheProfileImage(nextProfileImageUrl);
        }

        setState(() {
          _fullName = nextFullName;
          _profileImageUrl = nextProfileImageUrl;
          _userPosition = nextUserPosition;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading admin profile: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Logout signOut failed: $e');
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showProfileMenu() {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 8,
        offset.dx + size.width,
        offset.dy + size.height + 8,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem(
          value: 'profile',
          child: Row(
            children: [
              Icon(Icons.account_circle, color: AppColors.darkGrey, size: 20),
              const SizedBox(width: 12),
              const Text('Change Profile Picture'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'password',
          child: Row(
            children: [
              Icon(Icons.lock, color: AppColors.darkGrey, size: 20),
              const SizedBox(width: 12),
              const Text('Change Password'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, color: AppColors.deleteRed, size: 20),
              const SizedBox(width: 12),
              Text('Logout', style: TextStyle(color: AppColors.deleteRed)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'profile') {
        _showProfilePictureOptions();
      } else if (value == 'password') {
        _showChangePasswordDialog();
      } else if (value == 'logout') {
        unawaited(_handleLogout());
      }
    });
  }

  void _showProfilePictureOptions() {
    final hasImage = _profileImageUrl != null && _profileImageUrl!.isNotEmpty;

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              if (hasImage)
                ListTile(
                  leading: const Icon(Icons.fullscreen),
                  title: const Text('View Full Size'),
                  onTap: () {
                    Navigator.pop(context);
                    _viewFullSizeImage();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickProfileImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _takeProfilePhoto();
                },
              ),
              if (hasImage)
                ListTile(
                  leading: Icon(Icons.delete, color: AppColors.deleteRed),
                  title: Text(
                    'Remove Photo',
                    style: TextStyle(color: AppColors.deleteRed),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _removeProfilePhoto();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _viewFullSizeImage() {
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      openFullScreenImage(context, _profileImageUrl!);
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        await _uploadProfilePhoto(bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: ${e.toString()}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _takeProfilePhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        await _uploadProfilePhoto(bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error taking photo: ${e.toString()}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _uploadProfilePhoto(Uint8List bytes) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Upload to Firebase Storage
      final storagePath = 'profiles/${currentUser.uid}.jpg';
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      final metadata = SettableMetadata(contentType: 'image/jpeg');
      await ref.putData(bytes, metadata);
      final url = await ref.getDownloadURL();

      // Update Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({'profileImageUrl': url});

      // Close loading indicator
      if (mounted) Navigator.of(context).pop();

      // Update local state
      setState(() {
        _profileImageUrl = url;
      });

      _cachedProfileImageUrl = url;
      _lastProfileFetchAt = DateTime.now();
      _precacheProfileImage(url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated successfully!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Close loading indicator
      if (mounted) Navigator.of(context).pop();

      debugPrint('Error uploading profile photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading photo: ${e.toString()}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _removeProfilePhoto() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Delete from Firebase Storage
      final storagePath = 'profiles/${currentUser.uid}.jpg';
      try {
        await FirebaseStorage.instance.ref().child(storagePath).delete();
      } catch (_) {
        // Ignore if file doesn't exist
      }

      // Update Firestore - remove the URL
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({'profileImageUrl': FieldValue.delete()});

      // Close loading indicator
      if (mounted) Navigator.of(context).pop();

      // Update local state
      setState(() {
        _profileImageUrl = null;
      });

      _cachedProfileImageUrl = null;
      _lastProfileFetchAt = DateTime.now();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture removed'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Close loading indicator
      if (mounted) Navigator.of(context).pop();

      debugPrint('Error removing profile photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing photo: ${e.toString()}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => const ChangePasswordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final avatarSize = compact ? 44.0 : 60.0;
    final iconSize = compact ? 22.0 : 36.0;
    final nameSize = compact ? 13.0 : 14.0;
    final positionSize = compact ? 11.0 : 12.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _showProfileMenu,
        child: Row(
          mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
          children: [
            // Profile Avatar
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.inputBackground,
                border: Border.all(
                  color:
                      _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                      ? AppColors.primaryGreen
                      : AppColors.lightGrey,
                  width:
                      _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                      ? 2
                      : 1,
                ),
              ),
              child: ClipOval(
                child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                    ? Image.network(
                        _profileImageUrl!,
                        width: avatarSize,
                        height: avatarSize,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.person,
                            color: AppColors.darkGrey,
                            size: iconSize,
                          );
                        },
                      )
                    : Icon(
                        Icons.person,
                        color: AppColors.darkGrey,
                        size: iconSize,
                      ),
              ),
            ),
            SizedBox(width: compact ? 10 : 12),
            // User Info Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fullName ?? 'Admin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: nameSize,
                      fontWeight: FontWeight.w600,
                      color: _isHovered
                          ? AppColors.primaryGreen
                          : AppColors.darkGrey,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _userPosition ?? 'Administrator',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: positionSize,
                      color: AppColors.lightGrey,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: compact ? 4 : 8),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: _isHovered ? AppColors.primaryGreen : AppColors.darkGrey,
            ),
          ],
        ),
      ),
    );
  }
}

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final currentPassword = _currentPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (currentPassword.isEmpty ||
        newPassword.isEmpty ||
        confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New passwords do not match'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 6 characters'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No signed-in user found');
      }

      final email = user.email;
      final providers = user.providerData.map((e) => e.providerId).toList();

      debugPrint('User UID: ${user.uid}');
      debugPrint('User email: $email');
      debugPrint('Providers: $providers');

      if (email == null || email.isEmpty) {
        throw Exception('This account has no Firebase Auth email');
      }

      if (!providers.contains('password')) {
        throw Exception('This account does not support password change');
      }

      debugPrint('Verifying current password with fresh sign-in...');

      // Verify current password by signing in (creates a fresh authenticated session)
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: currentPassword)
          .timeout(const Duration(seconds: 15));

      final freshUser = userCredential.user;
      if (freshUser == null) {
        throw Exception('Sign-in succeeded but no user returned');
      }

      debugPrint('Sign-in successful, updating password...');

      // Update password with the fresh session
      await freshUser
          .updatePassword(newPassword)
          .timeout(const Duration(seconds: 15));

      debugPrint('Password updated successfully');

      if (mounted) {
        // Navigate to login FIRST (disposes old screens and their Firestore listeners)
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
        // Then show message after navigation
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Password changed! Please log in with your new password.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      // Sign out after navigation (avoids Firestore permission errors)
      debugPrint('Signing out for security...');
      await FirebaseAuth.instance.signOut();
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException: ${e.code} - ${e.message}');
      String message = 'Failed to change password';
      if (e.code == 'wrong-password') {
        message = 'Current password is incorrect';
      } else if (e.code == 'weak-password') {
        message = 'New password is too weak';
      } else if (e.code == 'requires-recent-login') {
        message = 'Please log in again before changing password';
      } else if (e.code == 'invalid-credential') {
        message = 'Invalid credentials. Please check your current password.';
      } else if (e.code == 'user-not-found') {
        message = 'User not found. Please log in again.';
      } else if (e.code == 'too-many-requests') {
        message = 'Too many attempts. Please try again later.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on TimeoutException catch (_) {
      debugPrint('Password change timed out');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request timed out. Please try again.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error changing password: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Change Password',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkGrey,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppColors.lightGrey),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Current Password
            TextField(
              controller: _currentPasswordController,
              obscureText: _obscureCurrentPassword,
              decoration: InputDecoration(
                labelText: 'Current Password',
                labelStyle: const TextStyle(color: AppColors.lightGrey),
                filled: true,
                fillColor: AppColors.inputBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureCurrentPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: AppColors.lightGrey,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureCurrentPassword = !_obscureCurrentPassword;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            // New Password
            TextField(
              controller: _newPasswordController,
              obscureText: _obscureNewPassword,
              decoration: InputDecoration(
                labelText: 'New Password',
                labelStyle: const TextStyle(color: AppColors.lightGrey),
                filled: true,
                fillColor: AppColors.inputBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNewPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: AppColors.lightGrey,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureNewPassword = !_obscureNewPassword;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Confirm New Password
            TextField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              decoration: InputDecoration(
                labelText: 'Confirm New Password',
                labelStyle: const TextStyle(color: AppColors.lightGrey),
                filled: true,
                fillColor: AppColors.inputBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: AppColors.lightGrey,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: AppColors.lightGrey),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.darkGrey),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _changePassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Change Password'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

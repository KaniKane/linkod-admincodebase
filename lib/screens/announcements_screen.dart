import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/announcement_backend_api.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/audience_tag.dart';
import '../widgets/draft_item.dart';
import '../widgets/success_notification.dart';
import '../widgets/draft_saved_notification.dart';
import '../widgets/error_notification.dart';
import '../widgets/custom_button.dart';
import '../widgets/outline_button.dart';
import '../widgets/dialog_container.dart';
import '../models/announcement_draft.dart';
import '../utils/app_colors.dart';
import 'dashboard_screen.dart';
import 'approvals_screen.dart';
import 'user_management_screen.dart';
import 'barangay_information_screen.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  static const String _lastTabPrefsKey = 'announcements_last_tab';

  int _activeTabIndex = 0;
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _aiRefinedController = TextEditingController();
  Set<String> _selectedAudiences = {};
  bool _isAIRefined = false;
  List<String> _suggestedAudiences = ['Senior', 'PWD'];
  bool _isRefining = false;
  bool _isSuggestingDemographic = false;
  bool _hasTriggeredAudienceSuggestion = false;

  // Drafts loaded from Firestore
  List<AnnouncementDraft> _drafts = [];

  // Published announcements (Approved) for Posts tab; officials see only their own
  List<Map<String, dynamic>> _publishedAnnouncements = [];

  // Currently edited draft id (if any)
  String? _currentDraftId;

  // Currently editing announcement id (if any) - for updating existing announcements
  String? _currentEditingAnnouncementId;

  // Announcement images: existing URLs (from loaded draft) and newly picked files
  List<String> _announcementImageUrls = [];
  List<XFile> _pickedImages = [];

  // Current user role for permission checks
  String? _currentUserRole;

  bool _isPostingAnnouncement = false;

  // Pending counts for sidebar badges
  int _pendingApprovalsCount = 0;
  int _pendingUsersCount = 0;

  final List<String> _audienceOptions = [
    'General Residents',
    'Senior',
    'Student',
    'PWD',
    'Youth',
    'Farmer',
    'Fisherman',
    'Tricycle Driver',
    'Small Business Owner',
    '4Ps',
    'Tanod',
    'Barangay Official',
    'Parent',
  ];

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.initialTabIndex.clamp(0, 2);
    if (widget.initialTabIndex == 0) {
      _restoreLastTabIndex();
    } else {
      _persistActiveTabIndex();
    }
    _loadDrafts();
    _loadCurrentUserRole();
    _loadPublishedAnnouncements();
    _loadPendingCounts();
  }

  Future<void> _restoreLastTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(_lastTabPrefsKey);
    if (savedIndex == null || !mounted) return;
    final normalized = savedIndex.clamp(0, 2);
    if (normalized == _activeTabIndex) return;
    setState(() {
      _activeTabIndex = normalized;
    });
    if (normalized == 2) {
      _loadPublishedAnnouncements();
    }
  }

  Future<void> _persistActiveTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastTabPrefsKey, _activeTabIndex.clamp(0, 2));
  }

  void _setActiveTab(int index) {
    final nextIndex = index.clamp(0, 2);
    if (nextIndex == _activeTabIndex) return;
    setState(() {
      _activeTabIndex = nextIndex;
    });
    _persistActiveTabIndex();
    if (nextIndex == 2) {
      _loadPublishedAnnouncements();
    }
  }

  static DateTime? _parseTimestamp(dynamic t) {
    if (t == null) return null;
    if (t is Timestamp) return t.toDate();
    if (t is DateTime) return t;
    return null;
  }

  Future<void> _loadPendingCounts() async {
    int pendingAnnouncements = 0;
    int pendingProducts = 0;
    int pendingTasks = 0;
    int pendingUsers = 0;
    final isSuperAdmin =
        (_currentUserRole ?? '').toLowerCase() == 'super_admin';
    try {
      final pendingAnnouncementsSnap = await FirebaseFirestore.instance
          .collection('announcements')
          .where('status', isEqualTo: 'Pending')
          .count()
          .get();
      pendingAnnouncements = pendingAnnouncementsSnap.count ?? 0;
    } catch (_) {}
    try {
      final pendingProductsSnap = await FirebaseFirestore.instance
          .collection('products')
          .where('status', isEqualTo: 'Pending')
          .count()
          .get();
      pendingProducts = pendingProductsSnap.count ?? 0;
    } catch (_) {}
    try {
      final pendingTasksSnap = await FirebaseFirestore.instance
          .collection('tasks')
          .where('approvalStatus', isEqualTo: 'Pending')
          .count()
          .get();
      pendingTasks = pendingTasksSnap.count ?? 0;
    } catch (_) {}
    if (isSuperAdmin) {
      try {
        final pendingUsersSnap = await FirebaseFirestore.instance
            .collection('awaitingApproval')
            .count()
            .get();
        pendingUsers = pendingUsersSnap.count ?? 0;
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _pendingApprovalsCount =
            pendingAnnouncements + pendingProducts + pendingTasks;
        _pendingUsersCount = pendingUsers;
      });
    }
  }

  Future<void> _loadPublishedAnnouncements() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('announcements')
          .where('status', isEqualTo: 'Approved')
          .get();
      var list = snapshot.docs.map((doc) {
        final d = doc.data();
        final imageUrlsRaw = d['imageUrls'] as List<dynamic>?;
        final imageUrls =
            imageUrlsRaw?.whereType<String>().toList() ?? <String>[];
        final postedByUserId =
            (d['postedByUserId'] ??
                    d['createdByUserId'] ??
                    d['authorUserId'] ??
                    d['userId'])
                as String?;
        return {
          'id': doc.id,
          'title': d['title'] as String? ?? '',
          'content': d['content'] as String? ?? '',
          'postedBy': d['postedBy'] as String? ?? '',
          'postedByUserId': postedByUserId,
          'createdAt': _parseTimestamp(d['createdAt']),
          'imageUrls': imageUrls,
        };
      }).toList();
      String role = (_currentUserRole ?? 'admin').toLowerCase();
      if (role != 'super_admin' && currentUser != null) {
        list = list
            .where((a) => a['postedByUserId'] == currentUser.uid)
            .toList();
      }
      list.sort((a, b) {
        final aT = a['createdAt'] as DateTime? ?? DateTime(0);
        final bT = b['createdAt'] as DateTime? ?? DateTime(0);
        return bT.compareTo(aT);
      });
      if (mounted) setState(() => _publishedAnnouncements = list);
    } catch (_) {
      if (mounted) setState(() => _publishedAnnouncements = []);
    }
  }

  Future<void> _loadCurrentUserRole() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        if (userDoc.exists && mounted) {
          final role = (userDoc.data()?['role'] as String? ?? 'admin')
              .toLowerCase();
          setState(() {
            _currentUserRole = role;
          });
          await _loadPendingCounts();
          await _loadPublishedAnnouncements();
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _currentUserRole = 'admin';
          });
          await _loadPendingCounts();
          await _loadPublishedAnnouncements();
        }
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _aiRefinedController.dispose();
    super.dispose();
  }

  void _navigateTo(String route) {
    if ((_currentUserRole ?? '').toLowerCase() != 'super_admin' &&
        (route == '/approvals' || route == '/user-management')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const DraftSavedNotification(
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
    } else if (route == '/barangay-information') {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              BarangayInformationScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        ),
      );
    }
  }

  void _toggleAudience(String audience) {
    setState(() {
      if (_selectedAudiences.contains(audience)) {
        _selectedAudiences.remove(audience);
      } else {
        _selectedAudiences.add(audience);
      }
    });
  }

  Future<void> _handleRefineWithAI() async {
    final original = _contentController.text.trim();
    if (original.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const ErrorNotification(
            message: 'Please enter content before refining.',
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isRefining = true;
      _hasTriggeredAudienceSuggestion = true;
    });
    try {
      final result = await refineAnnouncementText(original);
      if (!mounted) return;
      setState(() {
        _aiRefinedController.text = result.refinedText;
        _isAIRefined = true;
        _isRefining = false;
      });
      // Rule-based audience recommendation from refined text (no AI; transparent)
      try {
        final audienceResult = await recommendAudiences(result.refinedText);
        if (!mounted) return;
        setState(() {
          _suggestedAudiences = audienceResult.audiences.isNotEmpty
              ? audienceResult.audiences
              : _suggestedAudiences;
        });
      } catch (_) {
        // Keep previous suggested audiences if recommend-audiences fails
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const DraftSavedNotification(
                message:
                    'Audience suggestion unavailable. You can still select audiences manually.',
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } on AnnouncementBackendException catch (e) {
      if (!mounted) return;
      setState(() => _isRefining = false);
      final message = e.statusCode == 503
          ? 'Refinement failed. Is the backend running and Ollama available (llama3.2:3b)?'
          : (e.message.length > 80
                ? 'Refinement failed. Check backend.'
                : e.message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: DraftSavedNotification(message: message),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRefining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ErrorNotification(message: 'Refinement failed: $e'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleEditOriginal() {
    setState(() {
      _isAIRefined = false;
    });
  }

  void _handleAddSuggestedAudience(String audience) {
    setState(() {
      _selectedAudiences.add(audience);
    });
  }

  void _handleEditDraft(AnnouncementDraft draft) {
    setState(() {
      _titleController.text = draft.title;
      // Original content in Content field, refined in AI-Refined field
      _contentController.text = draft.originalContent ?? draft.content;
      _selectedAudiences = Set.from(draft.selectedAudiences);
      final hasRefined = (draft.aiRefinedContent ?? '').trim().isNotEmpty;
      _isAIRefined = hasRefined;
      _aiRefinedController.text = draft.aiRefinedContent ?? '';
      _currentDraftId = draft.id;
      _announcementImageUrls = List.from(draft.imageUrls);
      _pickedImages = [];
      _hasTriggeredAudienceSuggestion = true;
    });
    _setActiveTab(0); // Switch to Compose tab
  }

  void _handleDeleteDraft(String draftId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Draft'),
          content: const Text('Are you sure you want to delete this draft?'),
          actions: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () async {
                      try {
                        await FirebaseFirestore.instance
                            .collection('announcementDrafts')
                            .doc(draftId)
                            .delete();
                      } catch (_) {
                        // Ignore delete error for now; UI will refresh anyway.
                      }
                      if (mounted) {
                        setState(() {
                          _drafts.removeWhere((draft) => draft.id == draftId);
                          if (_currentDraftId == draftId) {
                            _currentDraftId = null;
                          }
                        });
                        Navigator.of(context).pop();
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Delete',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlineButton(
                  text: 'Cancel',
                  isFullWidth: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadDrafts() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('announcementDrafts')
          .orderBy('createdAt', descending: true)
          .get();

      final drafts = snapshot.docs.map((doc) {
        final data = doc.data();
        final audiences =
            (data['audiences'] as List?)?.whereType<String>().toList() ??
            <String>[];
        final imageUrlsRaw = data['imageUrls'] as List<dynamic>?;
        final imageUrls =
            imageUrlsRaw?.whereType<String>().toList() ?? <String>[];
        return AnnouncementDraft(
          id: doc.id,
          title: (data['title'] ?? '') as String,
          content: (data['content'] ?? '') as String,
          originalContent: data['originalContent'] as String?,
          selectedAudiences: audiences.toSet(),
          aiRefinedContent: data['aiRefinedContent'] as String?,
          imageUrls: imageUrls,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _drafts = drafts;
        });
      }
    } catch (_) {
      // Silently ignore load errors for now.
    }
  }

  /// Suggest demographics from current content (refined if available, else original).
  /// Allows rule-based targeting without using "Refine text with AI".
  /// Sends title + body so rules match against both (works when only original content exists).
  Future<void> _handleSuggestDemographic() async {
    final title = _titleController.text.trim();
    final refined = _aiRefinedController.text.trim();
    final original = _contentController.text.trim();
    final body = refined.isNotEmpty ? refined : original;
    final text = [title, body].where((s) => s.isNotEmpty).join('\n\n');
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const ErrorNotification(
            message:
                'Please enter title or content first to suggest demographics.',
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      _isSuggestingDemographic = true;
      _hasTriggeredAudienceSuggestion = true;
    });
    try {
      final audienceResult = await recommendAudiences(text);
      if (!mounted) return;
      setState(() {
        _suggestedAudiences = audienceResult.audiences.isNotEmpty
            ? audienceResult.audiences
            : _suggestedAudiences;
        _isSuggestingDemographic = false;
      });
    } on AnnouncementBackendException catch (e) {
      if (!mounted) return;
      setState(() => _isSuggestingDemographic = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: DraftSavedNotification(
            message: e.message.length > 80
                ? 'Suggestion failed. Check backend.'
                : e.message,
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSuggestingDemographic = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ErrorNotification(message: 'Suggest demographic failed: $e'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleSaveDraft() async {
    final title = _titleController.text.trim();
    final originalContent = _contentController.text.trim();
    final refinedContent = _aiRefinedController.text.trim();
    final content = _isAIRefined && refinedContent.isNotEmpty
        ? refinedContent
        : originalContent;

    if (title.isEmpty || content.isEmpty || _selectedAudiences.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const ErrorNotification(
            message:
                'Title, content, and at least one target audience are required to save draft',
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    List<String> imageUrls = List.from(_announcementImageUrls);
    if (_pickedImages.isNotEmpty) {
      try {
        final newUrls = await _uploadAnnouncementImages(_pickedImages);
        imageUrls = [..._announcementImageUrls, ...newUrls];
        if (mounted) {
          setState(() {
            _announcementImageUrls = imageUrls;
            _pickedImages = [];
          });
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ErrorNotification(message: 'Failed to upload images: $e'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    final data = <String, dynamic>{
      'title': title,
      'content': content,
      'originalContent': originalContent,
      'aiRefinedContent': refinedContent.isNotEmpty ? refinedContent : null,
      'audiences': _selectedAudiences.toList(),
      'imageUrls': imageUrls,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (_currentDraftId != null) {
        await FirebaseFirestore.instance
            .collection('announcementDrafts')
            .doc(_currentDraftId)
            .set(data, SetOptions(merge: true));
      } else {
        final docRef = await FirebaseFirestore.instance
            .collection('announcementDrafts')
            .add({...data, 'createdAt': FieldValue.serverTimestamp()});
        _currentDraftId = docRef.id;
      }

      await _loadDrafts();

      if (!mounted) return;

      showDialog(
        context: context,
        barrierColor: Colors.transparent,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.all(20),
            child: const SuccessNotification(
              message: 'Draft saved successfully',
            ),
          );
        },
      );

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ErrorNotification(message: 'Failed to save draft: $e'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handlePostAnnouncement() async {
    final title = _titleController.text.trim();
    final originalContent = _contentController.text.trim();
    final refinedContent = _aiRefinedController.text.trim();
    final content = _isAIRefined && refinedContent.isNotEmpty
        ? refinedContent
        : originalContent;

    if (title.isEmpty || content.isEmpty || _selectedAudiences.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const ErrorNotification(
            message:
                'Title, content, and at least one target audience are required to post',
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_isPostingAnnouncement) return;
    if (!mounted) return;
    setState(() => _isPostingAnnouncement = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      String postedBy = 'Barangay Official';
      String? postedByUserId;
      String? postedByPosition;
      String currentUserRole = 'official'; // Default fallback

      if (currentUser != null) {
        postedByUserId = currentUser.uid;
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        if (userDoc.exists) {
          final userData = userDoc.data() ?? {};
          postedBy = (userData['fullName'] as String?) ?? postedBy;
          postedByPosition = userData['position'] as String?;
          currentUserRole = ((userData['role'] as String?) ?? 'admin')
              .toLowerCase();
        }
      }

      // Role-based status: SUPER ADMIN publishes directly, OFFICIAL creates as Pending
      final canPublishDirectly = currentUserRole == 'super_admin';
      final status = canPublishDirectly ? 'Approved' : 'Pending';

      // OFFICIAL: no push option (push only when admin approves). SUPER ADMIN: choose post only or post + push.
      String? choice;
      if (canPublishDirectly) {
        choice = await showDialog<String>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Post announcement'),
              content: Text(
                'Audience: ${_selectedAudiences.join(', ')}\n\n'
                'Choose how to publish:',
              ),
              actions: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CustomButton(
                      text: 'Post and send push',
                      isFullWidth: true,
                      onPressed: () =>
                          Navigator.of(context).pop('post_and_push'),
                    ),
                    const SizedBox(height: 12),
                    OutlineButton(
                      text: 'Post only',
                      isFullWidth: true,
                      onPressed: () => Navigator.of(context).pop('post_only'),
                    ),
                    const SizedBox(height: 12),
                    OutlineButton(
                      text: 'Cancel',
                      isFullWidth: true,
                      onPressed: () => Navigator.of(context).pop('cancel'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      } else {
        choice = await showDialog<String>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Submit for approval'),
              content: Text(
                'Audience: ${_selectedAudiences.join(', ')}\n\n'
                'Your announcement will be sent to the admin/kapitan for approval. Push will be sent only after approval.',
              ),
              actions: [
                OutlineButton(
                  text: 'Cancel',
                  onPressed: () => Navigator.of(context).pop('cancel'),
                ),
                CustomButton(
                  text: 'Submit for approval',
                  isFullWidth: false,
                  onPressed: () => Navigator.of(context).pop('post_only'),
                ),
              ],
            );
          },
        );
      }

      if (choice == null || choice == 'cancel') {
        if (mounted) setState(() => _isPostingAnnouncement = false);
        return;
      }

      List<String> imageUrls = List.from(_announcementImageUrls);
      if (_pickedImages.isNotEmpty) {
        final newUrls = await _uploadAnnouncementImages(_pickedImages);
        imageUrls = [..._announcementImageUrls, ...newUrls];
      }

      // Check if we're editing an existing announcement
      if (_currentEditingAnnouncementId != null) {
        // Update existing announcement
        await FirebaseFirestore.instance
            .collection('announcements')
            .doc(_currentEditingAnnouncementId)
            .update({
              'title': title,
              'content': content,
              'originalContent': originalContent,
              'aiRefinedContent': refinedContent.isNotEmpty
                  ? refinedContent
                  : null,
              'audiences': _selectedAudiences.toList(),
              'imageUrls': imageUrls,
              'updatedAt': FieldValue.serverTimestamp(),
            });

        if (mounted) {
          setState(
            () => _currentEditingAnnouncementId = null,
          ); // Clear editing state
          _loadPublishedAnnouncements();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Announcement updated successfully'),
              backgroundColor: AppColors.primaryGreen,
            ),
          );
        }
      } else {
        // Create new announcement
        final announcementRef = await FirebaseFirestore.instance
            .collection('announcements')
            .add({
              'title': title,
              'content': content,
              'originalContent': originalContent,
              'aiRefinedContent': refinedContent.isNotEmpty
                  ? refinedContent
                  : null,
              'audiences': _selectedAudiences.toList(),
              'imageUrls': imageUrls,
              'status': status,
              'postedBy': postedBy,
              if (postedByPosition != null && postedByPosition.isNotEmpty)
                'postedByPosition': postedByPosition,
              if (postedByUserId != null) 'postedByUserId': postedByUserId,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
              'isActive': true,
            });

        if (!mounted) return;

        // When approval is on (status Pending), log to Recent Activities
        if (status == 'Pending') {
          try {
            String adminName = postedBy;
            if (postedByUserId != null) {
              final adminDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(postedByUserId)
                  .get();
              if (adminDoc.exists) {
                adminName =
                    (adminDoc.data()?['fullName'] as String?) ?? postedBy;
              }
            }
            await FirebaseFirestore.instance.collection('adminActivities').add({
              'type': 'post_request',
              'description':
                  '$adminName submitted an announcement for approval: $title',
              'fullName': title,
              'createdAt': FieldValue.serverTimestamp(),
            });
          } catch (_) {}
        }

        // Only send push when SUPER ADMIN chose "post and send push". OFFICIAL posts are Pending — push sent when admin approves.
        final shouldSendPush = choice == 'post_and_push' && canPublishDirectly;
        if (shouldSendPush) {
          final notifBody = content.length > 140
              ? '${content.substring(0, 137)}...'
              : content;
          try {
            final result = await sendAnnouncementPush(
              announcementId: announcementRef.id,
              title: title,
              body: notifBody,
              audiences: _selectedAudiences.toList(),
              requestedByUserId: postedByUserId,
            );

            if (!mounted) return;
            final String msg;
            if (result.tokenCount == 0) {
              if (result.userCount == 0) {
                msg =
                    'No residents matched the selected audiences. Check User Management: role=resident, approved, active, and Demographic category (categories array) matches the chosen audiences.';
              } else {
                msg =
                    'No valid tokens. ${result.userCount} resident(s) matched but none have FCM tokens. Ensure the mobile app has been opened after login on the target device(s).';
              }
            } else {
              msg =
                  'Push sent: ${result.successCount}/${result.tokenCount} token(s).';
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: DraftSavedNotification(message: msg),
                backgroundColor: Colors.transparent,
                elevation: 0,
                behavior: SnackBarBehavior.floating,
              ),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: ErrorNotification(message: 'Push send failed: $e'),
                backgroundColor: Colors.transparent,
                elevation: 0,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }

        final successMessage = canPublishDirectly
            ? 'Announcement is posted successfully'
            : 'Announcement submitted for approval. It will appear after admin approval.';

        showDialog(
          context: context,
          barrierColor: Colors.transparent,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.all(20),
              child: SuccessNotification(message: successMessage),
            );
          },
        );

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ErrorNotification(
            message: 'Failed to post announcement: $e',
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPostingAnnouncement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Row(
        children: [
          // Sidebar
          AppSidebar(
            currentRoute: '/announcements',
            currentUserRole: _currentUserRole,
            pendingApprovalsCount: _pendingApprovalsCount,
            pendingUsersCount: _pendingUsersCount,
            onNavigate: _navigateTo,
          ),
          // Main content
          Expanded(
            child: Container(
              color: AppColors.white,
              child: Column(
                children: [
                  // Top header
                  Container(
                    color: AppColors.white,
                    padding: const EdgeInsets.all(24),
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Announcements',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkGrey,
                        ),
                      ),
                    ),
                  ),
                  // Content area with inner background panel
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.dashboardInnerBg,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Column(
                        children: [
                          // Tabs bar at top of inner panel
                          _buildTabsBar(),
                          // Content area
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(32),
                              child: _activeTabIndex == 0
                                  ? _buildComposeTab()
                                  : _activeTabIndex == 1
                                  ? _buildDraftTab()
                                  : _buildPostsTab(),
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
        ],
      ),
    );
  }

  Widget _buildTabsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 0),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.inputBackground, width: 1),
        ),
      ),
      child: Row(
        children: [
          _buildTab('Compose', 0),
          const SizedBox(width: 32),
          _buildTab('Draft', 1),
          const SizedBox(width: 32),
          _buildTab('Posted', 2),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isActive = _activeTabIndex == index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _setActiveTab(index),
        child: Container(
          padding: const EdgeInsets.only(bottom: 16, top: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? AppColors.primaryGreen : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: isActive ? AppColors.darkGrey : AppColors.mediumGrey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposeTab() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          const Text(
            'AI-Assisted Announcement Composer',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.darkGrey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create clear, professional announcements with AI assistance',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: AppColors.mediumGrey,
            ),
          ),
          const SizedBox(height: 32),
          // Title field
          const Text(
            'Title',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: AppColors.darkGrey,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F1F1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 16, color: AppColors.darkGrey),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Content field
          const Text(
            'Content',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: AppColors.darkGrey,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F1F1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _contentController,
              minLines: 5,
              maxLines: null,
              style: const TextStyle(fontSize: 16, color: AppColors.darkGrey),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(15),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // AI Refine and Suggest demographic buttons
          Row(
            children: [
              _buildAIButton(),
              const SizedBox(width: 12),
              _buildSuggestDemographicButton(),
            ],
          ),
          // Spacing so Suggested Audiences never overlaps buttons (when refined box is absent)
          const SizedBox(height: 24),
          // AI-Refined Version section (only when user has refined)
          if (_isAIRefined) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'AI-Refined Version',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: AppColors.darkGrey,
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _handleEditOriginal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.mediumGrey,
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'Edit Original',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: AppColors.darkGrey,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.aiRefinedBorder, width: 2),
              ),
              child: TextField(
                controller: _aiRefinedController,
                minLines: 5,
                maxLines: null,
                style: const TextStyle(fontSize: 16, color: AppColors.darkGrey),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(15),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
          // Suggested Audiences section (shown only after audience suggestion is triggered)
          if (_hasTriggeredAudienceSuggestion)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.suggestedAudienceBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.lightbulb_outline,
                        color: AppColors.darkGrey,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Suggested Audiences',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkGrey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Rule-based suggestion from your content (review and edit as needed):',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: AppColors.mediumGrey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _suggestedAudiences.map((audience) {
                      final isAlreadySelected = _selectedAudiences.contains(
                        audience,
                      );
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            if (!isAlreadySelected) {
                              _handleAddSuggestedAudience(audience);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.primaryGreen,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              isAlreadySelected
                                  ? audience
                                  : '$audience (Click to add)',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: AppColors.darkGrey,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),
          // Target Audience section
          const Text(
            'Target Audience Required',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: AppColors.darkGrey,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _audienceOptions.map((audience) {
              return AudienceTag(
                label: audience,
                isSelected: _selectedAudiences.contains(audience),
                onTap: () => _toggleAudience(audience),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            '${_selectedAudiences.length} audience group(s) selected',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: AppColors.lightGrey,
            ),
          ),
          const SizedBox(height: 32),
          // Images section (optional)
          const Text(
            'Images (optional)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: AppColors.darkGrey,
            ),
          ),
          const SizedBox(height: 12),
          _buildAnnouncementImagesSection(),
          const SizedBox(height: 32),
          // Footer buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildDraftButton(),
              const SizedBox(width: 16),
              _buildPostButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAIButton() {
    return MouseRegion(
      cursor: _isRefining ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _isRefining ? null : _handleRefineWithAI,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: _isRefining ? AppColors.mediumGrey : AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(25),
          ),
          child: _isRefining
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                  ),
                )
              : const Text(
                  'Refine text with AI',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: AppColors.white,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSuggestDemographicButton() {
    return MouseRegion(
      cursor: _isSuggestingDemographic
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _isSuggestingDemographic ? null : _handleSuggestDemographic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: _isSuggestingDemographic
                ? AppColors.mediumGrey
                : AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(25),
          ),
          child: _isSuggestingDemographic
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                  ),
                )
              : const Text(
                  'Suggest demographic',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: AppColors.white,
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _pickAnnouncementImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _pickedImages.addAll(picked);
    });
  }

  void _removeAnnouncementImageUrl(int index) {
    setState(() {
      _announcementImageUrls.removeAt(index);
    });
  }

  void _removePickedImage(int index) {
    setState(() {
      _pickedImages.removeAt(index);
    });
  }

  /// Upload [files] to Firebase Storage announcement_images/ and return their download URLs.
  Future<List<String>> _uploadAnnouncementImages(List<XFile> files) async {
    if (files.isEmpty) return [];
    final ref = FirebaseStorage.instance.ref();
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      final path = 'announcement_images/${userId}_${ts}_$i.jpg';
      final file = File(files[i].path);
      final uploadRef = ref.child(path);
      await uploadRef.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await uploadRef.getDownloadURL();
      urls.add(url);
    }
    return urls;
  }

  Widget _buildAnnouncementImagesSection() {
    final totalCount = _announcementImageUrls.length + _pickedImages.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.mediumGrey.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _pickAnnouncementImages,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primaryGreen.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: AppColors.primaryGreen,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Add image(s)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.darkGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (totalCount > 0) ...[
                const SizedBox(width: 12),
                Text(
                  '$totalCount image(s)',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.lightGrey,
                  ),
                ),
              ],
            ],
          ),
          if (totalCount > 0) ...[
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...List.generate(_announcementImageUrls.length, (i) {
                    final url = _announcementImageUrls[i];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildImageThumbnail(
                        key: ValueKey('url_$i'),
                        child: Image.network(
                          url,
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image_outlined, size: 40),
                        ),
                        onRemove: () => _removeAnnouncementImageUrl(i),
                        onTap: () => _showFullScreenImage(url),
                      ),
                    );
                  }),
                  ...List.generate(_pickedImages.length, (i) {
                    final xfile = _pickedImages[i];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildImageThumbnail(
                        key: ValueKey('file_$i'),
                        child: Image.file(
                          File(xfile.path),
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                        ),
                        onRemove: () => _removePickedImage(i),
                        onTap: () => _showFullScreenFile(xfile.path),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageThumbnail({
    required Key key,
    required Widget child,
    required VoidCallback onRemove,
    required VoidCallback onTap,
  }) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.mediumGrey.withOpacity(0.5)),
        color: AppColors.mediumGrey.withOpacity(0.1),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(width: 96, height: 96, child: child),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.primaryGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: AppColors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            Positioned(
              top: -8,
              right: -8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreenFile(String path) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            InteractiveViewer(
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
            Positioned(
              top: -8,
              right: -8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _handleSaveDraft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.mediumGrey, width: 1),
          ),
          child: const Text(
            'Save as draft',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: AppColors.darkGrey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPostButton() {
    // STAFF cannot create announcements
    if (_currentUserRole == 'staff') {
      return const SizedBox.shrink();
    }

    return MouseRegion(
      cursor: _isPostingAnnouncement
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _isPostingAnnouncement ? null : _handlePostAnnouncement,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: _isPostingAnnouncement
                ? AppColors.mediumGrey
                : AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(10),
          ),
          child: _isPostingAnnouncement
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                  ),
                )
              : Text(
                  _currentUserRole == 'super_admin'
                      ? 'Post Announcement'
                      : 'Submit for Approval',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: AppColors.white,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildDraftTab() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Announcement Drafts',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.darkGrey,
            ),
          ),
          const SizedBox(height: 24),
          if (_drafts.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'No drafts available',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: AppColors.mediumGrey,
                  ),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _drafts.length,
              itemBuilder: (context, index) {
                final draft = _drafts[index];
                return DraftItem(
                  draft: draft,
                  onEdit: () => _handleEditDraft(draft),
                  onDelete: () => _handleDeleteDraft(draft.id),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPostsTab() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Published Posts',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.darkGrey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _currentUserRole == 'super_admin'
                ? 'All approved announcements. Tap "View readers" to see who read each post.'
                : 'Your approved announcements. Tap "View readers" to see who read each post.',
            style: const TextStyle(fontSize: 14, color: AppColors.mediumGrey),
          ),
          const SizedBox(height: 24),
          if (_publishedAnnouncements.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'No published posts yet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: AppColors.mediumGrey,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _publishedAnnouncements.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final a = _publishedAnnouncements[index];
                return _AnnouncementCard(
                  announcement: a,
                  onViewReaders: () => _showViewReadersModal(
                    a['id'] as String,
                    a['title'] as String? ?? '',
                  ),
                  onSave: (updatedData) async {
                    try {
                      await FirebaseFirestore.instance
                          .collection('announcements')
                          .doc(updatedData['id'] as String)
                          .update({
                            'title': updatedData['title'],
                            'content': updatedData['content'],
                            'imageUrls': updatedData['imageUrls'],
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                      _loadPublishedAnnouncements();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Announcement updated successfully'),
                          backgroundColor: AppColors.primaryGreen,
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update: $e')),
                      );
                      throw e;
                    }
                  },
                  onDelete: () => _handleDeleteAnnouncement(a['id'] as String),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showViewReadersModal(
    String announcementId,
    String title,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('announcements')
        .doc(announcementId)
        .collection('views')
        .get();
    final readers = snapshot.docs.map((doc) {
      final d = doc.data();
      final viewedAt = _parseTimestamp(d['viewedAt']);
      return {'userId': d['userId'] as String? ?? doc.id, 'viewedAt': viewedAt};
    }).toList();

    final readersWithNames = <Map<String, dynamic>>[];
    for (final reader in readers) {
      final userId = reader['userId'] as String?;
      if (userId != null && userId.isNotEmpty) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();
          final fullName = userDoc.exists
              ? (userDoc.data()?['fullName'] as String? ?? userId)
              : userId;
          readersWithNames.add({
            'userId': userId,
            'fullName': fullName,
            'viewedAt': reader['viewedAt'],
          });
        } catch (_) {
          readersWithNames.add({
            'userId': userId,
            'fullName': userId,
            'viewedAt': reader['viewedAt'],
          });
        }
      }
    }

    readersWithNames.sort((a, b) {
      final aT = a['viewedAt'] as DateTime? ?? DateTime(0);
      final bT = b['viewedAt'] as DateTime? ?? DateTime(0);
      return bT.compareTo(aT);
    });

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => DialogContainer(
        title: 'View Readers: ${title.isNotEmpty ? title : announcementId}',
        maxWidth: 480,
        child: readersWithNames.isEmpty
            ? const Text(
                'No readers yet.',
                style: TextStyle(color: AppColors.mediumGrey),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: readersWithNames.length,
                itemBuilder: (context, i) {
                  final r = readersWithNames[i];
                  final viewedAt = r['viewedAt'] as DateTime?;
                  final viewedStr = viewedAt != null
                      ? '${viewedAt.toIso8601String().substring(0, 16)}'
                      : '—';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            r['fullName'] as String? ??
                                r['userId'] as String? ??
                                '',
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          viewedStr,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.mediumGrey,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
        actions: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              width: 110,
              child: OutlineButton(
                text: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                isFullWidth: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleDeleteAnnouncement(String announcementId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Announcement'),
          content: const Text(
            'Are you sure you want to delete this announcement? This action cannot be undone.',
          ),
          actions: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () async {
                      try {
                        await FirebaseFirestore.instance
                            .collection('announcements')
                            .doc(announcementId)
                            .update({'isActive': false, 'status': 'Deleted'});
                      } catch (e) {
                        if (mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: ErrorNotification(
                                message: 'Failed to delete: $e',
                              ),
                            ),
                          );
                          return;
                        }
                      }
                      if (mounted) {
                        Navigator.of(context).pop();
                        _loadPublishedAnnouncements();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Announcement deleted'),
                            backgroundColor: AppColors.darkGrey,
                          ),
                        );
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlineButton(
                  text: 'Cancel',
                  isFullWidth: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Card widget for displaying an announcement in the Posts tab.
class _AnnouncementCard extends StatefulWidget {
  final Map<String, dynamic> announcement;
  final VoidCallback onViewReaders;
  final Function(Map<String, dynamic> updatedData) onSave;
  final VoidCallback onDelete;

  const _AnnouncementCard({
    required this.announcement,
    required this.onViewReaders,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard> {
  bool _isEditing = false;
  late TextEditingController _editTitleController;
  late TextEditingController _editContentController;
  late List<String> _editImageUrls;
  List<XFile> _newImages = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _editTitleController = TextEditingController();
    _editContentController = TextEditingController();
    _editImageUrls = [];
  }

  @override
  void dispose() {
    _editTitleController.dispose();
    _editContentController.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _editTitleController.text = widget.announcement['title'] as String? ?? '';
      _editContentController.text =
          widget.announcement['content'] as String? ?? '';
      _editImageUrls =
          (widget.announcement['imageUrls'] as List?)
              ?.whereType<String>()
              .toList() ??
          [];
      _newImages = [];
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _newImages = [];
    });
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      // Upload any new images
      List<String> allImageUrls = List.from(_editImageUrls);
      if (_newImages.isNotEmpty) {
        final newUrls = await _uploadImages(_newImages);
        allImageUrls.addAll(newUrls);
      }

      final updatedData = {
        'id': widget.announcement['id'],
        'title': _editTitleController.text.trim(),
        'content': _editContentController.text.trim(),
        'imageUrls': allImageUrls,
      };

      await widget.onSave(updatedData);

      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSaving = false;
          _newImages = [];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  Future<List<String>> _uploadImages(List<XFile> files) async {
    if (files.isEmpty) return [];
    final ref = FirebaseStorage.instance.ref();
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      final path = 'announcement_images/${userId}_${ts}_$i.jpg';
      final file = File(files[i].path);
      final uploadRef = ref.child(path);
      await uploadRef.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await uploadRef.getDownloadURL();
      urls.add(url);
    }
    return urls;
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isNotEmpty && mounted) {
      setState(() {
        _newImages.addAll(picked);
      });
    }
  }

  void _removeExistingImage(int index) {
    setState(() {
      _editImageUrls.removeAt(index);
    });
  }

  void _removeNewImage(int index) {
    setState(() {
      _newImages.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.announcement['id'] as String;
    final title = widget.announcement['title'] as String? ?? '';
    final content = widget.announcement['content'] as String? ?? '';
    final createdAt = widget.announcement['createdAt'] as DateTime?;
    final status = widget.announcement['status'] as String? ?? 'Published';

    final dateStr = createdAt != null ? _formatDate(createdAt) : '—';

    if (_isEditing) {
      return _buildEditingCard();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEAECF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: Title and PopupMenu
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isNotEmpty ? title : 'Untitled',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Metadata row with status badge
                      Row(
                        children: [
                          Text(
                            dateStr,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5EC),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF2E7D32),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Popup menu for Edit/Delete
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    color: AppColors.mediumGrey,
                    size: 20,
                  ),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: AppColors.darkGrey,
                          ),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.red,
                          ),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'edit') {
                      _startEditing();
                    } else if (value == 'delete') {
                      widget.onDelete();
                    }
                  },
                ),
              ],
            ),
            // Content preview
            if (content.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                content,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF4B5563),
                  height: 1.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            // Actions row
            Row(
              children: [
                // View Readers button - neutral outline style
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onViewReaders,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFD1D5DB)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.visibility_outlined,
                            size: 14,
                            color: Color(0xFF6B7280),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'View Readers',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditingCard() {
    final totalImageCount = _editImageUrls.length + _newImages.length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryGreen, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Editing header
            Row(
              children: [
                Icon(Icons.edit, color: AppColors.primaryGreen, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Editing Announcement',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Title field
            Text(
              'Title',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: TextField(
                controller: _editTitleController,
                style: const TextStyle(fontSize: 14, color: Color(0xFF1F2937)),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Content field
            Text(
              'Content',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: TextField(
                controller: _editContentController,
                minLines: 4,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF1F2937),
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(12),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Images section
            Text(
              'Images',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 8),
            // Image preview and add button
            if (totalImageCount > 0) ...[
              SizedBox(
                height: 80,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // Existing images
                    ...List.generate(_editImageUrls.length, (i) {
                      return _buildImageThumbnail(
                        imageUrl: _editImageUrls[i],
                        onRemove: () => _removeExistingImage(i),
                      );
                    }),
                    // New images
                    ...List.generate(_newImages.length, (i) {
                      return _buildImageThumbnail(
                        xFile: _newImages[i],
                        onRemove: () => _removeNewImage(i),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            // Add image button
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _pickImages,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFD1D5DB)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 16,
                        color: Color(0xFF6B7280),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Add Images',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Cancel button
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _cancelEditing,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFD1D5DB)),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Save button
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _isSaving ? null : _saveChanges,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _isSaving
                            ? AppColors.mediumGrey
                            : AppColors.primaryGreen,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageThumbnail({
    String? imageUrl,
    XFile? xFile,
    required VoidCallback onRemove,
  }) {
    return Container(
      width: 80,
      height: 80,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFFF3F4F6),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl != null
                ? Image.network(
                    imageUrl,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 80,
                        height: 80,
                        color: const Color(0xFFE5E7EB),
                        child: const Icon(
                          Icons.broken_image,
                          size: 24,
                          color: Color(0xFF9CA3AF),
                        ),
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: 80,
                        height: 80,
                        color: const Color(0xFFF3F4F6),
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF9CA3AF),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : Image.file(
                    File(xFile!.path),
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}

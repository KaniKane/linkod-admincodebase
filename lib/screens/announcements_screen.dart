import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../api/announcement_backend_api.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/user_header.dart';
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

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  int _activeTabIndex = 0;
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _aiRefinedController = TextEditingController();
  Set<String> _selectedAudiences = {'Senior'};
  bool _isAIRefined = false;
  List<String> _suggestedAudiences = ['Senior', 'PWD'];
  bool _isRefining = false;
  bool _isSuggestingDemographic = false;

  // Drafts loaded from Firestore
  List<AnnouncementDraft> _drafts = [];

  // Published announcements (Approved) for Posts tab; officials see only their own
  List<Map<String, dynamic>> _publishedAnnouncements = [];

  // Currently edited draft id (if any)
  String? _currentDraftId;
  
  // Current user role for permission checks
  String? _currentUserRole;

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
    _loadDrafts();
    _loadCurrentUserRole();
    _loadPublishedAnnouncements();
  }

  static DateTime? _parseTimestamp(dynamic t) {
    if (t == null) return null;
    if (t is Timestamp) return t.toDate();
    if (t is DateTime) return t;
    return null;
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
        return {
          'id': doc.id,
          'title': d['title'] as String? ?? '',
          'content': d['content'] as String? ?? '',
          'postedBy': d['postedBy'] as String? ?? '',
          'postedByUserId': d['postedByUserId'] as String?,
          'createdAt': _parseTimestamp(d['createdAt']),
        };
      }).toList();
      String role = (_currentUserRole ?? 'official').toLowerCase();
      if (role == 'official' && currentUser != null) {
        list = list.where((a) => a['postedByUserId'] == currentUser.uid).toList();
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
          final role = (userDoc.data()?['role'] as String? ?? 'official').toLowerCase();
          setState(() {
            _currentUserRole = role;
          });
        }
      } catch (_) {
        // Silently handle error, default to 'official'
        if (mounted) {
          setState(() {
            _currentUserRole = 'official';
          });
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
    if (route == '/dashboard') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    } else if (route == '/approvals') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ApprovalsScreen()),
      );
    } else if (route == '/user-management') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const UserManagementScreen()),
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
              message: 'Please enter content before refining.'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isRefining = true);
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
                  message: 'Audience suggestion unavailable. You can still select audiences manually.'),
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
          : (e.message.length > 80 ? 'Refinement failed. Check backend.' : e.message);
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
      _activeTabIndex = 0; // Switch to Compose tab
    });
  }

  void _handleDeleteDraft(String draftId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Draft'),
          content: const Text('Are you sure you want to delete this draft?'),
          actions: [
            OutlineButton(
              text: 'Cancel',
              onPressed: () => Navigator.of(context).pop(),
            ),
            CustomButton(
              text: 'Delete',
              isFullWidth: false,
              onPressed: () async {
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
        final audiences = (data['audiences'] as List?)
                ?.whereType<String>()
                .toList() ??
            <String>[];
        return AnnouncementDraft(
          id: doc.id,
          title: (data['title'] ?? '') as String,
          content: (data['content'] ?? '') as String,
          originalContent: data['originalContent'] as String?,
          selectedAudiences: audiences.toSet(),
          aiRefinedContent: data['aiRefinedContent'] as String?,
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
              message: 'Please enter title or content first to suggest demographics.'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isSuggestingDemographic = true);
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
              message: e.message.length > 80 ? 'Suggestion failed. Check backend.' : e.message),
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
    final content =
        _isAIRefined && refinedContent.isNotEmpty ? refinedContent : originalContent;

    if (title.isEmpty || content.isEmpty || _selectedAudiences.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const ErrorNotification(
              message: 'Title, content, and at least one target audience are required to save draft'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final data = <String, dynamic>{
      'title': title,
      'content': content,
      'originalContent': originalContent,
      'aiRefinedContent': refinedContent.isNotEmpty ? refinedContent : null,
      'audiences': _selectedAudiences.toList(),
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
            .add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
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
    final content =
        _isAIRefined && refinedContent.isNotEmpty ? refinedContent : originalContent;

    if (title.isEmpty || content.isEmpty || _selectedAudiences.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const ErrorNotification(
              message: 'Title, content, and at least one target audience are required to post'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

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
          currentUserRole = ((userData['role'] as String?) ?? 'official').toLowerCase();
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
                OutlineButton(
                  text: 'Cancel',
                  onPressed: () => Navigator.of(context).pop('cancel'),
                ),
                OutlineButton(
                  text: 'Post only',
                  onPressed: () => Navigator.of(context).pop('post_only'),
                ),
                CustomButton(
                  text: 'Post and send push',
                  isFullWidth: false,
                  onPressed: () => Navigator.of(context).pop('post_and_push'),
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

    if (choice == null || choice == 'cancel') return;
      
      final announcementRef =
          await FirebaseFirestore.instance.collection('announcements').add({
        'title': title,
        'content': content,
        'originalContent': originalContent,
        'aiRefinedContent': refinedContent.isNotEmpty ? refinedContent : null,
        'audiences': _selectedAudiences.toList(),
        'status': status,
        'postedBy': postedBy,
        if (postedByPosition != null && postedByPosition.isNotEmpty) 'postedByPosition': postedByPosition,
        if (postedByUserId != null) 'postedByUserId': postedByUserId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      if (!mounted) return;

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
              msg = 'No residents matched the selected audiences. Check User Management: role=resident, approved, active, and Demographic category (categories array) matches the chosen audiences.';
            } else {
              msg = 'No valid tokens. ${result.userCount} resident(s) matched but none have FCM tokens. Ensure the mobile app has been opened after login on the target device(s).';
            }
          } else {
            msg = 'Push sent: ${result.successCount}/${result.tokenCount} token(s).';
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
            child: SuccessNotification(
              message: successMessage,
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
          content: ErrorNotification(message: 'Failed to post announcement: $e'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
            onNavigate: _navigateTo,
          ),
          // Main content
          Expanded(
            child: Container(
              color: AppColors.white,
              child: Column(
                children: [
                  // Top header with user profile
                  Container(
                    color: AppColors.white,
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Announcements',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkGrey,
                          ),
                        ),
                        const UserHeader(),
                      ],
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
          bottom: BorderSide(
            color: AppColors.inputBackground,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildTab('Compose', 0),
          const SizedBox(width: 32),
          _buildTab('Draft', 1),
          const SizedBox(width: 32),
          _buildTab('Posts', 2),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isActive = _activeTabIndex == index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeTabIndex = index;
          });
          if (index == 2) _loadPublishedAnnouncements();
        },
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
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.darkGrey,
              ),
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
            height: 150,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F1F1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _contentController,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.darkGrey,
              ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.aiRefinedBorder,
                  width: 2,
                ),
              ),
              child: TextField(
                controller: _aiRefinedController,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.darkGrey,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(15),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
          // Suggested Audiences section (always visible so "Suggest demographic" works without refining)
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
                    final isAlreadySelected = _selectedAudiences.contains(audience);
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          if (!isAlreadySelected) {
                            _handleAddSuggestedAudience(audience);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            border: Border.all(
              color: AppColors.mediumGrey,
              width: 1,
            ),
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
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _handlePostAnnouncement,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            // Show different text for OFFICIAL (pending approval) vs SUPER ADMIN (direct publish)
            _currentUserRole == 'super_admin' ? 'Post Announcement' : 'Submit for Approval',
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
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.mediumGrey,
            ),
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
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _publishedAnnouncements.length,
              itemBuilder: (context, index) {
                final a = _publishedAnnouncements[index];
                final id = a['id'] as String;
                final title = a['title'] as String? ?? '';
                final createdAt = a['createdAt'] as DateTime?;
                final dateStr = createdAt != null
                    ? createdAt.toIso8601String().substring(0, 16).replaceFirst('T', ' ')
                    : '—';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.dashboardInnerBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.inputBackground),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title.isNotEmpty ? title : 'Untitled',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.darkGrey,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dateStr,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.mediumGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 120,
                          child: OutlineButton(
                            text: 'View readers',
                            onPressed: () => _showViewReadersModal(id, title),
                            isFullWidth: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showViewReadersModal(String announcementId, String title) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('announcements')
        .doc(announcementId)
        .collection('views')
        .get();
    final readers = snapshot.docs.map((doc) {
      final d = doc.data();
      final viewedAt = _parseTimestamp(d['viewedAt']);
      return {
        'userId': d['userId'] as String? ?? doc.id,
        'viewedAt': viewedAt,
      };
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
                            r['fullName'] as String? ?? r['userId'] as String? ?? '',
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
}

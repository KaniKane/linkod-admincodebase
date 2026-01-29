import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/user_header.dart';
import '../widgets/audience_tag.dart';
import '../widgets/draft_item.dart';
import '../widgets/success_notification.dart';
import '../widgets/draft_saved_notification.dart';
import '../models/announcement_draft.dart';
import '../utils/app_colors.dart';
import 'dashboard_screen.dart';
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
  final List<String> _suggestedAudiences = ['Senior', 'PWD'];

  // Drafts loaded from Firestore
  List<AnnouncementDraft> _drafts = [];

  // Currently edited draft id (if any)
  String? _currentDraftId;

  final List<String> _audienceOptions = [
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

  void _handleRefineWithAI() {
    final original = _contentController.text.trim();
    if (original.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter content before refining.'),
        ),
      );
      return;
    }

    setState(() {
      _isAIRefined = true;
      // Simple placeholder refinement: copy original content.
      // In real implementation, this would be replaced by an AI-generated version.
      _aiRefinedController.text = original;
    });
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
      _contentController.text = draft.content;
      _selectedAudiences = Set.from(draft.selectedAudiences);
      _isAIRefined = draft.aiRefinedContent != null;
      if (draft.aiRefinedContent != null) {
        _aiRefinedController.text = draft.aiRefinedContent!;
      } else {
        _aiRefinedController.clear();
      }
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
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
              child: const Text(
                'Delete',
                style: TextStyle(color: AppColors.deleteRed),
              ),
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

  void _handleSaveDraft() async {
    final title = _titleController.text.trim();
    final originalContent = _contentController.text.trim();
    final refinedContent = _aiRefinedController.text.trim();
    final content =
        _isAIRefined && refinedContent.isNotEmpty ? refinedContent : originalContent;

    if (title.isEmpty || content.isEmpty || _selectedAudiences.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Title, content, and at least one target audience are required to save draft'),
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
        SnackBar(content: Text('Failed to save draft: $e')),
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
        const SnackBar(
          content:
              Text('Title, content, and at least one target audience are required to post'),
        ),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('announcements').add({
        'title': title,
        'content': content,
        'originalContent': originalContent,
        'aiRefinedContent': refinedContent.isNotEmpty ? refinedContent : null,
        'audiences': _selectedAudiences.toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'published',
      });

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
              message: 'Announcement is posted successfully',
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
        SnackBar(content: Text('Failed to post announcement: $e')),
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
                                  : _buildDraftTab(),
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
          // AI Refine button
          _buildAIButton(),
          // AI-Refined Version section
          if (_isAIRefined) ...[
            const SizedBox(height: 32),
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
            // Suggested Audiences section
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
                    'Based on your content, we recommend targeting these groups:',
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
          ],
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
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _handleRefineWithAI,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(25),
          ),
          child: const Text(
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
          child: const Text(
            'Post Announcement',
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
}

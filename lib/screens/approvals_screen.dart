import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/user_header.dart';
import '../widgets/custom_tabs.dart';
import '../widgets/custom_button.dart';
import '../widgets/outline_button.dart';
import '../widgets/dialog_container.dart';
import '../widgets/error_notification.dart';
import '../widgets/success_notification.dart';
import '../api/announcement_backend_api.dart';
import 'dashboard_screen.dart';
import 'announcements_screen.dart';
import 'user_management_screen.dart';

/// Approvals screen: Post Approvals, Marketplace Approvals, Errand Approvals.
/// Human-in-the-loop: Admin is the final decision maker (Facebook-style review).
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  int _activeTabIndex = 0;
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _pendingAnnouncements = [];
  List<Map<String, dynamic>> _pendingProducts = [];
  List<Map<String, dynamic>> _pendingTasks = [];
  
  // Current user role for permission checks
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadCurrentUserRole();
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

  void _navigateTo(String route) {
    if (route == '/dashboard') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    } else if (route == '/announcements') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AnnouncementsScreen()),
      );
    } else if (route == '/user-management') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const UserManagementScreen()),
      );
    } else if (route == '/approvals') {
      // Already here
    }
  }

  static DateTime? _parseTimestamp(dynamic t) {
    if (t == null) return null;
    if (t is Timestamp) return t.toDate();
    if (t is DateTime) return t;
    return null;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await Future.wait([
        _loadPendingAnnouncements(),
        _loadPendingProducts(),
        _loadPendingTasks(),
      ]);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPendingAnnouncements() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('announcements')
        .where('status', isEqualTo: 'Pending')
        .get();
    final list = snapshot.docs.map((doc) {
      final d = doc.data();
      return {
        'id': doc.id,
        'title': d['title'] as String? ?? '',
        'content': d['content'] as String? ?? '',
        'postedBy': d['postedBy'] as String? ?? '',
        'createdAt': _parseTimestamp(d['createdAt']),
      };
    }).toList();
    list.sort((a, b) {
      final aT = a['createdAt'] as DateTime? ?? DateTime(0);
      final bT = b['createdAt'] as DateTime? ?? DateTime(0);
      return bT.compareTo(aT);
    });
    _pendingAnnouncements = list;
  }

  Future<void> _loadPendingProducts() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('products')
        .where('status', isEqualTo: 'Pending')
        .get();
    final list = snapshot.docs.map((doc) {
      final d = doc.data();
      final imageUrls = d['imageUrls'] as List<dynamic>?;
      return {
        'id': doc.id,
        'title': d['title'] as String? ?? '',
        'description': d['description'] as String? ?? '',
        'sellerName': d['sellerName'] as String? ?? '',
        'category': d['category'] as String? ?? 'General',
        'createdAt': _parseTimestamp(d['createdAt']),
        'imageUrls': imageUrls?.map((e) => e.toString()).toList() ?? <String>[],
      };
    }).toList();
    list.sort((a, b) {
      final aT = a['createdAt'] as DateTime? ?? DateTime(0);
      final bT = b['createdAt'] as DateTime? ?? DateTime(0);
      return bT.compareTo(aT);
    });
    _pendingProducts = list;
  }

  Future<void> _loadPendingTasks() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('tasks')
        .where('approvalStatus', isEqualTo: 'Pending')
        .get();
    final list = snapshot.docs.map((doc) {
      final d = doc.data();
      return {
        'id': doc.id,
        'title': d['title'] as String? ?? '',
        'description': d['description'] as String? ?? '',
        'requesterName': d['requesterName'] as String? ?? '',
        'createdAt': _parseTimestamp(d['createdAt']),
      };
    }).toList();
    list.sort((a, b) {
      final aT = a['createdAt'] as DateTime? ?? DateTime(0);
      final bT = b['createdAt'] as DateTime? ?? DateTime(0);
      return bT.compareTo(aT);
    });
    _pendingTasks = list;
  }

  Future<void> _markAsApproved(String collection, String id) async {
    try {
      final updates = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
      if (collection == 'tasks') {
        updates['approvalStatus'] = 'Approved';
      } else {
        updates['status'] = 'Approved';
      }
      await FirebaseFirestore.instance.collection(collection).doc(id).update(updates);

      // When approving an announcement, send push now (official's post was Pending; push was not sent on submit).
      if (collection == 'announcements' && mounted) {
        try {
          final doc = await FirebaseFirestore.instance.collection('announcements').doc(id).get();
          if (doc.exists) {
            final d = doc.data() ?? {};
            final title = d['title'] as String? ?? '';
            final content = d['content'] as String? ?? '';
            final audiences = (d['audiences'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
            final postedByUserId = d['postedByUserId'] as String?;
            final body = content.length > 140 ? '${content.substring(0, 140)}...' : content;
            await sendAnnouncementPush(
              announcementId: id,
              title: title,
              body: body,
              audiences: audiences,
              requestedByUserId: postedByUserId,
            );
          }
        } catch (pushError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: ErrorNotification(message: 'Approved; push send failed: $pushError'),
                backgroundColor: Colors.transparent,
                elevation: 0,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const SuccessNotification(message: 'Approved successfully'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ErrorNotification(message: 'Failed to approve: $e'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _markAsDeclined(String collection, String id) async {
    try {
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (collection == 'tasks') {
        updates['approvalStatus'] = 'Declined';
      } else {
        updates['status'] = 'Declined';
      }
      await FirebaseFirestore.instance.collection(collection).doc(id).update(updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const SuccessNotification(message: 'Declined'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ErrorNotification(message: 'Failed to decline: $e'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showPostDetailModal(Map<String, dynamic> a) {
    final id = a['id'] as String;
    final title = a['title'] as String? ?? '';
    final content = a['content'] as String? ?? '';
    final postedBy = a['postedBy'] as String? ?? '';
    final createdAt = a['createdAt'] as DateTime?;
    final dateStr = createdAt != null ? createdAt.toIso8601String().substring(0, 16) : '—';
    showDialog(
      context: context,
      builder: (ctx) => DialogContainer(
        title: title.isEmpty ? 'Post detail' : title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Posted by', postedBy),
            _detailRow('Date', dateStr),
            const SizedBox(height: 8),
            const Text('Content', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 4),
            Text(content, style: const TextStyle(fontSize: 14)),
          ],
        ),
        actions: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            DialogActionButton(
              label: 'Close',
              onPressed: () => Navigator.pop(ctx),
            ),
            // Approve/Decline: SUPER ADMIN only
            if (_currentUserRole == 'super_admin') ...[
              const SizedBox(width: 12),
              DialogActionButton(
                label: 'Decline',
                isDestructive: true,
                onPressed: () {
                  Navigator.pop(ctx);
                  _markAsDeclined('announcements', id);
                },
              ),
              const SizedBox(width: 12),
              DialogActionButton(
                label: 'Approve',
                isPrimary: true,
                onPressed: () {
                  Navigator.pop(ctx);
                  _markAsApproved('announcements', id);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showProductDetailModal(Map<String, dynamic> p) {
    final id = p['id'] as String;
    final title = p['title'] as String? ?? '';
    final description = p['description'] as String? ?? '';
    final sellerName = p['sellerName'] as String? ?? '';
    final category = p['category'] as String? ?? 'General';
    final createdAt = p['createdAt'] as DateTime?;
    final dateStr = createdAt != null ? createdAt.toIso8601String().substring(0, 16) : '—';
    final imageUrls = (p['imageUrls'] as List<dynamic>?)?.map((e) => e.toString()).where((s) => s.isNotEmpty).toList() ?? <String>[];
    showDialog(
      context: context,
      builder: (ctx) => DialogContainer(
        title: title.isEmpty ? 'Product detail' : title,
        maxWidth: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrls.isNotEmpty) ...[
              SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: imageUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      imageUrls[i],
                      width: 160,
                      height: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 160,
                        height: 160,
                        color: AppColors.inputBackground,
                        child: const Icon(Icons.image_not_supported_outlined, color: AppColors.lightGrey, size: 40),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _detailRow('Seller', sellerName),
            _detailRow('Category', category),
            _detailRow('Posted', dateStr),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 4),
              Text(description, style: const TextStyle(fontSize: 14)),
            ],
            if (category.contains('Health') || category.contains('Wellness'))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.suggestedAudienceBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.mediumGrey),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Health & Wellness: medicines must be strictly checked before approval.',
                          style: TextStyle(fontSize: 12, color: AppColors.darkGrey),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        actions: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            DialogActionButton(
              label: 'Close',
              onPressed: () => Navigator.pop(ctx),
            ),
            // Approve/Decline: SUPER ADMIN only
            if (_currentUserRole == 'super_admin') ...[
              const SizedBox(width: 12),
              DialogActionButton(
                label: 'Decline',
                isDestructive: true,
                onPressed: () {
                  Navigator.pop(ctx);
                  _markAsDeclined('products', id);
                },
              ),
              const SizedBox(width: 12),
              DialogActionButton(
                label: 'Approve',
                isPrimary: true,
                onPressed: () {
                  Navigator.pop(ctx);
                  _markAsApproved('products', id);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showTaskDetailModal(Map<String, dynamic> t) {
    final id = t['id'] as String;
    final title = t['title'] as String? ?? '';
    final description = t['description'] as String? ?? '';
    final requesterName = t['requesterName'] as String? ?? '';
    final createdAt = t['createdAt'] as DateTime?;
    final dateStr = createdAt != null ? createdAt.toIso8601String().substring(0, 16) : '—';
    showDialog(
      context: context,
      builder: (ctx) => DialogContainer(
        title: title.isEmpty ? 'Errand detail' : title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Posted by', requesterName),
            _detailRow('Date', dateStr),
            const SizedBox(height: 8),
            const Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 4),
            Text(description, style: const TextStyle(fontSize: 14)),
          ],
        ),
        actions: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            DialogActionButton(
              label: 'Close',
              onPressed: () => Navigator.pop(ctx),
            ),
            // Approve/Decline: SUPER ADMIN only
            if (_currentUserRole == 'super_admin') ...[
              const SizedBox(width: 12),
              DialogActionButton(
                label: 'Decline',
                isDestructive: true,
                onPressed: () {
                  Navigator.pop(ctx);
                  _markAsDeclined('tasks', id);
                },
              ),
              const SizedBox(width: 12),
              DialogActionButton(
                label: 'Approve',
                isPrimary: true,
                onPressed: () {
                  Navigator.pop(ctx);
                  _markAsApproved('tasks', id);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.lightGrey))),
          Expanded(child: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 14))),
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
    
    // Fetch user names for each reader
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
          // If fetch fails, use userId as fallback
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
            ? const Text('No readers yet.', style: TextStyle(color: AppColors.mediumGrey))
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
                        Text(viewedStr, style: const TextStyle(fontSize: 12, color: AppColors.mediumGrey)),
                      ],
                    ),
                  );
                },
              ),
        actions: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(width: 110, child: OutlineButton(text: 'Close', onPressed: () => Navigator.of(context).pop(), isFullWidth: true)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Row(
        children: [
          AppSidebar(
            currentRoute: '/approvals',
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
                        const Text(
                          'Approvals',
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
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.dashboardInnerBg,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                            child: CustomTabs(
                              tabs: const [
                                'Post Approvals',
                                'Marketplace Approvals',
                                'Errand Approvals',
                              ],
                              activeIndex: _activeTabIndex,
                              onTabChanged: (i) => setState(() => _activeTabIndex = i),
                            ),
                          ),
                          if (_errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.errorBannerBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(_errorMessage!, style: const TextStyle(color: AppColors.deleteRed)),
                              ),
                            ),
                          Expanded(
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
                                : SingleChildScrollView(
                                    padding: const EdgeInsets.all(32),
                                    child: _buildTabContent(),
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

  Widget _buildTabContent() {
    switch (_activeTabIndex) {
      case 0:
        return _buildPostApprovals();
      case 1:
        return _buildMarketplaceApprovals();
      case 2:
        return _buildErrandApprovals();
      default:
        return const SizedBox();
    }
  }

  Widget _buildPostApprovals() {
    if (_pendingAnnouncements.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Text('No pending announcements.', style: TextStyle(color: AppColors.mediumGrey)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Announcements awaiting approval',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.darkGrey),
        ),
        const SizedBox(height: 16),
        ..._pendingAnnouncements.map((a) {
          final id = a['id'] as String;
          final title = a['title'] as String;
          final excerpt = (a['content'] as String? ?? '').length > 80
              ? '${(a['content'] as String).substring(0, 80)}...'
              : (a['content'] as String? ?? '');
          final postedBy = a['postedBy'] as String? ?? '';
          final createdAt = a['createdAt'] as DateTime?;
          final dateStr = createdAt != null ? '${createdAt.toIso8601String().substring(0, 10)}' : '—';
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: AppColors.shadowColor, blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(excerpt, style: const TextStyle(fontSize: 13, color: AppColors.mediumGrey), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text('By $postedBy · $dateStr', style: const TextStyle(fontSize: 12, color: AppColors.lightGrey)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  height: 32,
                  child: OutlineButton(
                    text: 'View',
                    onPressed: () => _showPostDetailModal(a),
                    isFullWidth: true,
                  ),
                ),
                // View Readers: SUPER ADMIN and OFFICIAL only
                if (_currentUserRole == 'super_admin' || _currentUserRole == 'official') ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    height: 32,
                    child: OutlineButton(
                      text: 'View Readers',
                      onPressed: () => _showViewReadersModal(id, title),
                      isFullWidth: true,
                    ),
                  ),
                ],
                // Approve button: SUPER ADMIN only
                if (_currentUserRole == 'super_admin') ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    height: 32,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _markAsApproved('announcements', id),
                      child: const Text('Approve'),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMarketplaceApprovals() {
    if (_pendingProducts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Text('No pending marketplace items.', style: TextStyle(color: AppColors.mediumGrey)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Marketplace items awaiting approval',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.darkGrey),
        ),
        const SizedBox(height: 16),
        ..._pendingProducts.map((p) {
          final id = p['id'] as String;
          final title = p['title'] as String;
          final sellerName = p['sellerName'] as String? ?? '—';
          final category = p['category'] as String? ?? 'General';
          final createdAt = p['createdAt'] as DateTime?;
          final dateStr = createdAt != null ? '${createdAt.toIso8601String().substring(0, 10)}' : '—';
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: AppColors.shadowColor, blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      Text('$sellerName · $category · $dateStr', style: const TextStyle(fontSize: 13, color: AppColors.mediumGrey)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 90,
                  height: 32,
                  child: OutlineButton(
                    text: 'View',
                    onPressed: () => _showProductDetailModal(p),
                    isFullWidth: true,
                  ),
                ),
                // Approve button: SUPER ADMIN only
                if (_currentUserRole == 'super_admin') ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    height: 32,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _markAsApproved('products', id),
                      child: const Text('Approve'),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildErrandApprovals() {
    if (_pendingTasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Text('No pending errands.', style: TextStyle(color: AppColors.mediumGrey)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Errands awaiting approval',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.darkGrey),
        ),
        const SizedBox(height: 16),
        ..._pendingTasks.map((t) {
          final id = t['id'] as String;
          final title = t['title'] as String;
          final requesterName = t['requesterName'] as String? ?? '—';
          final createdAt = t['createdAt'] as DateTime?;
          final dateStr = createdAt != null ? '${createdAt.toIso8601String().substring(0, 10)}' : '—';
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: AppColors.shadowColor, blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      Text('$requesterName · $dateStr', style: const TextStyle(fontSize: 13, color: AppColors.mediumGrey)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 90,
                  height: 32,
                  child: OutlineButton(
                    text: 'View',
                    onPressed: () => _showTaskDetailModal(t),
                    isFullWidth: true,
                  ),
                ),
                // Approve button: SUPER ADMIN only
                if (_currentUserRole == 'super_admin') ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    height: 32,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _markAsApproved('tasks', id),
                      child: const Text('Approve'),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}

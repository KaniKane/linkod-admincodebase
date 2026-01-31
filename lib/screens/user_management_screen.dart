import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/user_header.dart';
import '../widgets/custom_tabs.dart';
import '../widgets/search_bar.dart';
import '../widgets/custom_button.dart';
import '../widgets/accept_decline_buttons.dart';
import '../widgets/audience_tag.dart';
import '../utils/app_colors.dart';
import 'dashboard_screen.dart';
import 'announcements_screen.dart';
import 'login_screen.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  int _activeTabIndex = 0;
  final _searchController = TextEditingController();
  int _currentPage = 1;
  int _itemsPerPage = 20;
  final Set<int> _selectedIndices = {};

  bool _isLoading = false;
  String? _errorMessage;

  // Users data (loaded from Firestore)
  List<Map<String, String>> _users = [];

  // Admins data (loaded from Firestore)
  List<Map<String, String>> _admins = [];

  // Awaiting Approval data (loaded from Firestore)
  List<Map<String, String>> _awaitingApproval = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final usersSnapshot =
          await FirebaseFirestore.instance.collection('users').get();
      final awaitingSnapshot =
          await FirebaseFirestore.instance.collection('awaitingApproval').get();

      final loadedUsers = <Map<String, String>>[];
      final loadedAdmins = <Map<String, String>>[];
      final loadedAwaiting = <Map<String, String>>[];

      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final fullName = (data['fullName'] ?? '') as String;
        final phoneNumber = (data['phoneNumber'] ?? '') as String;
        final role = ((data['role'] ?? '') as String).toLowerCase();
        final position = (data['position'] ?? '') as String;
        final demographicCategory =
            (data['category'] ?? data['demographicCategory'] ?? '') as String;

        // Schema: role is official | resident | vendor; admin panel shows "Admin" for official
        if (role == 'admin' || role == 'official') {
          loadedAdmins.add({
            'id': doc.id,
            'name': fullName.isNotEmpty ? fullName : 'Unnamed admin',
            'phone': phoneNumber,
            'position': position.isNotEmpty ? position : 'Admin',
          });
        } else {
          loadedUsers.add({
            'id': doc.id,
            'name': fullName.isNotEmpty ? fullName : 'Unnamed user',
            'phone': phoneNumber,
            'category': demographicCategory.isNotEmpty
                ? demographicCategory
                : (role.isNotEmpty ? role : 'User'),
          });
        }
      }

      for (final doc in awaitingSnapshot.docs) {
        final data = doc.data();
        final fullName = (data['fullName'] ?? '') as String;
        final phoneNumber = (data['phoneNumber'] ?? '') as String;
        final role = ((data['role'] ?? '') as String).toLowerCase();
        final position = (data['position'] ?? '') as String;
        final category =
            (data['category'] ?? data['demographicCategory'] ?? '') as String;

        loadedAwaiting.add({
          'id': doc.id,
          'name': fullName.isNotEmpty ? fullName : 'Unnamed user',
          'phone': phoneNumber,
          'category': category.isNotEmpty
              ? category
              : (role == 'admin' || role == 'official'
                  ? (position.isNotEmpty ? position : 'Admin')
                  : (role.isNotEmpty ? role : 'User')),
          'role': role,
          'position': position,
        });
      }

      setState(() {
        _users = loadedUsers;
        _admins = loadedAdmins;
        _awaitingApproval = loadedAwaiting;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load accounts: $e';
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    }
  }

  int get _totalRecords {
    switch (_activeTabIndex) {
      case 0:
        return _users.length;
      case 1:
        return _admins.length;
      case 2:
        return _awaitingApproval.length;
      default:
        return 0;
    }
  }

  int get _totalPages => (_totalRecords / _itemsPerPage).ceil();

  void _handlePreviousPage() {
    if (_currentPage > 1) {
      setState(() {
        _currentPage--;
      });
    }
  }

  void _handleNextPage() {
    if (_currentPage < _totalPages) {
      setState(() {
        _currentPage++;
      });
    }
  }

  void _handleItemsPerPageChange(String? value) {
    if (value != null) {
      setState(() {
        _itemsPerPage = int.parse(value);
        _currentPage = 1;
      });
    }
  }

  void _handleSelectAll(bool? value) {
    setState(() {
      if (value == true) {
        _selectedIndices.clear();
        for (int i = 0; i < _awaitingApproval.length; i++) {
          _selectedIndices.add(i);
        }
      } else {
        _selectedIndices.clear();
      }
    });
  }

  void _handleSelectItem(int index, bool? value) {
    setState(() {
      if (value == true) {
        _selectedIndices.add(index);
      } else {
        _selectedIndices.remove(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Row(
        children: [
          // Sidebar
          AppSidebar(
            currentRoute: '/user-management',
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
                          'User Management',
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
                            child: Column(
                              children: [
                                // Action bar (search + add button)
                                if (_activeTabIndex == 2) // Awaiting Approval tab
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
                                    child: const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Approval Request',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.darkGrey,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: CustomSearchBar(
                                            placeholder: _activeTabIndex == 0
                                                ? 'Search user'
                                                : 'Search admin',
                                            controller: _searchController,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        CustomButton(
                                          text: _activeTabIndex == 0
                                              ? 'Add New User'
                                              : 'Add New Admin',
                                          onPressed: () => _showAddAccountDialog(
                                            isAdmin: _activeTabIndex == 1,
                                          ),
                                          isFullWidth: false,
                                        ),
                                      ],
                                    ),
                                  ),
                                // Table content
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.symmetric(horizontal: 32),
                                    child: _isLoading
                                        ? const Padding(
                                            padding: EdgeInsets.only(top: 48),
                                            child: Center(
                                              child: CircularProgressIndicator(),
                                            ),
                                          )
                                        : Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              if (_errorMessage != null) ...[
                                                Text(
                                                  _errorMessage!,
                                                  style: const TextStyle(
                                                    color: Colors.red,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                              ],
                                              _buildTable(),
                                            ],
                                          ),
                                  ),
                                ),
                                // Footer
                                Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: _buildTableFooter(),
                                ),
                              ],
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
          _buildTab('Users', 0),
          const SizedBox(width: 32),
          _buildTab('Admins', 1),
          const SizedBox(width: 32),
          _buildTab('Awaiting Approval', 2),
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
            _currentPage = 1;
            _selectedIndices.clear();
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

  Widget _buildTable() {
    switch (_activeTabIndex) {
      case 0:
        return _buildUsersTable();
      case 1:
        return _buildAdminsTable();
      case 2:
        return _buildAwaitingApprovalTable();
      default:
        return const SizedBox();
    }
  }

  Future<void> _showAddAccountDialog({required bool isAdmin}) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController();
    final roleController = TextEditingController(text: isAdmin ? 'admin' : 'user');
    // For selectable position / demographic options
    final Set<String> selectedCategories = {};
    String? selectedPosition;
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: Form(
                  key: formKey,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 520),
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
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            isAdmin ? 'Add New Admin' : 'Add New User',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.loginGreen,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildDialogTextField(
                            label: 'Full Name',
                            controller: nameController,
                            validator: (value) =>
                                value == null || value.trim().isEmpty ? 'Name is required' : null,
                          ),
                          const SizedBox(height: 16),
                          _buildDialogTextField(
                            label: 'Phone Number',
                            controller: phoneController,
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'Phone number is required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _buildDialogTextField(
                            label: 'Password',
                            controller: passwordController,
                            obscureText: true,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Password is required';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          if (isAdmin)
                            _buildPositionSelector(
                              selectedPosition: selectedPosition,
                              onSelect: (value) {
                                setState(() {
                                  selectedPosition = value;
                                });
                              },
                            )
                          else
                            _buildDemographicSelector(
                              selectedCategories: selectedCategories,
                              onToggle: (value) {
                                setState(() {
                                  if (selectedCategories.contains(value)) {
                                    selectedCategories.remove(value);
                                  } else {
                                    selectedCategories.add(value);
                                  }
                                });
                              },
                            ),
                          const SizedBox(height: 16),
                          _buildDialogTextField(
                            label: 'Role',
                            controller: roleController,
                            enabled: false,
                          ),
                          const SizedBox(height: 16),
                          if (dialogError != null) ...[
                            Text(
                              dialogError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.loginGreen,
                                  foregroundColor: AppColors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: isSubmitting
                                    ? null
                                    : () async {
                                        if (!formKey.currentState!.validate()) return;

                                        if (isAdmin && (selectedPosition == null)) {
                                          setState(() {
                                            dialogError = 'Please select a position';
                                          });
                                          return;
                                        }
                                        if (!isAdmin && selectedCategories.isEmpty) {
                                          setState(() {
                                            dialogError =
                                                'Please select at least one demographic category';
                                          });
                                          return;
                                        }

                                        setState(() {
                                          isSubmitting = true;
                                          dialogError = null;
                                        });

                                        try {
                                          final name = nameController.text.trim();
                                          final phone = phoneController.text.trim();
                                          final now = FieldValue.serverTimestamp();
                                          // Schema: role official | resident; email phone@linkod.com
                                          final firestoreRole = isAdmin ? 'official' : 'resident';
                                          final data = <String, dynamic>{
                                            'fullName': name,
                                            'phoneNumber': phone,
                                            'email': phone.isNotEmpty ? '$phone@linkod.com' : null,
                                            'role': firestoreRole,
                                            'createdAt': now,
                                            'updatedAt': now,
                                            'isActive': true,
                                            'isApproved': true,
                                          };
                                          if (isAdmin) {
                                            data['position'] = selectedPosition ?? 'Admin';
                                          } else {
                                            data['category'] = selectedCategories.isEmpty
                                                ? 'User'
                                                : selectedCategories.join(', ');
                                          }

                                          // Direct create uses phone as doc ID (no Auth account; login requires approval flow).
                                          await FirebaseFirestore.instance
                                              .collection('users')
                                              .doc(phone)
                                              .set(data);

                                          if (mounted) {
                                            await _loadAccounts();
                                            Navigator.of(context).pop();
                                          }
                                        } catch (e) {
                                          setState(() {
                                            dialogError = 'Unexpected error: $e';
                                            isSubmitting = false;
                                          });
                                        }
                                      },
                                child: isSubmitting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            AppColors.white,
                                          ),
                                        ),
                                      )
                                    : const Text('Create'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPositionSelector({
    required String? selectedPosition,
    required ValueChanged<String> onSelect,
  }) {
    const barangayPositions = [
      'Barangay Captain',
      'Barangay Secretary',
      'Barangay Treasurer',
      'Barangay Councilor',
      'SK Chairman',
      'Barangay Health Worker',
      'Barangay Tanod',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Barangay Position',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.darkGrey,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: barangayPositions.map((position) {
            final isSelected = selectedPosition == position;
            return AudienceTag(
              label: position,
              isSelected: isSelected,
              onTap: () => onSelect(position),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDemographicSelector({
    required Set<String> selectedCategories,
    required ValueChanged<String> onToggle,
  }) {
    const audienceOptions = [
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Demographic Category',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.darkGrey,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: audienceOptions.map((audience) {
            final isSelected = selectedCategories.contains(audience);
            return AudienceTag(
              label: audience,
              isSelected: isSelected,
              onTap: () => onToggle(audience),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          '${selectedCategories.length} category(ies) selected',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: AppColors.lightGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildDialogTextField({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    bool obscureText = false,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.darkGrey,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            enabled: enabled,
            validator: validator,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.darkGrey,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUsersTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.inputBackground,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.inputBackground.withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Name',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Phone number',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Demographic category',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                SizedBox(width: 60),
              ],
            ),
          ),
          ...List.generate(_users.length, (index) {
            return _buildUserRow(_users[index], index == _users.length - 1);
          }),
        ],
      ),
    );
  }

  Widget _buildAdminsTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.inputBackground,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.inputBackground.withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Name',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Phone number',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Posistion',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                SizedBox(width: 60),
              ],
            ),
          ),
          ...List.generate(_admins.length, (index) {
            return _buildAdminRow(_admins[index], index == _admins.length - 1);
          }),
        ],
      ),
    );
  }

  Widget _buildAwaitingApprovalTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.inputBackground,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.inputBackground.withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Checkbox(
                    value: _selectedIndices.length == _awaitingApproval.length &&
                        _awaitingApproval.isNotEmpty,
                    onChanged: _handleSelectAll,
                  ),
                ),
                const Expanded(
                  flex: 2,
                  child: Text(
                    'Name',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 2,
                  child: Text(
                    'Phone number',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 3,
                  child: Text(
                    'Demographic category',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
                  ),
                ),
                const SizedBox(width: 200),
              ],
            ),
          ),
          ...List.generate(_awaitingApproval.length, (index) {
            return _buildAwaitingApprovalRow(
              _awaitingApproval[index],
              index,
              index == _awaitingApproval.length - 1,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildUserRow(Map<String, String> user, bool isLast) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.inputBackground.withOpacity(0.3),
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(
                  color: AppColors.inputBackground,
                  width: 1,
                ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              user['name']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              user['phone']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              user['category']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionIcon(
                  icon: Icons.edit,
                  onTap: () => _showEditUserDialog(user),
                ),
                const SizedBox(width: 12),
                _ActionIcon(
                  icon: Icons.delete,
                  onTap: () => _deleteUser(user),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminRow(Map<String, String> admin, bool isLast) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.inputBackground.withOpacity(0.3),
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(
                  color: AppColors.inputBackground,
                  width: 1,
                ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              admin['name']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              admin['phone']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              admin['position']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionIcon(
                  icon: Icons.edit,
                  onTap: () => _showEditAdminDialog(admin),
                ),
                const SizedBox(width: 12),
                _ActionIcon(
                  icon: Icons.delete,
                  onTap: () => _deleteAdmin(admin),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAwaitingApprovalRow(
    Map<String, String> user,
    int index,
    bool isLast,
  ) {
    final docId = user['id'] ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.inputBackground.withOpacity(0.3),
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(
                  color: AppColors.inputBackground,
                  width: 1,
                ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Checkbox(
              value: _selectedIndices.contains(index),
              onChanged: (value) => _handleSelectItem(index, value),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              user['name']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              user['phone']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              user['category']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.darkGrey,
              ),
            ),
          ),
          SizedBox(
            width: 200,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionIcon(
                  icon: Icons.edit,
                  onTap: () => _showEditAwaitingDialog(user),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: AcceptDeclineButtons(
                    onAccept: () => _confirmThenApprove(docId, user),
                    onDecline: () => _showDeclineDialog(docId),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmThenApprove(String docId, Map<String, String> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve request'),
        content: const Text(
          'This will create the user\'s account. You will stay logged in. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.loginGreen,
              foregroundColor: AppColors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _approveAwaiting(docId, user);
    }
  }

  Future<void> _approveAwaiting(String docId, Map<String, String> user) async {
    if (docId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('awaitingApproval')
          .doc(docId)
          .get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      final fullName = (data['fullName'] ?? user['name'] ?? '') as String;
      final phone = (data['phoneNumber'] ?? user['phone'] ?? '').toString().trim();
      final password = (data['password'] ?? '') as String?;
      final role = ((data['role'] ?? user['role'] ?? 'user') as String).toLowerCase();
      final position = (data['position'] ?? user['position'] ?? '') as String;
      final category =
          (data['category'] ?? data['demographicCategory'] ?? user['category'] ?? '') as String;

      if (phone.isEmpty) {
        if (mounted) setState(() => _errorMessage = 'Phone number is required to approve.');
        return;
      }
      if (password == null || password.isEmpty || password.length < 6) {
        if (mounted) setState(() => _errorMessage = 'Valid password (6+ chars) required in request to approve.');
        return;
      }

      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      final email = '$phone@linkod.com';
      final now = FieldValue.serverTimestamp();

      // 1) As admin: mark request approved
      await FirebaseFirestore.instance.collection('awaitingApproval').doc(docId).update({
        'status': 'approved',
        'reviewedBy': adminUid,
        'reviewedAt': now,
      });

      // 2) Use a secondary Firebase App so we create the Auth user without signing out the admin
      FirebaseApp secondaryApp;
      try {
        secondaryApp = Firebase.app('AuthHelper');
      } catch (_) {
        secondaryApp = await Firebase.initializeApp(
          name: 'AuthHelper',
          options: Firebase.app().options,
        );
      }
      final authHelper = FirebaseAuth.instanceFor(app: secondaryApp);
      UserCredential? userCredential;
      try {
        userCredential = await authHelper.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          userCredential = await authHelper.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
        } else {
          rethrow;
        }
      }

      final newUser = userCredential?.user;
      if (newUser == null) {
        if (mounted) setState(() => _errorMessage = 'Failed to create or sign in to account.');
        return;
      }
      final uid = newUser.uid;
      final firestoreRole = (role == 'admin') ? 'official' : 'resident';

      // 3) As admin (primary Auth unchanged): create/update users/{uid} and delete awaitingApproval
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'userId': uid,
        'fullName': fullName,
        'phoneNumber': phone,
        'email': email,
        'role': firestoreRole,
        'createdAt': now,
        'updatedAt': now,
        'isActive': true,
        'isApproved': true,
        if (firestoreRole == 'official') 'position': position.isNotEmpty ? position : 'Admin',
        if (firestoreRole == 'resident') 'category': category.isNotEmpty ? category : 'User',
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('awaitingApproval').doc(docId).delete();

      // Sign out from secondary app only so admin stays logged in on primary
      await authHelper.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created successfully.')),
      );
      await _loadAccounts();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to approve request: $e';
        });
      }
    }
  }

  Future<void> _showDeclineDialog(String docId) async {
    if (docId.isEmpty) return;
    final reasonController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Decline request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Optionally add a reason (visible to applicant if you use it):',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Reason for decline (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _declineAwaiting(docId, reasonController.text.trim());
              },
              child: const Text('Decline'),
            ),
          ],
        );
      },
    );
    reasonController.dispose();
  }

  Future<void> _declineAwaiting(String docId, [String? rejectionReason]) async {
    if (docId.isEmpty) return;
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      final updates = <String, dynamic>{
        'status': 'rejected',
        'reviewedAt': FieldValue.serverTimestamp(),
        if (adminUid != null) 'reviewedBy': adminUid,
        if (rejectionReason != null && rejectionReason.isNotEmpty) 'rejectionReason': rejectionReason,
      };
      await FirebaseFirestore.instance
          .collection('awaitingApproval')
          .doc(docId)
          .update(updates);
      await FirebaseFirestore.instance
          .collection('awaitingApproval')
          .doc(docId)
          .delete();
      if (mounted) {
        await _loadAccounts();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to decline request: $e';
        });
      }
    }
  }

  Future<void> _showEditAwaitingDialog(Map<String, String> user) async {
    final nameController = TextEditingController(text: user['name'] ?? '');
    final phoneController = TextEditingController(text: user['phone'] ?? '');
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? dialogError;
    final docId = user['id'] ?? '';
    final isAdmin = ((user['role'] ?? '').toLowerCase() == 'admin' ||
        (user['role'] ?? '').toLowerCase() == 'official');
    final existingCategory = user['category'] ?? '';
    final existingPosition = user['position'] ?? '';
    String? selectedPosition = existingPosition.isNotEmpty ? existingPosition : null;
    Set<String> selectedCategories = existingCategory.isEmpty
        ? <String>{}
        : existingCategory.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();

    await showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
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
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Edit Approval Request',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.loginGreen,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildDialogTextField(
                          label: 'Full Name',
                          controller: nameController,
                          validator: (value) =>
                              value == null || value.trim().isEmpty ? 'Name is required' : null,
                        ),
                        const SizedBox(height: 16),
                        _buildDialogTextField(
                          label: 'Phone Number',
                          controller: phoneController,
                          validator: (value) => value == null || value.trim().isEmpty
                              ? 'Phone number is required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        if (isAdmin)
                          _buildPositionSelector(
                            selectedPosition: selectedPosition,
                            onSelect: (value) => setState(() => selectedPosition = value),
                          )
                        else
                          _buildDemographicSelector(
                            selectedCategories: selectedCategories,
                            onToggle: (value) {
                              setState(() {
                                if (selectedCategories.contains(value)) {
                                  selectedCategories.remove(value);
                                } else {
                                  selectedCategories.add(value);
                                }
                              });
                            },
                          ),
                        const SizedBox(height: 16),
                        if (dialogError != null) ...[
                          Text(
                            dialogError!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.loginGreen,
                                foregroundColor: AppColors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate()) return;
                                      if (isAdmin && selectedPosition == null) {
                                        setState(() => dialogError = 'Please select a position.');
                                        return;
                                      }
                                      if (!isAdmin && selectedCategories.isEmpty) {
                                        setState(() =>
                                            dialogError = 'Please select at least one category.');
                                        return;
                                      }
                                      setState(() {
                                        isSubmitting = true;
                                        dialogError = null;
                                      });

                                      try {
                                        final updates = <String, dynamic>{
                                          'fullName': nameController.text.trim(),
                                          'phoneNumber': phoneController.text.trim(),
                                        };
                                        if (isAdmin) {
                                          updates['position'] =
                                              selectedPosition?.trim().isNotEmpty == true
                                                  ? selectedPosition!
                                                  : 'Admin';
                                        } else {
                                          updates['category'] =
                                              selectedCategories.isEmpty
                                                  ? 'User'
                                                  : selectedCategories.join(', ');
                                        }
                                        await FirebaseFirestore.instance
                                            .collection('awaitingApproval')
                                            .doc(docId)
                                            .update(updates);
                                        if (mounted) {
                                          await _loadAccounts();
                                          Navigator.of(context).pop();
                                        }
                                      } catch (e) {
                                        setState(() {
                                          dialogError = 'Failed to update request: $e';
                                          isSubmitting = false;
                                        });
                                      }
                                    },
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          AppColors.white,
                                        ),
                                      ),
                                    )
                                  : const Text('Save'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showEditUserDialog(Map<String, String> user) async {
    final nameController = TextEditingController(text: user['name'] ?? '');
    final phoneController = TextEditingController(text: user['phone'] ?? '');
    // Initialize selected categories from existing comma-separated string
    final existingCategory = user['category'] ?? '';
    final Set<String> selectedCategories = existingCategory.isEmpty
        ? <String>{}
        : existingCategory
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? dialogError;
    final docId = user['id'] ?? '';

    await showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
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
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Edit User',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.loginGreen,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildDialogTextField(
                          label: 'Full Name',
                          controller: nameController,
                          validator: (value) =>
                              value == null || value.trim().isEmpty ? 'Name is required' : null,
                        ),
                        const SizedBox(height: 16),
                        _buildDialogTextField(
                          label: 'Phone Number',
                          controller: phoneController,
                          validator: (value) => value == null || value.trim().isEmpty
                              ? 'Phone number is required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildDemographicSelector(
                          selectedCategories: selectedCategories,
                          onToggle: (value) {
                            setState(() {
                              if (selectedCategories.contains(value)) {
                                selectedCategories.remove(value);
                              } else {
                                selectedCategories.add(value);
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        if (dialogError != null) ...[
                          Text(
                            dialogError!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.loginGreen,
                                foregroundColor: AppColors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate()) return;
                                      setState(() {
                                        isSubmitting = true;
                                        dialogError = null;
                                      });

                                      try {
                                        await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(docId)
                                            .update({
                                          'fullName': nameController.text.trim(),
                                          'phoneNumber': phoneController.text.trim(),
                                          'category': selectedCategories.isEmpty
                                              ? 'User'
                                              : selectedCategories.join(', '),
                                          'updatedAt': FieldValue.serverTimestamp(),
                                          'role': 'resident',
                                        });
                                        if (mounted) {
                                          await _loadAccounts();
                                          Navigator.of(context).pop();
                                        }
                                      } catch (e) {
                                        setState(() {
                                          dialogError = 'Failed to update user: $e';
                                          isSubmitting = false;
                                        });
                                      }
                                    },
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          AppColors.white,
                                        ),
                                      ),
                                    )
                                  : const Text('Save'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showEditAdminDialog(Map<String, String> admin) async {
    final nameController = TextEditingController(text: admin['name'] ?? '');
    final phoneController = TextEditingController(text: admin['phone'] ?? '');
    String? selectedPosition = admin['position'];
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? dialogError;
    final docId = admin['id'] ?? '';

    await showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
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
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Edit Admin',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.loginGreen,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildDialogTextField(
                          label: 'Full Name',
                          controller: nameController,
                          validator: (value) =>
                              value == null || value.trim().isEmpty ? 'Name is required' : null,
                        ),
                        const SizedBox(height: 16),
                        _buildDialogTextField(
                          label: 'Phone Number',
                          controller: phoneController,
                          validator: (value) => value == null || value.trim().isEmpty
                              ? 'Phone number is required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildPositionSelector(
                          selectedPosition: selectedPosition,
                          onSelect: (value) {
                            setState(() {
                              selectedPosition = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        if (dialogError != null) ...[
                          Text(
                            dialogError!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.loginGreen,
                                foregroundColor: AppColors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate()) return;
                                      setState(() {
                                        isSubmitting = true;
                                        dialogError = null;
                                      });

                                      try {
                                        final positionValue =
                                            (selectedPosition ?? admin['position'] ?? '').trim();
                                        await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(docId)
                                            .update({
                                          'fullName': nameController.text.trim(),
                                          'phoneNumber': phoneController.text.trim(),
                                          'position':
                                              positionValue.isNotEmpty ? positionValue : 'Admin',
                                          'updatedAt': FieldValue.serverTimestamp(),
                                          'role': 'official',
                                        });
                                        if (mounted) {
                                          await _loadAccounts();
                                          Navigator.of(context).pop();
                                        }
                                      } catch (e) {
                                        setState(() {
                                          dialogError = 'Failed to update admin: $e';
                                          isSubmitting = false;
                                        });
                                      }
                                    },
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          AppColors.white,
                                        ),
                                      ),
                                    )
                                  : const Text('Save'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteUser(Map<String, String> user) async {
    final docId = user['id'] ?? '';
    if (docId.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).delete();
      if (mounted) {
        await _loadAccounts();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to delete user: $e';
        });
      }
    }
  }

  Future<void> _deleteAdmin(Map<String, String> admin) async {
    final docId = admin['id'] ?? '';
    if (docId.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).delete();
      if (mounted) {
        await _loadAccounts();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to delete admin: $e';
        });
      }
    }
  }

  Widget _buildTableFooter() {
    final recordText = _activeTabIndex == 2
        ? '$_totalRecords Awaiting Approval'
        : '$_totalRecords Records';

    return Container(
      padding: const EdgeInsets.only(top: 24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.inputBackground,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            recordText,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: AppColors.darkGrey,
            ),
          ),
          Row(
            children: [
              const Text(
                'Show',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: AppColors.darkGrey,
                ),
              ),
              const SizedBox(width: 8),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  width: 60,
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.inputBackground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _itemsPerPage.toString(),
                      isExpanded: true,
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: AppColors.darkGrey,
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.darkGrey,
                      ),
                      items: ['10', '20', '50', '100'].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: _handleItemsPerPageChange,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              _PaginationButton(
                icon: Icons.chevron_left,
                onTap: _handlePreviousPage,
                isEnabled: _currentPage > 1,
              ),
              const SizedBox(width: 16),
              Text(
                'Page $_currentPage of $_totalPages',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: AppColors.darkGrey,
                ),
              ),
              const SizedBox(width: 16),
              _PaginationButton(
                icon: Icons.chevron_right,
                onTap: _handleNextPage,
                isEnabled: _currentPage < _totalPages,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.icon,
    required this.onTap,
  });

  @override
  State<_ActionIcon> createState() => _ActionIconState();
}

class _ActionIconState extends State<_ActionIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Icon(
          widget.icon,
          size: 20,
          color: _isHovered
              ? AppColors.primaryGreen
              : AppColors.darkGrey,
        ),
      ),
    );
  }
}

class _PaginationButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isEnabled;

  const _PaginationButton({
    required this.icon,
    required this.onTap,
    required this.isEnabled,
  });

  @override
  State<_PaginationButton> createState() => _PaginationButtonState();
}

class _PaginationButtonState extends State<_PaginationButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (widget.isEnabled) {
          setState(() => _isHovered = true);
        }
      },
      onExit: (_) {
        if (widget.isEnabled) {
          setState(() => _isHovered = false);
        }
      },
      cursor: widget.isEnabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.isEnabled ? widget.onTap : null,
        child: Icon(
          widget.icon,
          size: 20,
          color: widget.isEnabled
              ? (_isHovered
                  ? AppColors.primaryGreen
                  : AppColors.darkGrey)
              : AppColors.lightGrey,
        ),
      ),
    );
  }
}

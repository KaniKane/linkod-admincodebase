import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../widgets/custom_link.dart';
import '../widgets/draft_saved_notification.dart';
import '../widgets/error_notification.dart';
import 'login_screen.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _selectedPosition;

  bool _isLoading = false;
  String? _errorMessage;
  bool _passwordObscure = true;

  final List<String> _barangayPositions = [
    'Barangay Captain',
    'Barangay Secretary',
    'Barangay Treasurer',
    'Barangay Councilor',
    'SK Chairman',
    'Barangay Health Worker',
    'Barangay Tanod',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();
      final password = _passwordController.text;
      final position = _selectedPosition ?? '';
      final email = '$phone@linkod.com';

      // Create Firebase Auth user so they can log in with same credentials (before or after approval)
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      final uid = userCredential.user?.uid;
      if (uid == null) {
        setState(() => _errorMessage = 'Failed to create account. Please try again.');
        return;
      }

      // Store request in awaitingApproval for admin review (no password; Auth already created)
      await FirebaseFirestore.instance.collection('awaitingApproval').add({
        'uid': uid,
        'fullName': name,
        'phoneNumber': phone,
        'role': 'admin',
        'position': position,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const DraftSavedNotification(
              message: 'Account request submitted for approval. You can log in with your phone and password; access will be granted after approval.'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );

      _navigateToLogin();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        setState(() {
          _errorMessage = 'An account with this phone number already exists. Try logging in or wait for approval.';
        });
      } else {
        setState(() => _errorMessage = e.message ?? 'Sign up failed: ${e.code}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Unexpected error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: [
              AppColors.gradientBottomLeft, // #019E6F
              AppColors.gradientTopRight, // #1FE07A
            ],
          ),
        ),
        child: Row(
          children: [
            // Left branding section
            Expanded(
              flex: 2,
              child: _buildBrandingSection(),
            ),
            // Right sign up card section
            Expanded(
              flex: 1,
              child: Center(
                child: SingleChildScrollView(
                  child: _buildSignUpCard(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandingSection() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo with text positioned below
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo image
                Image.asset(
                  'assets/img/logo/linkod_logo.png',
                  width: 400,
                  height: 400,
                  fit: BoxFit.contain,
                ),
                // Subtitle positioned directly below logo
                Transform.translate(
                  offset: const Offset(140, -160),
                  child: const Text(
                    'Ai-Assisted Barangay-based Social Platform',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.normal,
                      color: AppColors.white,
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

  Widget _buildSignUpCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 450),
      margin: const EdgeInsets.only(left: 60, right: 20, top: 20, bottom: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 50),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              const Text(
                'Request Sign in',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: AppColors.loginGreen,
                ),
              ),
              const SizedBox(height: 40),
              
              // Name Field
              const Text(
                'Name',
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
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextFormField(
                  controller: _nameController,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.darkGrey,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Juan Dela Cruz',
                    hintStyle: TextStyle(
                      fontSize: 16,
                      color: AppColors.lightGrey,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Phone Number Field
              const Text(
                'Phone Number',
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
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextFormField(
                  controller: _phoneController,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Phone number is required';
                    }
                    return null;
                  },
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.darkGrey,
                  ),
                  decoration: const InputDecoration(
                    hintText: '09856231879',
                    hintStyle: TextStyle(
                      fontSize: 16,
                      color: AppColors.lightGrey,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Password Field
              const Text(
                'Password',
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
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextFormField(
                  controller: _passwordController,
                  obscureText: _passwordObscure,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password is required';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.darkGrey,
                  ),
                  decoration: InputDecoration(
                    hintText: '********',
                    hintStyle: const TextStyle(
                      fontSize: 16,
                      color: AppColors.lightGrey,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 15,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordObscure ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.darkGrey,
                        size: 22,
                      ),
                      onPressed: () =>
                          setState(() => _passwordObscure = !_passwordObscure),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Barangay Position Dropdown
              const Text(
                'Barangay Position',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: AppColors.darkGrey,
                ),
              ),
              const SizedBox(height: 8),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.inputBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButtonFormField<String>(
                      value: _selectedPosition,
                      isExpanded: true,
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: AppColors.lightGrey,
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.darkGrey,
                      ),
                      hint: const Text(
                        'Select position',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.lightGrey,
                        ),
                      ),
                      items: _barangayPositions.map((String item) {
                        return DropdownMenuItem<String>(
                          value: item,
                          child: Text(item),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedPosition = value;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select a position';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              
              if (_errorMessage != null) ...[
                ErrorNotification(message: _errorMessage!),
                const SizedBox(height: 12),
              ],

              // Create Admin Button
              _SignUpButton(
                text: 'Create Admin Account',
                onPressed: _isLoading ? null : _handleSignUp,
              ),
              const SizedBox(height: 15),
              
              // Log in link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Already have an account? ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: AppColors.darkGreyAlt,
                    ),
                  ),
                  CustomLink(
                    text: 'Log in',
                    onTap: _navigateToLogin,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignUpButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;

  const _SignUpButton({
    required this.text,
    this.onPressed,
  });

  @override
  State<_SignUpButton> createState() => _SignUpButtonState();
}

class _SignUpButtonState extends State<_SignUpButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            color: _isHovered
                ? AppColors.gradientBottomLeft
                : AppColors.loginGreen,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              widget.text,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

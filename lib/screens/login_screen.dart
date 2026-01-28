import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../widgets/custom_link.dart';
import 'create_account_screen.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final phone = _phoneController.text.trim();
      final password = _passwordController.text;

      // Map phone number to an email-style identifier for Firebase Auth,
      // e.g. "+1234567890" -> "+1234567890@linkod.com"
      final email = '$phone@linkod.com';

      // Sign in with Firebase Authentication
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      final user = userCredential.user;

      if (user == null) {
        setState(() {
          _errorMessage = 'Login failed. Please try again.';
        });
        return;
      }

      // Load profile from Firestore: users/{UID}
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        setState(() {
          _errorMessage =
              'Profile not found. Please contact support or create an account.';
        });
        return;
      }

      final data = userDoc.data() ?? {};
      final role = data['role'] as String? ?? '';

      // Optional: restrict this admin app to admin users only
      if (role.toLowerCase() != 'admin') {
        setState(() {
          _errorMessage =
              'This admin panel is only for admin accounts. Your role is "$role".';
        });
        await FirebaseAuth.instance.signOut();
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const DashboardScreen(),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Login failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToCreateAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateAccountScreen()),
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
            // Right login card section
            Expanded(
              flex: 1,
              child: Center(
                child: SingleChildScrollView(
                  child: _buildLoginCard(),
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

  Widget _buildLoginCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
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
                'Login to Continue',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  color: AppColors.loginGreen,
                ),
              ),
              const SizedBox(height: 50),
              
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
              const SizedBox(height: 25),
              
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
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password is required';
                    }
                    return null;
                  },
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.darkGrey,
                  ),
                  decoration: const InputDecoration(
                    hintText: '************',
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
              const SizedBox(height: 35),

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
              
              // Login Button
              _LoginButton(
                text: 'Login',
                onPressed: _isLoading ? null : _handleLogin,
              ),
              const SizedBox(height: 30),
              
              // Sign up link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Dont have an account? ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: AppColors.darkGreyAlt,
                    ),
                  ),
                  CustomLink(
                    text: 'Sign up',
                    onTap: _navigateToCreateAccount,
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

class _LoginButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;

  const _LoginButton({
    required this.text,
    this.onPressed,
  });

  @override
  State<_LoginButton> createState() => _LoginButtonState();
}

class _LoginButtonState extends State<_LoginButton> {
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

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../services/email_auth_service.dart';
import '../utils/app_colors.dart';
import '../widgets/custom_link.dart';
import '../widgets/draft_saved_notification.dart';
import '../widgets/error_notification.dart';
import '../widgets/outline_button.dart';
import 'login_screen.dart';

enum _SignUpStep { email, otp, profile }

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  _SignUpStep _step = _SignUpStep.email;
  String? _selectedPosition;
  String _selectedUserType = 'admin';
  bool _emailVerified = false;

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
    _emailController.dispose();
    _otpController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String value) {
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return emailRegex.hasMatch(value.trim());
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await EmailAuthService.sendOtp(email: email);
      if (!mounted) return;
      setState(() {
        _step = _SignUpStep.otp;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const DraftSavedNotification(
            message: 'OTP sent. Please check your email.',
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'Failed to send OTP.';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to send OTP: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() {
        _errorMessage = 'Please enter the 6-digit OTP.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await EmailAuthService.verifyOtp(
        email: _emailController.text.trim(),
        otp: otp,
      );
      if (!mounted) return;
      setState(() {
        _emailVerified = true;
        _step = _SignUpStep.profile;
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'Invalid OTP.';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to verify OTP: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_emailVerified) {
      setState(() {
        _errorMessage = 'Please verify your email first.';
      });
      return;
    }
    if (_selectedUserType == 'admin' && _selectedPosition == null) {
      setState(() {
        _errorMessage = 'Please select a barangay position.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await EmailAuthService.createPendingSignup(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        firstName: _firstNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        userType: _selectedUserType,
        requestedRole: _selectedUserType == 'admin' ? 'admin' : 'resident',
        position: _selectedUserType == 'admin' ? (_selectedPosition ?? '') : '',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const DraftSavedNotification(
            message: 'Request submitted. Waiting for admin approval.',
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
        ),
      );

      _navigateToLogin();
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'Sign up failed.';
      });
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

  Widget _buildStepIndicator() {
    final labels = ['Email', 'OTP', 'Profile'];
    final index = _step.index;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(labels.length, (i) {
        final isActive = i == index;
        final isDone = i < index;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDone || isActive
                ? AppColors.loginGreen.withOpacity(0.15)
                : AppColors.inputBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            labels[i],
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDone || isActive
                  ? AppColors.loginGreen
                  : AppColors.mediumGrey,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Email Address',
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
            controller: _emailController,
            validator: (value) {
              if (_step != _SignUpStep.email) return null;
              if (value == null || !_isValidEmail(value)) {
                return 'Valid email is required';
              }
              return null;
            },
            style: const TextStyle(fontSize: 16, color: AppColors.darkGrey),
            decoration: const InputDecoration(
              hintText: 'name@example.com',
              hintStyle: TextStyle(fontSize: 16, color: AppColors.lightGrey),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _SignUpButton(
          text: _isLoading ? 'Sending OTP...' : 'Send OTP',
          onPressed: _isLoading ? null : _sendOtp,
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the OTP sent to ${_emailController.text.trim()}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.mediumGrey,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'OTP Code',
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
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: const TextStyle(fontSize: 16, color: AppColors.darkGrey),
            decoration: const InputDecoration(
              hintText: '123456',
              counterText: '',
              hintStyle: TextStyle(fontSize: 16, color: AppColors.lightGrey),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlineButton(
                text: 'Back',
                onPressed: _isLoading
                    ? null
                    : () => setState(() => _step = _SignUpStep.email),
                isFullWidth: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SignUpButton(
                text: _isLoading ? 'Verifying...' : 'Verify OTP',
                onPressed: _isLoading ? null : _verifyOtp,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProfileStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'First Name',
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
            controller: _firstNameController,
            validator: (value) {
              if (_step != _SignUpStep.profile) return null;
              if (value == null || value.trim().isEmpty) {
                return 'First name is required';
              }
              return null;
            },
            style: const TextStyle(fontSize: 16, color: AppColors.darkGrey),
            decoration: const InputDecoration(
              hintText: 'Juan',
              hintStyle: TextStyle(fontSize: 16, color: AppColors.lightGrey),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Middle Name',
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
            controller: _middleNameController,
            style: const TextStyle(fontSize: 16, color: AppColors.darkGrey),
            decoration: const InputDecoration(
              hintText: 'Santos (optional)',
              hintStyle: TextStyle(fontSize: 16, color: AppColors.lightGrey),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Last Name',
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
            controller: _lastNameController,
            validator: (value) {
              if (_step != _SignUpStep.profile) return null;
              if (value == null || value.trim().isEmpty) {
                return 'Last name is required';
              }
              return null;
            },
            style: const TextStyle(fontSize: 16, color: AppColors.darkGrey),
            decoration: const InputDecoration(
              hintText: 'Dela Cruz',
              hintStyle: TextStyle(fontSize: 16, color: AppColors.lightGrey),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
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
              if (_step != _SignUpStep.profile) return null;
              if (value == null || value.isEmpty) {
                return 'Password is required';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
            style: const TextStyle(fontSize: 16, color: AppColors.darkGrey),
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
        const SizedBox(height: 16),
        const Text(
          'Account Type',
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
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedUserType,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'admin', child: Text('Admin Account')),
                DropdownMenuItem(
                  value: 'resident',
                  child: Text('Resident Account'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedUserType = value;
                  if (value != 'admin') {
                    _selectedPosition = null;
                  }
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_selectedUserType == 'admin') ...[
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
                    style: TextStyle(fontSize: 16, color: AppColors.lightGrey),
                  ),
                  items: _barangayPositions
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item,
                          child: Text(item),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedPosition = value),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: OutlineButton(
                text: 'Back',
                onPressed: _isLoading
                    ? null
                    : () => setState(() => _step = _SignUpStep.otp),
                isFullWidth: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SignUpButton(
                text: _isLoading ? 'Submitting...' : 'Request Sign Up',
                onPressed: _isLoading ? null : _handleSignUp,
              ),
            ),
          ],
        ),
      ],
    );
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
            Expanded(flex: 2, child: _buildBrandingSection()),
            // Right sign up card section
            Expanded(
              flex: 1,
              child: Center(
                child: SingleChildScrollView(child: _buildSignUpCard()),
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
                'Request Sign Up',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: AppColors.loginGreen,
                ),
              ),
              const SizedBox(height: 12),
              _buildStepIndicator(),
              const SizedBox(height: 40),

              if (_step == _SignUpStep.email) _buildEmailStep(),
              if (_step == _SignUpStep.otp) _buildOtpStep(),
              if (_step == _SignUpStep.profile) _buildProfileStep(),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                ErrorNotification(message: _errorMessage!),
                const SizedBox(height: 12),
              ],
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
                  CustomLink(text: 'Log in', onTap: _navigateToLogin),
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

  const _SignUpButton({required this.text, this.onPressed});

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

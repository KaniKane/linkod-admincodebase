import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../widgets/custom_link.dart';
import '../widgets/error_notification.dart';
import 'create_account_screen.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  String? _errorMessage;
  String? _emailFieldError;
  String? _passwordFieldError;
  bool _passwordObscure = true;

  void _clearFieldErrors() {
    if (_emailFieldError == null && _passwordFieldError == null) return;
    setState(() {
      _emailFieldError = null;
      _passwordFieldError = null;
    });
  }

  void _setFieldErrors({String? emailError, String? passwordError}) {
    setState(() {
      _emailFieldError = emailError;
      _passwordFieldError = passwordError;
    });
  }

  String _mapFirebaseAuthErrorToMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'user-not-found':
        return 'No account found for this email.';
      case 'wrong-password':
        return 'Incorrect password. Try again.';
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a few minutes.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection and try again.';
      default:
        return 'Login failed. Please try again.';
    }
  }

  @override
  void initState() {
    super.initState();
    _tryAutoLoginFromExistingSession();
  }

  Future<void> _tryAutoLoginFromExistingSession() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        return;
      }

      final data = userDoc.data() ?? {};
      final accountStatus = (data['accountStatus'] as String? ?? '')
          .toLowerCase();
      final role = (data['role'] as String? ?? '').toLowerCase();

      final isAllowedRole = role == 'super_admin' || role == 'admin';
      final isApproved = accountStatus != 'pending';

      if (!isAllowedRole || !isApproved) {
        await FirebaseAuth.instance.signOut();
        return;
      }

      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
        );
      });
    } catch (_) {
      await FirebaseAuth.instance.signOut();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    _clearFieldErrors();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;

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
        // Check if they signed up but are still pending approval
        final pendingQuery = await FirebaseFirestore.instance
            .collection('awaitingApproval')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (pendingQuery.docs.isNotEmpty) {
          setState(() {
            _errorMessage =
                'Your account is pending approval. You will be notified when an admin approves your request.';
          });
          await FirebaseAuth.instance.signOut();
          return;
        }
        setState(() {
          _errorMessage =
              'Profile not found. Please contact support or create an account.';
        });
        return;
      }

      final data = userDoc.data() ?? {};
      final accountStatus = (data['accountStatus'] as String? ?? '')
          .toLowerCase();
      if (accountStatus == 'pending') {
        setState(() {
          _errorMessage = 'Waiting for admin approval.';
        });
        await FirebaseAuth.instance.signOut();
        return;
      }
      final role = (data['role'] as String? ?? '').toLowerCase();

      // Only Super Admin and Admin can access this panel. Positions (e.g. official, staff) are labels only.
      if (role != 'super_admin' && role != 'admin') {
        setState(() {
          _errorMessage =
              'This admin panel is only for Super Admin and Admin accounts. Your role is "$role".';
        });
        await FirebaseAuth.instance.signOut();
        return;
      }

      if (!mounted) return;
      // Workaround: Firebase Auth on Windows sends channel messages from a
      // non-platform thread after sign-in, which can crash. Defer navigation
      // to the next frame so it runs on the platform thread.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
        );
      });
    } on FirebaseAuthException catch (e) {
      final message = _mapFirebaseAuthErrorToMessage(e);

      if (e.code == 'invalid-email' || e.code == 'user-not-found') {
        _setFieldErrors(emailError: message);
      } else if (e.code == 'wrong-password') {
        _setFieldErrors(passwordError: message);
      } else if (e.code == 'invalid-credential') {
        final email = _emailController.text.trim().toLowerCase();
        try {
          final methods = await FirebaseAuth.instance
              .fetchSignInMethodsForEmail(email);
          if (methods.isEmpty) {
            _setFieldErrors(emailError: 'No account found for this email.');
          } else {
            _setFieldErrors(passwordError: 'Incorrect password. Try again.');
          }
        } catch (_) {
          _setFieldErrors(passwordError: message);
        }
      } else {
        setState(() {
          _errorMessage = message;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Login failed. Please try again.';
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
            Expanded(flex: 2, child: _buildBrandingSection()),
            // Right login card section
            Expanded(
              flex: 1,
              child: Center(
                child: SingleChildScrollView(child: _buildLoginCard()),
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
      margin: const EdgeInsets.only(left: 0, right: 200, top: 20, bottom: 20),
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

              // Email Field
              const Text(
                'Email',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: AppColors.darkGrey,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_errorMessage != null || _emailFieldError != null) {
                      setState(() {
                        _errorMessage = null;
                        _emailFieldError = null;
                      });
                    }
                  },
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) {
                      return 'Email is required';
                    }
                    final isValid = RegExp(
                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                    ).hasMatch(email);
                    if (!isValid) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.darkGrey,
                  ),
                  decoration: InputDecoration(
                    hintText: 'name@example.com',
                    hintStyle: const TextStyle(
                      fontSize: 16,
                      color: AppColors.lightGrey,
                    ),
                    errorText: _emailFieldError,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 25),

              // Password Field
              const Text(
                'Password (min 6 characters)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: AppColors.darkGrey,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextFormField(
                  controller: _passwordController,
                  obscureText: _passwordObscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (!_isLoading) {
                      _handleLogin();
                    }
                  },
                  onChanged: (_) {
                    if (_errorMessage != null || _passwordFieldError != null) {
                      setState(() {
                        _errorMessage = null;
                        _passwordFieldError = null;
                      });
                    }
                  },
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
                    hintText: '************',
                    hintStyle: const TextStyle(
                      fontSize: 16,
                      color: AppColors.lightGrey,
                    ),
                    errorText: _passwordFieldError,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 15,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordObscure
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: AppColors.darkGrey,
                        size: 22,
                      ),
                      onPressed: () =>
                          setState(() => _passwordObscure = !_passwordObscure),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 35),

              if (_errorMessage != null) ...[
                ErrorNotification(message: _errorMessage!),
                const SizedBox(height: 16),
              ],

              // Login Button
              _LoginButton(
                text: 'Login',
                isLoading: _isLoading,
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
                  CustomLink(text: 'Sign up', onTap: _navigateToCreateAccount),
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
  final bool isLoading;

  const _LoginButton({
    required this.text,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  State<_LoginButton> createState() => _LoginButtonState();
}

class _LoginButtonState extends State<_LoginButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (!widget.isLoading) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (!widget.isLoading) setState(() => _isHovered = false);
      },
      cursor: widget.onPressed != null && !widget.isLoading
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.isLoading ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            color: widget.isLoading
                ? AppColors.loginGreen.withOpacity(0.7)
                : (_isHovered
                      ? AppColors.gradientBottomLeft
                      : AppColors.loginGreen),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.white,
                      ),
                    ),
                  )
                : Text(
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

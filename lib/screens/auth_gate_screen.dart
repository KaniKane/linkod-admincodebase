import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import 'admin_shell_screen.dart';
import 'login_screen.dart';

class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  String? _validatedUserId;
  Future<bool>? _validationFuture;

  Future<bool> _validateSession(User user) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        return false;
      }

      final data = userDoc.data() ?? {};
      final accountStatus = (data['accountStatus'] as String? ?? '')
          .toLowerCase();
      final role = (data['role'] as String? ?? '').toLowerCase();

      final isAllowedRole = role == 'super_admin' || role == 'admin';
      final isApproved = accountStatus != 'pending';

      if (!isAllowedRole || !isApproved) {
        await FirebaseAuth.instance.signOut();
        return false;
      }

      return true;
    } catch (_) {
      await FirebaseAuth.instance.signOut();
      return false;
    }
  }

  Future<bool> _getValidationFuture(User user) {
    if (_validatedUserId != user.uid || _validationFuture == null) {
      _validatedUserId = user.uid;
      _validationFuture = _validateSession(user);
    }
    return _validationFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoadingScreen();
        }

        if (snapshot.hasError) {
          return const LoginScreen();
        }

        final user = snapshot.data;
        if (user == null) {
          _validatedUserId = null;
          _validationFuture = null;
          return const LoginScreen();
        }

        return FutureBuilder<bool>(
          future: _getValidationFuture(user),
          builder: (context, validationSnapshot) {
            if (validationSnapshot.connectionState != ConnectionState.done) {
              return const _AuthLoadingScreen();
            }

            final isValidSession = validationSnapshot.data ?? false;
            if (!isValidSession) {
              return const LoginScreen();
            }

            return const AdminShellScreen(initialRoute: '/dashboard');
          },
        );
      },
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: [AppColors.gradientBottomLeft, AppColors.gradientTopRight],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/img/logo/linkod_logo_3.png',
                width: 180,
                height: 180,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 16),
              const Text(
                'Restoring your session...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'services/fcm_token_service.dart';
import 'services/backend_orchestrator.dart';
import 'screens/login_screen.dart';
import 'screens/startup_screen.dart';
import 'utils/app_colors.dart';

/// Development mode flag.
/// 
/// In debug/profile mode, the app does NOT auto-start the packaged backend.
/// Instead, it expects the developer to run the backend manually from source.
/// This preserves the existing developer workflow.
/// 
/// In release mode, the app uses the packaged backend EXE and auto-starts it.
/// 
/// To override this behavior (e.g., test production mode in debug):
/// - Set [forceProductionMode] to true below
/// - Or set the environment variable LINKOD_FORCE_PROD=true
const bool _isDebugMode = kDebugMode || kProfileMode;

/// Force production mode for testing (set to true to test production behavior in debug)
const bool forceProductionMode = false;

/// Determine if we should use production startup orchestration
bool get useProductionMode {
  // Check environment variable override
  const envOverride = String.fromEnvironment('LINKOD_FORCE_PROD');
  if (envOverride.toLowerCase() == 'true') {
    return true;
  }
  
  // Force production flag for testing
  if (forceProductionMode) {
    return true;
  }
  
  // Default: release mode = production, debug = development
  return !_isDebugMode;
}

/// Main entry point
/// 
/// In production (release mode on Windows):
/// 1. Show startup screen that orchestrates backend startup
/// 2. Wait for backend to be healthy
/// 3. Then show login screen
/// 
/// In development (debug mode):
/// 1. Skip backend orchestration
/// 2. Assume backend is running manually from source
/// 3. Go directly to login screen
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase first (required for all modes)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Start FCM token registration (no-op on Windows)
  FcmTokenService.instance.start();

  developer.log(
    'main: Running in ${useProductionMode ? "PRODUCTION" : "DEVELOPMENT"} mode',
    name: 'Main',
  );

  runApp(const MyApp());
}

/// Root application widget
/// 
/// Handles the startup flow based on build mode:
/// - Production: Shows [StartupScreen] first, then navigates to main app
/// - Development: Shows [LoginScreen] directly (assumes manual backend)
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _startupComplete = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LINKod Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2ECC71))
            .copyWith(
              onSurface: AppColors.buttonTextOnLightStrong,
              onSurfaceVariant: AppColors.buttonTextOnLightStrong,
            ),
        useMaterial3: true,
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.buttonTextOnLightStrong,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.buttonTextOnLightStrong,
          ),
        ),
      ),
      home: _buildHomeScreen(),
    );
  }

  /// Build the appropriate home screen based on mode and startup state
  Widget _buildHomeScreen() {
    // In development mode, skip startup orchestration entirely
    if (!useProductionMode) {
      developer.log(
        'MyApp: Development mode - skipping backend orchestration',
        name: 'MyApp',
      );
      return const LoginScreen();
    }

    // In production mode, show startup screen first
    if (!_startupComplete) {
      return StartupScreen(
        onStartupComplete: () {
          developer.log(
            'MyApp: Startup complete, showing main app',
            name: 'MyApp',
          );
          setState(() {
            _startupComplete = true;
          });
        },
        mainScreen: const LoginScreen(),
      );
    }

    // Startup is complete, show the main app
    return const LoginScreen();
  }
}

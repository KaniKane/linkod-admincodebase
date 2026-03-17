import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:linkod_admin/screens/dashboard_screen.dart';

import 'firebase_options.dart';
import 'services/fcm_token_service.dart';
import 'screens/login_screen.dart';
import 'utils/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Start FCM token registration (no-op on Windows).
  FcmTokenService.instance.start();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      home: const LoginScreen(),
    );
  }
}

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/app_colors.dart';
import '../services/backend_orchestrator.dart';

/// Startup screen that orchestrates backend initialization.
///
/// This screen handles:
/// - Checking backend health
/// - Starting packaged backend if needed
/// - Showing loading state with progress indication
/// - Displaying user-friendly error dialogs on failure
/// - Providing retry functionality
///
/// After successful startup, navigates to the main app screen.
class StartupScreen extends StatefulWidget {
  const StartupScreen({
    super.key,
    required this.onStartupComplete,
    required this.mainScreen,
  });

  /// Called when startup completes successfully
  final VoidCallback onStartupComplete;

  /// The main screen widget to show after startup
  final Widget mainScreen;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  late final BackendOrchestrator _orchestrator;
  String _statusMessage = 'Starting up...';
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String? _logsPath;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _orchestrator = BackendOrchestrator();
    _startStartupSequence();
  }

  /// Main startup sequence
  Future<void> _startStartupSequence() async {
    try {
      setState(() {
        _statusMessage = 'Setting up backend service...';
        _progress = 10;
      });

      final result = await _orchestrator.ensureBackendRunning();

      if (result.success) {
        setState(() {
          _statusMessage = 'Backend ready!';
          _progress = 100;
        });

        // Small delay so user sees "Ready!" briefly
        await Future.delayed(const Duration(milliseconds: 300));

        if (mounted) {
          widget.onStartupComplete();
        }
      } else {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = result.errorMessage ??
              'Failed to start the backend service. Please try again or contact support.';
          _logsPath = result.logsPath;
        });
      }
    } catch (e, stackTrace) {
      developer.log(
        'StartupScreen: Unexpected error during startup: $e',
        name: 'StartupScreen',
        error: e,
        stackTrace: stackTrace,
      );
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage =
            'An unexpected error occurred during startup. Please try again.';
      });
    }
  }

  /// Retry the startup sequence
  Future<void> _retry() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
      _progress = 0;
    });
    await _startStartupSequence();
  }

  /// Open the logs folder
  Future<void> _openLogsFolder() async {
    if (_logsPath == null) return;

    try {
      final uri = Uri.file(_logsPath!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        // Fallback: try to open parent directory
        final parentUri = Uri.file(Directory(_logsPath!).parent.path);
        if (await canLaunchUrl(parentUri)) {
          await launchUrl(parentUri);
        }
      }
    } catch (e) {
      developer.log(
        'StartupScreen: Failed to open logs folder: $e',
        name: 'StartupScreen',
      );
    }
  }

  @override
  void dispose() {
    _orchestrator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorScreen();
    }

    return _buildLoadingScreen();
  }

  /// Loading screen with progress indicator
  Widget _buildLoadingScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A5F2A),
              Color(0xFF2ECC71),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.admin_panel_settings,
                  size: 60,
                  color: Color(0xFF2ECC71),
                ),
              ),
              const SizedBox(height: 48),
              // Loading circle
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(height: 48),
              // Progress bar
              SizedBox(
                width: 240,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progress / 100,
                    backgroundColor: Colors.white.withAlpha(51),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Status message
              Text(
                _statusMessage,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Error screen with retry option
  Widget _buildErrorScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF8B2635),
              Color(0xFFC0392B),
            ],
          ),
        ),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(51),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Color(0xFFE74C3C),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Startup Issue',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF7F8C8D),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_logsPath != null) ...[
                      OutlinedButton.icon(
                        onPressed: _openLogsFolder,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Open Logs'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7F8C8D),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _retry,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_isLoading ? 'Retrying...' : 'Try Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2ECC71),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

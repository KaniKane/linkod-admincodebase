import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

// Simple file logger for release builds
class _FileLogger {
  static void log(String message) async {
    try {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        final logDir = Directory(path.join(localAppData, 'LINKodAdmin', 'Flutter'));
        if (!logDir.existsSync()) logDir.createSync(recursive: true);
        final logFile = File(path.join(logDir.path, 'startup.log'));
        final timestamp = DateTime.now().toIso8601String();
        logFile.writeAsStringSync('$timestamp: $message\n', mode: FileMode.append);
      }
    } catch (_) {
      // Ignore logging errors
    }
  }
}

/// Result of backend startup attempt
class BackendStartupResult {
  BackendStartupResult({
    required this.success,
    this.errorMessage,
    this.logsPath,
    this.alreadyRunning = false,
  });

  final bool success;
  final String? errorMessage;
  final String? logsPath;
  final bool alreadyRunning;

  bool get needsUserAction => !success;
}

/// Startup orchestration for LINKod Admin backend.
///
/// This service manages the lifecycle of the packaged Python backend:
/// - Checks if backend is already running (health check)
/// - Starts the backend EXE if not running
/// - Polls until backend is healthy or timeout
/// - Provides error handling and user-friendly error messages
///
/// Usage:
/// ```dart
/// final orchestrator = BackendOrchestrator();
/// final result = await orchestrator.ensureBackendRunning();
/// if (!result.success) {
///   // Show error dialog with result.errorMessage
/// }
/// ```
class BackendOrchestrator {
  BackendOrchestrator({
    this.healthCheckUrl = 'http://127.0.0.1:8000/health',
    this.backendPort = 8000,
    this.healthCheckTimeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(milliseconds: 500),
    this.maxPollAttempts = 40, // 40 * 500ms = 20 seconds
  });

  final String healthCheckUrl;
  final int backendPort;
  final Duration healthCheckTimeout;
  final Duration pollInterval;
  final int maxPollAttempts;

  Process? _backendProcess;
  bool _isShuttingDown = false;

  /// Ensure the backend is running.
  /// 
  /// 1. Check if backend is already healthy
  /// 2. If not, try to start the packaged backend EXE
  /// 3. Poll until healthy or timeout
  /// 4. Return result with success status and error info if failed
  Future<BackendStartupResult> ensureBackendRunning() async {
    _FileLogger.log('Starting backend orchestration...');
    developer.log(
      'BackendOrchestrator: Ensuring backend is running...',
      name: 'BackendOrchestrator',
    );

    // Step 1: Check if already healthy
    final isHealthy = await _checkHealth();
    _FileLogger.log('Initial health check: $isHealthy');
    if (isHealthy) {
      _FileLogger.log('Backend already running');
      developer.log(
        'BackendOrchestrator: Backend already running and healthy',
        name: 'BackendOrchestrator',
      );
      return BackendStartupResult(
        success: true,
        alreadyRunning: true,
      );
    }

    // Step 2: Try to start the backend
    _FileLogger.log('Backend not running, attempting to start...');
    developer.log(
      'BackendOrchestrator: Backend not running, attempting to start...',
      name: 'BackendOrchestrator',
    );

    final startResult = await _startBackend();
    _FileLogger.log('Start backend result: $startResult');
    if (!startResult) {
      final logsPath = await _getBackendLogsPath();
      _FileLogger.log('Failed to start backend');
      return BackendStartupResult(
        success: false,
        errorMessage: 'Failed to start the backend service. '
            'The application may need to be reinstalled or there may be a system issue.',
        logsPath: logsPath,
      );
    }

    // Step 3: Poll until healthy
    _FileLogger.log('Waiting for backend to become healthy...');
    developer.log(
      'BackendOrchestrator: Waiting for backend to become healthy...',
      name: 'BackendOrchestrator',
    );

    final becameHealthy = await _pollForHealth();
    _FileLogger.log('Poll for health result: $becameHealthy');
    if (!becameHealthy) {
      final logsPath = await _getBackendLogsPath();
      _FileLogger.log('Backend failed to become healthy');
      developer.log(
        'BackendOrchestrator: Backend failed to become healthy within timeout',
        name: 'BackendOrchestrator',
      );
      return BackendStartupResult(
        success: false,
        errorMessage: 'The backend service started but did not respond in time. '
            'This may indicate a configuration issue or port conflict (port $backendPort in use).',
        logsPath: logsPath,
      );
    }

    _FileLogger.log('Backend is healthy and ready');
    developer.log(
      'BackendOrchestrator: Backend is healthy and ready',
      name: 'BackendOrchestrator',
    );
    return BackendStartupResult(success: true);
  }

  /// Check if the backend is healthy
  Future<bool> _checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse(healthCheckUrl))
          .timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          return body['status'] == 'ok';
        } catch (_) {
          return true; // 200 OK is sufficient
        }
      }
      return false;
    } on SocketException {
      return false; // Connection refused - not running
    } on TimeoutException {
      return false; // Timeout - not responding
    } catch (e) {
      developer.log(
        'BackendOrchestrator: Health check error: $e',
        name: 'BackendOrchestrator',
      );
      return false;
    }
  }

  /// Poll for backend health with retry logic
  Future<bool> _pollForHealth() async {
    for (var attempt = 0; attempt < maxPollAttempts; attempt++) {
      final isHealthy = await _checkHealth();
      if (isHealthy) {
        return true;
      }
      
      // Wait before next attempt
      await Future.delayed(pollInterval);
    }
    return false;
  }

  /// Start the packaged backend executable
  Future<bool> _startBackend() async {
    try {
      final exePath = await _resolveBackendExePath();
      if (exePath == null) {
        _FileLogger.log('Could not resolve backend EXE path');
        developer.log(
          'BackendOrchestrator: Could not resolve backend EXE path',
          name: 'BackendOrchestrator',
        );
        return false;
      }

      final workingDir = path.dirname(exePath);

      _FileLogger.log('Starting backend from: $exePath (working dir: $workingDir)');
      developer.log(
        'BackendOrchestrator: Starting backend from: $exePath (working dir: $workingDir)',
        name: 'BackendOrchestrator',
      );

      // Check if already running by checking for port in use
      if (await _isPortInUse(backendPort)) {
        _FileLogger.log('Port $backendPort already in use, assuming backend running');
        developer.log(
          'BackendOrchestrator: Port $backendPort already in use, assuming backend running',
          name: 'BackendOrchestrator',
        );
        return true;
      }

      // Start the process with proper working directory
      // Use detached mode so backend continues running even if Flutter app closes
      _FileLogger.log('Launching process...');
      _backendProcess = await Process.start(
        exePath,
        [], // No arguments needed - launcher handles config
        workingDirectory: workingDir,
        mode: ProcessStartMode.detached,
      );

      _FileLogger.log('Process started with PID: ${_backendProcess?.pid}');
      developer.log(
        'BackendOrchestrator: Backend process started with PID: ${_backendProcess?.pid}',
        name: 'BackendOrchestrator',
      );

      return true;
    } catch (e, stackTrace) {
      _FileLogger.log('Failed to start backend: $e');
      developer.log(
        'BackendOrchestrator: Failed to start backend: $e',
        name: 'BackendOrchestrator',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Resolve the path to the backend executable
  /// 
  /// In production (installed), the backend EXE is in the same directory
  /// as the Flutter app executable.
  /// In development, we don't auto-start (expect manual backend run).
  Future<String?> _resolveBackendExePath() async {
    try {
      // Get the directory containing the Flutter app executable
      final appDir = await _getAppDirectory();
      if (appDir == null) {
        return null;
      }

      // Backend EXE should be in a 'backend' subdirectory or same directory
      final possiblePaths = [
        path.join(appDir, 'backend', 'linkod_admin_backend.exe'),
        path.join(appDir, 'linkod_admin_backend.exe'),
        path.join(appDir, 'linkod_admin_backend', 'linkod_admin_backend.exe'),
      ];

      for (final exePath in possiblePaths) {
        _FileLogger.log('Checking path: $exePath exists=${File(exePath).existsSync()}');
        if (File(exePath).existsSync()) {
          _FileLogger.log('Found backend EXE at: $exePath');
          developer.log(
            'BackendOrchestrator: Found backend EXE at: $exePath',
            name: 'BackendOrchestrator',
          );
          return exePath;
        }
      }

      _FileLogger.log('Backend EXE not found in any location');
      return null;
    } catch (e) {
      developer.log(
        'BackendOrchestrator: Error resolving backend path: $e',
        name: 'BackendOrchestrator',
      );
      return null;
    }
  }

  /// Get the application directory (where the Flutter EXE is located)
  Future<String?> _getAppDirectory() async {
    try {
      if (Platform.isWindows) {
        // In production, Platform.resolvedExecutable gives us the path to the EXE
        final exePath = Platform.resolvedExecutable;
        _FileLogger.log('Resolved executable path: $exePath');
        return path.dirname(exePath);
      } else {
        // Development/other platforms
        return null;
      }
    } catch (e) {
      _FileLogger.log('Error getting app directory: $e');
      developer.log(
        'BackendOrchestrator: Error getting app directory: $e',
        name: 'BackendOrchestrator',
      );
      return null;
    }
  }

  /// Get the path where backend logs are stored
  Future<String> _getBackendLogsPath() async {
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        return path.join(localAppData, 'LINKodAdmin', 'Backend', 'logs');
      }
    }
    
    // Fallback to temp directory
    final tempDir = await getTemporaryDirectory();
    return path.join(tempDir.path, 'linkod_admin', 'logs');
  }

  /// Check if a port is already in use
  Future<bool> _isPortInUse(int port) async {
    try {
      final socket = await ServerSocket.bind('127.0.0.1', port);
      await socket.close();
      return false; // Port available
    } catch (_) {
      return true; // Port in use
    }
  }

  /// Shutdown the backend process if we started it
  /// 
  /// Note: By default, we don't kill the backend when the app closes.
  /// This allows the backend to keep running for faster subsequent app starts.
  /// Call this method only if you explicitly want to shut down the backend.
  Future<void> shutdownBackend() async {
    if (_isShuttingDown) return;
    _isShuttingDown = true;

    developer.log(
      'BackendOrchestrator: Shutting down backend...',
      name: 'BackendOrchestrator',
    );

    if (_backendProcess != null) {
      try {
        // Send signal to terminate (Windows doesn't support SIGTERM well,
        // but the backend should handle it if possible)
        _backendProcess!.kill();
        
        // Wait a moment for graceful shutdown
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Force kill if still running
        if (_backendProcess != null) {
          _backendProcess!.kill(ProcessSignal.sigkill);
        }
      } catch (e) {
        developer.log(
          'BackendOrchestrator: Error killing backend process: $e',
          name: 'BackendOrchestrator',
        );
      }
      _backendProcess = null;
    }

    _isShuttingDown = false;
  }

  /// Dispose resources
  void dispose() {
    // We intentionally do NOT auto-kill the backend here
    // This keeps it running for faster restarts
    _backendProcess = null;
  }
}

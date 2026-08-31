import 'dart:async';
import 'dart:io' show exit;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:root_checker_plus/root_checker_plus.dart';
import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/features/auth/providers/auth_provider.dart';
import 'package:dula_auth/features/auth/screens/app_lock_screen.dart';
import 'package:dula_auth/features/auth/screens/credential_setup_screen.dart';
import 'package:dula_auth/features/settings/providers/settings_provider.dart';

class AppLifecycleWrapper extends ConsumerStatefulWidget {
  final Widget child;
  
  const AppLifecycleWrapper({super.key, required this.child});

  @override
  ConsumerState<AppLifecycleWrapper> createState() => _AppLifecycleWrapperState();
}

class _AppLifecycleWrapperState extends ConsumerState<AppLifecycleWrapper> with WidgetsBindingObserver {
  Timer? _lockTimer;
  bool _isDeviceCompromised = false;
  bool _isInactive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkDeviceIntegrity();
    _protectScreen();
  }
  
  Future<void> _checkDeviceIntegrity() async {
    if (kIsWeb) return;
    try {
      bool isCompromised = false;
      if (defaultTargetPlatform == TargetPlatform.android) {
        final isRooted = await RootCheckerPlus.isRootChecker() ?? false;
        final isDevMode = await RootCheckerPlus.isDeveloperMode() ?? false;
        isCompromised = isRooted || isDevMode;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        isCompromised = await RootCheckerPlus.isJailbreak() ?? false;
      }
      
      if (mounted && isCompromised) {
        setState(() {
          _isDeviceCompromised = true;
        });
      }
    } catch (_) {
      // If the security check fails, we conservatively continue but might log it
    }
  }
  
  Future<void> _protectScreen() async {
    try {
      await ScreenProtector.preventScreenshotOn();
      await ScreenProtector.protectDataLeakageWithBlur();
    } catch (_) {
      // Might fail on unsupported platforms like Windows without native code, ignore error
    }
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Immediate privacy blurring
    final isNowInactive = state != AppLifecycleState.resumed;
    if (_isInactive != isNowInactive) {
      setState(() {
        _isInactive = isNowInactive;
      });
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _lockTimer?.cancel();

      // How patient the lock is, is the user's call (ADR-0011): 30 seconds
      // suits a shared workstation and is merely irritating on a personal
      // desktop. "Never" means no timer at all rather than a very long one.
      final delay = ref.read(settingsProvider).autoLock.duration;
      if (delay == null) return;

      if (delay == Duration.zero) {
        ref.read(authStateProvider.notifier).lock();
      } else {
        _lockTimer = Timer(delay, () {
          ref.read(authStateProvider.notifier).lock();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _lockTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDeviceCompromised) {
      return _buildCompromisedWarning();
    }

    final authState = ref.watch(authStateProvider);
    final branding = ref.watch(brandingConfigProvider);

    // Three gates, in order of precedence: create a credential, replace an
    // expired one, or unlock. Rotation only reaches the setup screen once the
    // current credential has been verified on the lock screen.
    final needsSetup = authState.isSetupRequired ||
        (authState.isCredentialExpired && authState.isVerifiedForRotation);

    Widget content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: needsSetup
          ? const CredentialSetupScreen()
          : (authState.isLocked ? const AppLockScreen() : widget.child),
    );

    // Immediate privacy overlay when app is inactive (task switcher, etc.)
    // Only show if NOT already on the lock screen (which is already secure)
    if (_isInactive && !authState.isLocked && !authState.isSetupRequired) {
      return Stack(
        children: [
          content,
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.shield_outlined, color: Colors.white70, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    '${branding.appName} - Secure Mode',
                    style: const TextStyle(color: Colors.white70, decoration: TextDecoration.none, fontSize: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return content;
  }

  Widget _buildCompromisedWarning() {
    return Scaffold(
      backgroundColor: Colors.red[900],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 80),
              const SizedBox(height: 24),
              const Text(
                'SECURITY ALERT',
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'This device appears to be ROOTED or JAILBROKEN. For your safety, this authenticator cannot run on compromised devices.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => exit(0),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red[900]),
                child: const Text('CLOSE APPLICATION'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

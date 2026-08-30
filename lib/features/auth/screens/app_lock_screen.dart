import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dula_auth/features/auth/providers/auth_provider.dart';
import 'package:dula_auth/core/widgets/responsive_layout.dart';
import 'package:dula_auth/core/security/pin_policy.dart';
import 'package:dula_auth/core/branding/branded_logo.dart';
import 'package:dula_auth/core/branding/branding_config.dart';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/services.dart';

class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> with WidgetsBindingObserver {
  String _currentPin = '';
  String _errorText = '';
  
  // For setup mode
  String? _firstPin;
  bool _isConfirming = false;
  
  // Biometric state
  bool _biometricsAvailable = false;
  bool _isBiometricLoading = false;

  final FocusNode _focusNode = FocusNode();
  Timer? _lockoutTimer;
  
  static const int _pinLength = 6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startLockoutTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _checkAndTriggerBiometrics();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-trigger biometrics if the app was locked in the background and is now returning to foreground
      _checkAndTriggerBiometrics();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockoutTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  /// Check if biometrics is available and, if so, auto-trigger the prompt.
  /// This runs every time the lock screen is shown (including after inactivity lock).
  Future<void> _checkAndTriggerBiometrics() async {
    if (!mounted) return;
    final authState = ref.read(authStateProvider);
    // Only auto-trigger for normal unlock, not during PIN setup/rotation
    if (authState.isPinSetupRequired || authState.isPinExpired) return;

    final repository = ref.read(authRepositoryProvider);
    final isEnabled = await repository.isBiometricsEnabled();
    final canUse = await repository.canUseBiometrics();
    final available = isEnabled && canUse;

    if (!mounted) return;
    setState(() => _biometricsAvailable = available);

    if (available) {
      // Small delay so the lock screen animation completes first
      await Future.delayed(const Duration(milliseconds: 400));
      // Only fire the biometric prompt if the app is actually in the foreground.
      // If it's in the background, we'll catch it in didChangeAppLifecycleState when it resumes.
      if (mounted && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _triggerBiometricUnlock();
      }
    }
  }

  Future<void> _triggerBiometricUnlock() async {
    if (_isBiometricLoading || !mounted) return;
    setState(() => _isBiometricLoading = true);
    await ref.read(authStateProvider.notifier).unlockWithBiometrics();
    if (mounted) setState(() => _isBiometricLoading = false);
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final authState = ref.read(authStateProvider);
      if (authState.isLockedOut) {
        setState(() {}); // Refresh for countdown
      } else if (authState.lockoutUntil != null) {
        setState(() {}); // Final refresh when lockout ends
        timer.cancel();
      } else {
        timer.cancel();
      }
    });
  }

  void _onDigitPressed(String digit) {
    if (_currentPin.length < _pinLength) {
      setState(() {
        _currentPin += digit;
        _errorText = '';
      });
      
      if (_currentPin.length == _pinLength) {
        _processPin();
      }
    }
  }

  void _onBackspacePressed() {
    if (_currentPin.isNotEmpty) {
      setState(() {
        _currentPin = _currentPin.substring(0, _currentPin.length - 1);
        _errorText = '';
      });
    }
  }
  
  Future<void> _processPin() async {
    final authState = ref.read(authStateProvider);
    final notifier = ref.read(authStateProvider.notifier);

    // Give a slight delay for visual feedback before processing
    await Future.delayed(const Duration(milliseconds: 150));

    if (authState.isPinSetupRequired || (authState.isPinExpired && authState.isPinVerifiedForRotation)) {
      if (!_isConfirming) {
        final pinError = PinPolicy.validate(_currentPin);
        if (pinError != null) {
          setState(() {
            _errorText = pinError;
            _currentPin = '';
          });
          return;
        }
        setState(() {
          _firstPin = _currentPin;
          _currentPin = '';
          _isConfirming = true;
        });
      } else {
        if (_firstPin == _currentPin) {
          // Success, save NEW PIN (rotation or setup)
          final success = await notifier.setupPin(_currentPin);
          if (success) {
            setState(() {
              _currentPin = '';
              _errorText = '';
              _firstPin = null;
              _isConfirming = false;
            });
          } else {
            // Reuse error (New PIN same as Old PIN)
            setState(() {
              _errorText = 'New PIN cannot be the same as your old one.';
              _currentPin = '';
              _firstPin = null;
              _isConfirming = false;
            });
          }
        } else {
          // Mismatch
          setState(() {
            _errorText = 'PINs do not match. Try again.';
            _currentPin = '';
            _firstPin = null;
            _isConfirming = false;
          });
        }
      }
    } else {
      // Normal unlock or Rotation step 1 (Verify Old PIN)
      final success = await notifier.unlockWithPin(_currentPin);
      if (success && authState.isPinExpired) {
        // Old PIN verified, now prompt for NEW PIN
        setState(() {
          _currentPin = '';
          _errorText = '';
        });
      } else if (!success) {
        final newState = ref.read(authStateProvider);
        if (newState.isLockedOut) {
          _startLockoutTimer();
        }
        setState(() {
          _errorText = newState.isLockedOut ? '' : 'Incorrect PIN';
          _currentPin = '';
        });
      }
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final authState = ref.read(authStateProvider);
      if (authState.isLockedOut) return;

      final logicalKey = event.logicalKey;
      
      // Handle standard digits (0-9)
      if (logicalKey.keyLabel.length == 1 && RegExp(r'[0-9]').hasMatch(logicalKey.keyLabel)) {
        _onDigitPressed(logicalKey.keyLabel);
      } 
      // Handle Numpad digits (specifically for cases where label might differ or for robustness)
      else if (logicalKey == LogicalKeyboardKey.numpad0) { _onDigitPressed('0'); }
      else if (logicalKey == LogicalKeyboardKey.numpad1) { _onDigitPressed('1'); }
      else if (logicalKey == LogicalKeyboardKey.numpad2) { _onDigitPressed('2'); }
      else if (logicalKey == LogicalKeyboardKey.numpad3) { _onDigitPressed('3'); }
      else if (logicalKey == LogicalKeyboardKey.numpad4) { _onDigitPressed('4'); }
      else if (logicalKey == LogicalKeyboardKey.numpad5) { _onDigitPressed('5'); }
      else if (logicalKey == LogicalKeyboardKey.numpad6) { _onDigitPressed('6'); }
      else if (logicalKey == LogicalKeyboardKey.numpad7) { _onDigitPressed('7'); }
      else if (logicalKey == LogicalKeyboardKey.numpad8) { _onDigitPressed('8'); }
      else if (logicalKey == LogicalKeyboardKey.numpad9) { _onDigitPressed('9'); }
      // Handle Backspace
      else if (logicalKey == LogicalKeyboardKey.backspace) {
        _onBackspacePressed();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final theme = Theme.of(context);
    final branding = ref.watch(brandingConfigProvider);

    String titleString = 'Enter PIN';
    if (authState.isPinSetupRequired) {
      titleString = _isConfirming ? 'Confirm PIN' : 'Create 6-Digit PIN';
    } else if (authState.isPinExpired) {
      if (!authState.isPinVerifiedForRotation) {
        titleString = 'PIN Expired - Enter Old PIN';
      } else {
        titleString = _isConfirming ? 'Confirm New PIN' : 'Create New PIN';
      }
    }

    return Scaffold(
      body: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4C1D95), Color(0xFF5B21B6), Color(0xFF1E1B4B)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: ResponsiveLayout(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenHeight = constraints.maxHeight;
                  final isSmallScreen = screenHeight < 650;
                  
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 1),
                      // App branding header
                      BrandedLogo(size: isSmallScreen ? 60 : 100),
                      const SizedBox(height: 12),
                      Text(
                        branding.appName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const Spacer(flex: 1),
                      Text(
                        titleString,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      if (!authState.isPinSetupRequired &&
                          authState.isLockedOut) ...[
                        const SizedBox(height: 4),
                        _buildLockoutMessage(authState.lockoutUntil!),
                      ],
                      const Spacer(flex: 1),
                      // PIN Dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pinLength, (index) {
                          final isFilled = index < _currentPin.length;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isFilled ? Colors.white : Colors.white24,
                              border: Border.all(
                                color: isFilled ? Colors.white : Colors.white54,
                                width: 1,
                              ),
                            ),
                          );
                        }),
                      ),
                      if (_errorText.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorText,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                      const Spacer(flex: 1),
                      // Numpad - constrained to fit
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: isSmallScreen ? 340 : 400),
                        child: _buildNumPad(isSmallScreen, authState.isLockedOut),
                      ),
                      
                      if (!authState.isPinSetupRequired && _biometricsAvailable) ...[
                        const Spacer(flex: 1),
                        GestureDetector(
                          onTap: _isBiometricLoading ? null : _triggerBiometricUnlock,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _isBiometricLoading
                                  ? const SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: CircularProgressIndicator(
                                        color: Colors.white70,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.fingerprint,
                                      size: 48,
                                      color: Colors.tealAccent,
                                    ),
                              const SizedBox(height: 6),
                              Text(
                                _isBiometricLoading ? 'Scanning...' : 'Use Biometrics',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(flex: 1),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLockoutMessage(DateTime until) {
    final remaining = until.difference(DateTime.now());
    final seconds = remaining.inSeconds % 60;
    final minutes = remaining.inMinutes;

    String timeStr = '';
    if (minutes > 0) {
      timeStr = '$minutes min ${seconds}s';
    } else {
      timeStr = '${seconds}s';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_clock_outlined, color: Colors.redAccent, size: 16),
          const SizedBox(width: 8),
          Text(
            'Security Lockout: Try again in $timeStr',
            style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNumPad(bool isSmallScreen, bool isDisabled) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNumButton('1', isSmallScreen, isDisabled),
            _buildNumButton('2', isSmallScreen, isDisabled),
            _buildNumButton('3', isSmallScreen, isDisabled),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNumButton('4', isSmallScreen, isDisabled),
            _buildNumButton('5', isSmallScreen, isDisabled),
            _buildNumButton('6', isSmallScreen, isDisabled),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNumButton('7', isSmallScreen, isDisabled),
            _buildNumButton('8', isSmallScreen, isDisabled),
            _buildNumButton('9', isSmallScreen, isDisabled),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: isSmallScreen ? 60 : 80, height: isSmallScreen ? 60 : 80),
            _buildNumButton('0', isSmallScreen, isDisabled),
            Container(
              width: isSmallScreen ? 60 : 80,
              height: isSmallScreen ? 60 : 80,
              alignment: Alignment.center,
              child: IconButton(
                iconSize: isSmallScreen ? 24 : 28,
                color: Colors.white,
                icon: const Icon(Icons.backspace_outlined),
                onPressed: isDisabled ? null : _onBackspacePressed,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNumButton(String digit, bool isSmallScreen, bool isDisabled) {
    final size = isSmallScreen ? 56.0 : 72.0;
    final margin = isSmallScreen ? 8.0 : 12.0;
    
    return Opacity(
      opacity: isDisabled ? 0.4 : 1.0,
      child: Container(
        margin: EdgeInsets.all(margin),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.1),
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isDisabled ? null : () => _onDigitPressed(digit),
                child: Center(
                  child: Text(
                    digit,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 24 : 28,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

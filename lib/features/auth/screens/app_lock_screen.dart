import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dula_auth/core/branding/branded_logo.dart';
import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/core/security/credential_kind.dart';
import 'package:dula_auth/core/security/pin_policy.dart';
import 'package:dula_auth/core/theme/app_theme.dart';
import 'package:dula_auth/core/widgets/responsive_layout.dart';
import 'package:dula_auth/features/auth/providers/auth_provider.dart';
import 'package:dula_auth/features/auth/widgets/passphrase_field.dart';
import 'package:dula_auth/features/auth/widgets/pin_pad.dart';
import 'package:dula_auth/features/settings/providers/settings_provider.dart';

/// Unlock gate for an existing vault.
///
/// Caller: `lib/core/widgets/app_lifecycle_wrapper.dart`, and driven by
/// `integration_test/app_flow_test.dart`. No data schema — it reads auth state
/// and settings and persists nothing itself.
///
/// Setup and rotation entry moved to `credential_setup_screen.dart` during the
/// user instruction "go ahead on phase 3"; this screen now does one job, and
/// presents whichever input the vault's recorded credential kind calls for
/// (ADR-0011).
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen>
    with WidgetsBindingObserver {
  String _pin = '';
  String _errorText = '';
  bool _busy = false;
  bool _biometricPromptInFlight = false;

  final TextEditingController _passphrase = TextEditingController();
  final FocusNode _keyboardFocus = FocusNode();
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startLockoutTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocus.requestFocus();
      _maybePromptForBiometrics();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retry on resume: a prompt raised while backgrounded goes nowhere.
    if (state == AppLifecycleState.resumed) _maybePromptForBiometrics();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockoutTimer?.cancel();
    _passphrase.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  /// Fires the biometric prompt when the user has asked for it.
  ///
  /// This screen is the single owner of that trigger: the auth notifier
  /// deliberately does not raise it on startup, so two prompts can never race.
  Future<void> _maybePromptForBiometrics() async {
    if (!mounted || _biometricPromptInFlight) return;

    // Both the auth state and the settings load asynchronously, and this runs
    // from a post-frame callback — so without waiting, the check reads the
    // defaults (biometrics off), returns, and never fires again. That made
    // biometric unlock silently dead on a cold launch.
    await ref.read(authStateProvider.notifier).ready;
    await ref.read(settingsProvider.notifier).ready;
    if (!mounted) return;

    final auth = ref.read(authStateProvider);
    final settings = ref.read(settingsProvider);
    if (!auth.isLocked) return;
    if (!settings.biometricUnlockEnabled || !auth.biometricsAvailable) return;
    if (auth.isCredentialExpired || auth.isLockedOut) return;

    // Don't raise a prompt into a backgrounded app — it goes nowhere and the
    // resume handler will retry. A *null* state means the platform has not
    // reported one yet, which is normal at cold start and must not be read as
    // "backgrounded", or the launch prompt never fires at all.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;

    setState(() => _biometricPromptInFlight = true);
    await ref.read(authStateProvider.notifier).unlockWithBiometrics();
    if (mounted) setState(() => _biometricPromptInFlight = false);
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final authState = ref.read(authStateProvider);
      if (authState.isLockedOut) {
        setState(() {}); // Refresh the countdown.
      } else {
        if (authState.lockoutUntil != null) setState(() {});
        timer.cancel();
      }
    });
  }

  void _onDigit(String digit) {
    if (_busy || ref.read(authStateProvider).isLockedOut) return;
    if (_pin.length >= PinPolicy.pinLength) return;

    setState(() {
      _pin += digit;
      _errorText = '';
    });

    if (_pin.length == PinPolicy.pinLength) _attemptUnlock(_pin);
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _errorText = '';
    });
  }

  Future<void> _attemptUnlock(String credential) async {
    if (_busy) return;
    setState(() => _busy = true);

    final notifier = ref.read(authStateProvider.notifier);
    final succeeded = await notifier.unlockWithCredential(credential);

    if (!mounted) return;

    if (succeeded) {
      // Either the app is now unlocked, or an expired credential has been
      // verified and the setup screen takes over. Either way this screen is
      // being replaced, so it only needs to stop showing a stale entry.
      setState(() {
        _busy = false;
        _pin = '';
        _errorText = '';
        _passphrase.clear();
      });
      return;
    }

    final state = ref.read(authStateProvider);
    if (state.isLockedOut) _startLockoutTimer();

    setState(() {
      _busy = false;
      _pin = '';
      _passphrase.clear();
      _errorText = state.isLockedOut
          ? ''
          : (state.credentialKind == CredentialKind.pin
              ? 'Incorrect PIN'
              : 'Incorrect passphrase');
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final branding = ref.watch(brandingConfigProvider);

    final isPin = authState.credentialKind == CredentialKind.pin;
    final showBiometricButton =
        settings.biometricUnlockEnabled && authState.biometricsAvailable;

    String title;
    if (authState.isCredentialExpired) {
      title = isPin
          ? 'PIN expired — enter your current PIN'
          : 'Passphrase expired — enter your current one';
    } else {
      title = isPin ? 'Enter PIN' : 'Enter Passphrase';
    }

    return Scaffold(
      body: Container(
        decoration: brandGradientBackground(theme.colorScheme),
        child: SafeArea(
          child: ResponsiveLayout(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 650;

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 24),
                        BrandedLogo(size: compact ? 56 : 88),
                        const SizedBox(height: 12),
                        Text(
                          branding.appName,
                          style: theme.textTheme.displaySmall
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        if (authState.isLockedOut) ...[
                          const SizedBox(height: 12),
                          _buildLockoutMessage(authState.lockoutUntil!),
                        ],
                        const SizedBox(height: 24),
                        if (isPin)
                          _buildPinEntry(compact, authState.isLockedOut)
                        else
                          _buildPassphraseEntry(authState.isLockedOut),
                        if (showBiometricButton) ...[
                          const SizedBox(height: 28),
                          _buildBiometricButton(),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinEntry(bool compact, bool lockedOut) {
    final pad = PinPad(
      onDigit: _onDigit,
      onBackspace: _onBackspace,
      disabled: lockedOut || _busy,
      compact: compact,
    );

    return KeyboardListener(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: pad.handleKeyEvent,
      child: Column(
        children: [
          PinDots(length: PinPolicy.pinLength, filled: _pin.length),
          if (_errorText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _errorText,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          const SizedBox(height: 24),
          pad,
        ],
      ),
    );
  }

  Widget _buildPassphraseEntry(bool lockedOut) {
    return Column(
      children: [
        PassphraseField(
          controller: _passphrase,
          label: 'Passphrase',
          autofocus: true,
          enabled: !lockedOut && !_busy,
          errorText: _errorText.isEmpty ? null : _errorText,
          onSubmitted: () => _attemptUnlock(_passphrase.text),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: lockedOut || _busy
                ? null
                : () => _attemptUnlock(_passphrase.text),
            child: const Text('Unlock'),
          ),
        ),
      ],
    );
  }

  Widget _buildBiometricButton() {
    return GestureDetector(
      onTap: _biometricPromptInFlight ? null : _maybePromptForBiometrics,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _biometricPromptInFlight
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
            _biometricPromptInFlight ? 'Scanning...' : 'Use Biometrics',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildLockoutMessage(DateTime until) {
    final remaining = until.difference(DateTime.now());
    final seconds = remaining.inSeconds % 60;
    final minutes = remaining.inMinutes;
    final timeStr = minutes > 0 ? '$minutes min ${seconds}s' : '${seconds}s';

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
          const Icon(Icons.lock_clock_outlined,
              color: Colors.redAccent, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Too many attempts. Try again in $timeStr',
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

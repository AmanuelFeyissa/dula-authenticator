import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dula_auth/core/branding/branded_logo.dart';
import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/core/security/credential_kind.dart';
import 'package:dula_auth/core/security/credential_policy.dart';
import 'package:dula_auth/core/security/pin_policy.dart';
import 'package:dula_auth/core/widgets/responsive_layout.dart';
import 'package:dula_auth/features/auth/providers/auth_provider.dart';
import 'package:dula_auth/features/auth/widgets/passphrase_field.dart';
import 'package:dula_auth/features/auth/widgets/pin_pad.dart';

/// First-run registration, and the rotation flow when that policy is enabled.
///
/// Caller: `lib/core/widgets/app_lifecycle_wrapper.dart`, which shows this
/// whenever `AuthState.isSetupRequired` or an expired credential has been
/// verified for rotation. Calls `AuthNotifier.setupCredential` and
/// `setBiometricUnlockEnabled`. No data schema of its own — the chosen kind is
/// persisted by `VaultService` into `vault_meta`, the biometric preference by
/// `SettingsRepository`.
///
/// The order of steps matters: biometrics are offered *before* the vault is
/// created but applied only after, because caching the key for biometric
/// unlock requires a key to exist.
///
/// Added for the user instruction "go ahead on phase 3", implementing
/// ADR-0011's PIN-or-passphrase choice at registration.
class CredentialSetupScreen extends ConsumerStatefulWidget {
  const CredentialSetupScreen({super.key});

  @override
  ConsumerState<CredentialSetupScreen> createState() =>
      _CredentialSetupScreenState();
}

enum _Step { choose, enter, confirm, biometrics }

class _CredentialSetupScreenState extends ConsumerState<CredentialSetupScreen> {
  _Step _step = _Step.choose;
  CredentialKind _kind = CredentialKind.pin;

  String _pin = '';
  String? _firstEntry;
  String _error = '';
  bool _busy = false;

  final TextEditingController _passphrase = TextEditingController();
  final FocusNode _keyboardFocus = FocusNode();

  @override
  void dispose() {
    _passphrase.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  bool get _isRotation => ref.read(authStateProvider).isCredentialExpired;

  void _chooseKind(CredentialKind kind) {
    setState(() {
      _kind = kind;
      _step = _Step.enter;
      _error = '';
      _pin = '';
      _firstEntry = null;
      _passphrase.clear();
    });
  }

  void _onDigit(String digit) {
    if (_busy || _pin.length >= PinPolicy.pinLength) return;
    setState(() {
      _pin += digit;
      _error = '';
    });
    if (_pin.length == PinPolicy.pinLength) _submit(_pin);
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = '';
    });
  }

  /// Handles one entry, whichever step we are on.
  Future<void> _submit(String value) async {
    if (_busy) return;

    if (_step == _Step.enter) {
      // Validate before asking the user to type it a second time — being told
      // "too common" only after confirming is wasted effort.
      final policyError = CredentialPolicy.validate(_kind, value);
      if (policyError != null) {
        setState(() {
          _error = policyError;
          _pin = '';
          _passphrase.clear();
        });
        return;
      }
      setState(() {
        _firstEntry = value;
        _pin = '';
        _passphrase.clear();
        _error = '';
        _step = _Step.confirm;
      });
      return;
    }

    if (value != _firstEntry) {
      setState(() {
        _error = _kind == CredentialKind.pin
            ? 'PINs do not match. Try again.'
            : 'Passphrases do not match. Try again.';
        _pin = '';
        _passphrase.clear();
        _firstEntry = null;
        _step = _Step.enter;
      });
      return;
    }

    final biometricsAvailable = ref.read(authStateProvider).biometricsAvailable;
    if (biometricsAvailable && !_isRotation) {
      setState(() => _step = _Step.biometrics);
      return;
    }

    await _create(withBiometrics: false);
  }

  Future<void> _create({required bool withBiometrics}) async {
    setState(() => _busy = true);

    final notifier = ref.read(authStateProvider.notifier);
    final error = await notifier.setupCredential(_firstEntry!, _kind);

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
        _pin = '';
        _firstEntry = null;
        _passphrase.clear();
        _step = _Step.enter;
      });
      return;
    }

    if (withBiometrics) {
      await notifier.setBiometricUnlockEnabled(true);
    }
    // No further setState: a successful setup unlocks the app, and the
    // lifecycle wrapper replaces this screen.
  }

  @override
  Widget build(BuildContext context) {
    final branding = ref.watch(brandingConfigProvider);

    return Scaffold(
      body: Container(
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _buildStep(compact),
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

  Widget _buildStep(bool compact) {
    switch (_step) {
      case _Step.choose:
        return _buildChoose();
      case _Step.enter:
      case _Step.confirm:
        return _kind == CredentialKind.pin
            ? _buildPinEntry(compact)
            : _buildPassphraseEntry();
      case _Step.biometrics:
        return _buildBiometricOffer();
    }
  }

  Widget _buildChoose() {
    return Column(
      children: [
        const Text(
          'How would you like to unlock?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'You can change this later without losing your accounts.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 24),
        for (final kind in CredentialKind.values) ...[
          _ChoiceCard(kind: kind, onTap: () => _chooseKind(kind)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildPinEntry(bool compact) {
    final confirming = _step == _Step.confirm;
    final pad = PinPad(
      onDigit: _onDigit,
      onBackspace: _onBackspace,
      disabled: _busy,
      compact: compact,
    );

    return KeyboardListener(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: pad.handleKeyEvent,
      child: Column(
        children: [
          Text(
            confirming
                ? 'Confirm PIN'
                : (_isRotation ? 'Create New PIN' : 'Create 6-Digit PIN'),
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
          PinDots(length: PinPolicy.pinLength, filled: _pin.length),
          _buildError(),
          const SizedBox(height: 24),
          pad,
          const SizedBox(height: 8),
          _buildStartOver(),
        ],
      ),
    );
  }

  Widget _buildPassphraseEntry() {
    final confirming = _step == _Step.confirm;

    return Column(
      children: [
        Text(
          confirming
              ? 'Confirm Passphrase'
              : (_isRotation ? 'Create New Passphrase' : 'Create Passphrase'),
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 24),
        PassphraseField(
          controller: _passphrase,
          label: confirming ? 'Repeat passphrase' : 'Passphrase',
          showStrength: !confirming,
          autofocus: true,
          enabled: !_busy,
          errorText: _error.isEmpty ? null : _error,
          onSubmitted: () => _submit(_passphrase.text),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : () => _submit(_passphrase.text),
            child: Text(confirming ? 'Confirm' : 'Continue'),
          ),
        ),
        const SizedBox(height: 8),
        _buildStartOver(),
      ],
    );
  }

  Widget _buildBiometricOffer() {
    return Column(
      children: [
        const Icon(Icons.fingerprint, size: 72, color: Colors.tealAccent),
        const SizedBox(height: 16),
        const Text(
          'Unlock with biometrics?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your ${_kind.label.toLowerCase()} keeps working, and you can turn '
          'this off at any time in Settings.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _create(withBiometrics: true),
            icon: const Icon(Icons.fingerprint),
            label: const Text('Enable biometric unlock'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => _create(withBiometrics: false),
          child: const Text('Not now', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }

  Widget _buildError() {
    if (_error.isEmpty) return const SizedBox(height: 12);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        _error,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.redAccent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStartOver() {
    return TextButton(
      onPressed: _busy
          ? null
          : () => setState(() {
                _step = _Step.choose;
                _pin = '';
                _firstEntry = null;
                _error = '';
                _passphrase.clear();
              }),
      child: const Text(
        'Choose a different method',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final CredentialKind kind;
  final VoidCallback onTap;

  const _ChoiceCard({required this.kind, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                kind == CredentialKind.pin ? Icons.dialpad : Icons.password,
                color: Colors.tealAccent,
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      kind.explanation,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

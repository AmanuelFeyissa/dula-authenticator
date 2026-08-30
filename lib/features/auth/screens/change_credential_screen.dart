import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dula_auth/core/security/credential_kind.dart';
import 'package:dula_auth/core/security/credential_policy.dart';
import 'package:dula_auth/core/security/passphrase_policy.dart';
import 'package:dula_auth/core/security/pin_policy.dart';
import 'package:dula_auth/core/widgets/responsive_layout.dart';
import 'package:dula_auth/features/auth/providers/auth_provider.dart';

/// Replaces the unlock credential, optionally switching between a PIN and a
/// passphrase.
///
/// Caller: `lib/features/settings/screens/settings_screen.dart`. Writes
/// nothing directly — `AuthNotifier.changeCredential` re-keys the vault and
/// refreshes the credential-set date.
///
/// Entry uses text fields rather than the keypad even for a PIN: this screen
/// asks for three values at once, and three stacked keypads would be worse to
/// use than three fields.
///
/// Added for the user instruction "go ahead on phase 3", implementing
/// ADR-0011 item 4 — changing the knowledge factor must not cost the user
/// their enrolled accounts.
class ChangeCredentialScreen extends ConsumerStatefulWidget {
  const ChangeCredentialScreen({super.key});

  @override
  ConsumerState<ChangeCredentialScreen> createState() =>
      _ChangeCredentialScreenState();
}

class _ChangeCredentialScreenState
    extends ConsumerState<ChangeCredentialScreen> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  CredentialKind? _newKind;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final kind = _newKind ?? ref.read(authStateProvider).credentialKind;

    if (_next.text != _confirm.text) {
      setState(() => _error = 'The new values do not match.');
      return;
    }

    final policyError = CredentialPolicy.validate(kind, _next.text);
    if (policyError != null) {
      setState(() => _error = policyError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final failure = await ref.read(authStateProvider.notifier).changeCredential(
          current: _current.text,
          next: _next.text,
          kind: kind,
        );

    if (!mounted) return;

    if (failure != null) {
      setState(() {
        _busy = false;
        _error = failure;
      });
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text('Your ${kind.label.toLowerCase()} is updated.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final currentKind = auth.credentialKind;
    final newKind = _newKind ?? currentKind;

    return Scaffold(
      appBar: AppBar(title: const Text('Change credential')),
      body: ResponsiveLayout(
        maxWidth: 560,
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text(
              'Your accounts stay exactly where they are — the vault is '
              're-encrypted under the new credential.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            _field(
              controller: _current,
              label: 'Current ${currentKind.label.toLowerCase()}',
              kind: currentKind,
              autofocus: true,
            ),
            const SizedBox(height: 28),
            const Text(
              'NEW CREDENTIAL',
              style: TextStyle(
                color: Colors.tealAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<CredentialKind>(
              segments: [
                for (final kind in CredentialKind.values)
                  ButtonSegment(
                    value: kind,
                    label: Text(kind.label),
                    icon: Icon(
                      kind == CredentialKind.pin
                          ? Icons.dialpad
                          : Icons.password,
                    ),
                  ),
              ],
              selected: {newKind},
              onSelectionChanged: (selection) => setState(() {
                _newKind = selection.first;
                // The rules differ between kinds, so a half-typed value from
                // the other kind would only produce a confusing error.
                _next.clear();
                _confirm.clear();
                _error = null;
              }),
            ),
            const SizedBox(height: 8),
            Text(
              newKind.explanation,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 20),
            _field(
              controller: _next,
              label: 'New ${newKind.label.toLowerCase()}',
              kind: newKind,
              onChanged: () => setState(() => _error = null),
            ),
            if (newKind == CredentialKind.passphrase) ...[
              const SizedBox(height: 8),
              Text(
                'At least ${PassphrasePolicy.minLength} characters.',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            _field(
              controller: _confirm,
              label: 'Repeat new ${newKind.label.toLowerCase()}',
              kind: newKind,
              onChanged: () => setState(() => _error = null),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Update credential'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required CredentialKind kind,
    bool autofocus = false,
    VoidCallback? onChanged,
  }) {
    final isPin = kind == CredentialKind.pin;

    return TextField(
      controller: controller,
      obscureText: true,
      autofocus: autofocus,
      autocorrect: false,
      enableSuggestions: false,
      enabled: !_busy,
      keyboardType: isPin ? TextInputType.number : TextInputType.text,
      maxLength: isPin ? PinPolicy.pinLength : PassphrasePolicy.maxLength,
      inputFormatters:
          isPin ? [FilteringTextInputFormatter.digitsOnly] : const [],
      onChanged: (_) => onChanged?.call(),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
    );
  }
}

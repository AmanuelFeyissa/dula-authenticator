import 'package:flutter/material.dart';
import 'package:dula_auth/core/security/passphrase_policy.dart';

/// Obscured passphrase entry with an optional strength meter.
///
/// Callers: `lib/features/auth/screens/app_lock_screen.dart` (unlock) and
/// `lib/features/auth/screens/credential_setup_screen.dart` (create and
/// confirm). No data schema — the text stays in the caller's controller and
/// goes straight to the vault; nothing here persists it.
///
/// The reveal toggle is deliberate: hiding a long passphrase behind dots with
/// no way to check it is how people mistype one twice and lock themselves out.
///
/// Added for the user instruction "go ahead on phase 3" (ADR-0011).
class PassphraseField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? errorText;
  final bool showStrength;
  final bool autofocus;
  final bool enabled;
  final VoidCallback? onSubmitted;

  const PassphraseField({
    super.key,
    required this.controller,
    required this.label,
    this.errorText,
    this.showStrength = false,
    this.autofocus = false,
    this.enabled = true,
    this.onSubmitted,
  });

  @override
  State<PassphraseField> createState() => _PassphraseFieldState();
}

class _PassphraseFieldState extends State<PassphraseField> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          obscureText: !_revealed,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => widget.onSubmitted?.call(),
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: const TextStyle(color: Colors.white70),
            errorText: widget.errorText,
            errorStyle: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.tealAccent),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            suffixIcon: IconButton(
              tooltip: _revealed ? 'Hide passphrase' : 'Show passphrase',
              icon: Icon(
                _revealed ? Icons.visibility_off : Icons.visibility,
                color: Colors.white54,
              ),
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
          ),
        ),
        if (widget.showStrength) ...[
          const SizedBox(height: 12),
          _StrengthMeter(passphrase: widget.controller.text),
        ],
      ],
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  final String passphrase;

  const _StrengthMeter({required this.passphrase});

  static const Map<PassphraseStrength, Color> _colors = {
    PassphraseStrength.weak: Colors.redAccent,
    PassphraseStrength.fair: Colors.orangeAccent,
    PassphraseStrength.good: Colors.lightGreenAccent,
    PassphraseStrength.strong: Colors.tealAccent,
  };

  static const Map<PassphraseStrength, String> _labels = {
    PassphraseStrength.weak: 'Weak',
    PassphraseStrength.fair: 'Fair',
    PassphraseStrength.good: 'Good',
    PassphraseStrength.strong: 'Strong',
  };

  @override
  Widget build(BuildContext context) {
    if (passphrase.isEmpty) {
      return Text(
        'At least ${PassphrasePolicy.minLength} characters. '
        'A few unrelated words beat one clever one.',
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      );
    }

    final strength = PassphrasePolicy.strengthOf(passphrase);
    final steps = PassphraseStrength.values.length;
    final filled = strength.index + 1;

    return Row(
      children: [
        for (var i = 0; i < steps; i++)
          Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i == steps - 1 ? 0 : 4),
              decoration: BoxDecoration(
                color: i < filled ? _colors[strength] : Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        const SizedBox(width: 12),
        SizedBox(
          width: 52,
          child: Text(
            _labels[strength]!,
            style: TextStyle(
              color: _colors[strength],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

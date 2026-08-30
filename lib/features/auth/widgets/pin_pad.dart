import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Filled/empty dots showing how much of a PIN has been entered.
///
/// Callers: `lib/features/auth/screens/app_lock_screen.dart` and
/// `lib/features/auth/screens/credential_setup_screen.dart`.
/// No data schema — presentation only.
///
/// Extracted during the user instruction "go ahead on phase 3" so the setup
/// and unlock screens share one keypad instead of two copies of it.
class PinDots extends StatelessWidget {
  final int length;
  final int filled;

  const PinDots({super.key, required this.length, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (index) {
        final isFilled = index < filled;
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
    );
  }
}

/// Numeric keypad for PIN entry.
///
/// Callers: the auth lock and setup screens. No data schema.
///
/// The digit buttons keep their `InkWell` + `Text` structure because the
/// end-to-end suite drives them with `find.widgetWithText(InkWell, digit)`.
class PinPad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool disabled;
  final bool compact;

  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.disabled = false,
    this.compact = false,
  });

  /// Maps a hardware key event onto the keypad, so desktop users can type.
  ///
  /// Returns true when the event was a keypad action, letting the caller stop
  /// there.
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || disabled) return false;

    final key = event.logicalKey;

    if (key.keyLabel.length == 1 && RegExp(r'[0-9]').hasMatch(key.keyLabel)) {
      onDigit(key.keyLabel);
      return true;
    }

    // Not const: LogicalKeyboardKey overrides ==, which a const map forbids.
    final numpad = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.numpad0: '0',
      LogicalKeyboardKey.numpad1: '1',
      LogicalKeyboardKey.numpad2: '2',
      LogicalKeyboardKey.numpad3: '3',
      LogicalKeyboardKey.numpad4: '4',
      LogicalKeyboardKey.numpad5: '5',
      LogicalKeyboardKey.numpad6: '6',
      LogicalKeyboardKey.numpad7: '7',
      LogicalKeyboardKey.numpad8: '8',
      LogicalKeyboardKey.numpad9: '9',
    };

    final digit = numpad[key];
    if (digit != null) {
      onDigit(digit);
      return true;
    }

    if (key == LogicalKeyboardKey.backspace) {
      onBackspace();
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final digit in row) _button(digit)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: compact ? 60 : 80, height: compact ? 60 : 80),
            _button('0'),
            Container(
              width: compact ? 60 : 80,
              height: compact ? 60 : 80,
              alignment: Alignment.center,
              child: IconButton(
                iconSize: compact ? 24 : 28,
                color: Colors.white,
                tooltip: 'Delete',
                icon: const Icon(Icons.backspace_outlined),
                onPressed: disabled ? null : onBackspace,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _button(String digit) {
    final size = compact ? 56.0 : 72.0;
    final margin = compact ? 8.0 : 12.0;

    return Opacity(
      opacity: disabled ? 0.4 : 1.0,
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
                onTap: disabled ? null : () => onDigit(digit),
                child: Center(
                  child: Text(
                    digit,
                    style: TextStyle(
                      fontSize: compact ? 24 : 28,
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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/core/widgets/app_lifecycle_wrapper.dart';
import 'package:dula_auth/features/home/screens/home_screen.dart';

/// The other half of ADR-0018's proof: on Linux with a running, **unlocked**
/// default keyring, the gate must open — the app reaches first-run setup, not
/// the blocking screen. Opt-in, like its no-keyring sibling:
///
///     flutter test integration_test/linux_keyring_ok_test.dart -d linux \
///         --dart-define=DULA_EXPECT_KEYRING=true
///
/// See docs/adr/0018-linux-secret-service-gate.md for the keyring start
/// sequence; `--unlock --start` in one call does *not* create a default
/// collection and would (correctly) fail this test.
const _expectKeyring = bool.fromEnvironment('DULA_EXPECT_KEYRING');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'opens the gate on a healthy keyring and reaches first-run setup',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            brandingConfigProvider.overrideWithValue(BrandingConfig.fallback),
          ],
          child: const MaterialApp(
            home: AppLifecycleWrapper(child: HomeScreen()),
          ),
        ),
      );

      final deadline = DateTime.now().add(const Duration(seconds: 20));
      final setup = find.text('How would you like to unlock?');
      final blocked = find.textContaining('install and enable gnome-keyring');
      while (setup.evaluate().isEmpty &&
          blocked.evaluate().isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 250));
      }

      expect(
        blocked,
        findsNothing,
        reason: 'the gate closed on a keyring that is up and unlocked',
      );
      expect(setup, findsOneWidget);
    },
    skip:
        !(_expectKeyring &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.linux),
  );
}

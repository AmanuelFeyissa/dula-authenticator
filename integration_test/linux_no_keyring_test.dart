import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/core/widgets/app_lifecycle_wrapper.dart';
import 'package:dula_auth/features/home/screens/home_screen.dart';

/// Proves ADR-0018 against the real platform: on Linux with **no** Secret
/// Service on the session bus, the app must reach the ADR-0004 blocking
/// screen promptly instead of freezing on a blank frame.
///
/// This only makes sense in an environment deliberately set up without a
/// keyring, so it is opt-in:
///
///     flutter test integration_test/linux_no_keyring_test.dart -d linux \
///         --dart-define=DULA_EXPECT_NO_KEYRING=true
///
/// Run under Xvfb with a `dbus-launch` session and no `gnome-keyring-daemon`
/// (see docs/adr/0018-linux-secret-service-gate.md for the container recipe).
/// Anywhere else it is skipped rather than failing.
const _expectNoKeyring = bool.fromEnvironment('DULA_EXPECT_NO_KEYRING');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shows the no-credential-store screen instead of hanging',
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

      // The gate's D-Bus query is bounded at 3s and activation at 10s; a
      // frozen platform thread would never let this loop run at all.
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      final target = find.textContaining('install and enable gnome-keyring');
      while (target.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 250));
      }

      expect(target, findsOneWidget);
      expect(
        find.text('How would you like to unlock?'),
        findsNothing,
        reason: 'an unreachable store must not look like first run',
      );
    },
    skip:
        !(_expectNoKeyring &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.linux),
  );
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/features/accounts/screens/add_account_screen.dart';

void main() {
  const scanned =
      'otpauth://totp/GitHub:dev@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub';

  Widget harness(Future<String?> Function(BuildContext) launcher) {
    return ProviderScope(
      overrides: [
        qrScanLauncherProvider.overrideWithValue(launcher),
        brandingConfigProvider.overrideWithValue(BrandingConfig.fallback),
      ],
      child: const MaterialApp(home: AddAccountScreen()),
    );
  }

  testWidgets(
    'a scanned credential returns to the form, fills it in, and confirms '
    'the scan',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await tester.pumpWidget(harness((_) async => scanned));

      await tester.tap(find.text('Scan QR Code with Camera'));
      await tester.pumpAndSettle();

      // Back on the form, not left sitting on the camera.
      expect(find.text('ADD ACCOUNT'), findsOneWidget);

      // The scanned credential actually landed in the fields.
      expect(find.text('GitHub'), findsWidgets);
      expect(find.text('dev@example.com'), findsWidgets);
      expect(find.text('JBSWY3DPEHPK3PXP'), findsWidgets);

      // And the user is told the scan worked, rather than being left to guess.
      expect(find.textContaining('Scanned'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('a cancelled scan leaves the form untouched and says nothing',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.pumpWidget(harness((_) async => null));

    await tester.tap(find.text('Scan QR Code with Camera'));
    await tester.pumpAndSettle();

    expect(find.text('ADD ACCOUNT'), findsOneWidget);
    expect(find.textContaining('Scanned'), findsNothing);
    expect(find.text('GitHub'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });
}

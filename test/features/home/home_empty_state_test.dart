import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/core/repositories/account_repository.dart';
import 'package:dula_auth/core/vault/secret_store.dart';
import 'package:dula_auth/features/auth/providers/auth_provider.dart';
import 'package:dula_auth/features/auth/repositories/auth_repository.dart';
import 'package:dula_auth/features/home/providers/home_provider.dart';
import 'package:dula_auth/features/home/screens/home_screen.dart';

/// The empty-state hint must only suggest scanning where a camera path
/// actually exists (ADR-0006): on Windows and Linux there is no scanner, so
/// telling the user to scan sends them looking for a button that isn't there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(WidgetTester tester) async {
    final store = InMemorySecretStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          brandingConfigProvider.overrideWithValue(BrandingConfig.fallback),
          authRepositoryProvider.overrideWithValue(
            AuthRepository(store: store),
          ),
          accountRepositoryProvider.overrideWithValue(
            AccountRepository(store: store),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('on a camera-less desktop the hint points at paste or manual '
      'entry, not scanning', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pumpHome(tester);

    expect(find.text('No Accounts Yet'), findsOneWidget);
    expect(find.textContaining('Scan'), findsNothing);
    expect(find.textContaining('Paste a QR image'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on a phone the hint still offers scanning', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpHome(tester);

    expect(find.textContaining('Scan a QR code'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}

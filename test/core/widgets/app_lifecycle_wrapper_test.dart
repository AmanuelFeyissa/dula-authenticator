import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/core/security/secure_storage_canary.dart';
import 'package:dula_auth/core/vault/secret_store.dart';
import 'package:dula_auth/core/widgets/app_lifecycle_wrapper.dart';
import 'package:dula_auth/features/auth/providers/auth_provider.dart';
import 'package:dula_auth/features/auth/repositories/auth_repository.dart';

class _ThrowingSecretStore implements SecretStore {
  @override
  Future<String?> read(String key) async => throw StateError('no keyring');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('no keyring');

  @override
  Future<void> delete(String key) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'blocks with an explicit error on Linux when secure storage has no '
    'accessible keyring (ADR-0004)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            brandingConfigProvider.overrideWithValue(BrandingConfig.fallback),
            // In-process against a failing store: the real probe runs on a
            // background isolate (ADR-0017), which a widget test has no root
            // token to bootstrap platform channels on.
            secureStorageProbeProvider.overrideWithValue(
              () => SecureStorageCanary.check(_ThrowingSecretStore()),
            ),
            // In-memory so the (still-unresolved) auth check behind the
            // storage gate never reaches a real platform channel.
            authRepositoryProvider.overrideWithValue(
              AuthRepository(store: InMemorySecretStore()),
            ),
          ],
          child: const MaterialApp(
            home: AppLifecycleWrapper(child: SizedBox()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('install and enable gnome-keyring'),
        findsOneWidget,
      );

      debugDefaultTargetPlatformOverride = null;
    },
  );
}

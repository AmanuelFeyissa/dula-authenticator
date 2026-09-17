import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/security/biometric_authenticator.dart';
import 'package:dula_auth/core/vault/secret_store.dart';
import 'package:dula_auth/core/vault/vault_service.dart';
import 'package:dula_auth/features/auth/providers/auth_provider.dart';
import 'package:dula_auth/features/auth/repositories/auth_repository.dart';
import 'package:dula_auth/features/auth/screens/app_lock_screen.dart';

const _params = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

/// Holds the startup read open, so a test can unmount the lock screen while
/// `AuthNotifier.ready` is still pending — the window in which the screen's
/// biometric prompt is suspended mid-`await`.
class _HangingStore extends InMemorySecretStore {
  final gate = Completer<void>();
  var reads = 0;

  @override
  Future<String?> read(String key) async {
    reads++;
    await gate.future;
    return super.read(key);
  }
}

class _AvailableBiometrics implements BiometricAuthenticator {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate(String reason) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'the lock screen does not touch ref after being disposed mid-prompt',
    (tester) async {
      final store = _HangingStore();
      final repository = AuthRepository(
        store: store,
        vault: VaultService(store, params: _params),
        biometrics: _AvailableBiometrics(),
      );

      // One ProviderScope whose child is swapped, mirroring how
      // AppLifecycleWrapper replaces the lock screen: the container survives,
      // only the screen is disposed. Replacing the whole scope instead would
      // tear the container down and test the harness rather than the app.
      final showLock = ValueNotifier<bool>(true);
      addTearDown(showLock.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            brandingConfigProvider.overrideWithValue(BrandingConfig.fallback),
            authRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: showLock,
              builder: (_, lock, _) => lock
                  ? const AppLockScreen()
                  : const Scaffold(body: SizedBox()),
            ),
          ),
        ),
      );
      // The post-frame callback has run and the prompt is now suspended
      // waiting on the startup read.
      await tester.pump();
      expect(
        store.reads,
        greaterThan(0),
        reason: 'the startup read should be in flight',
      );

      // Whatever replaces the lock screen — the storage-unavailable screen, a
      // successful unlock, a rebuild — disposes it while that await is parked.
      showLock.value = false;
      await tester.pump();

      // Let the suspended prompt resume against the disposed widget.
      store.gate.complete();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'resuming after disposal must not use ref',
      );
    },
  );
}

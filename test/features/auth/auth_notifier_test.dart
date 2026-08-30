import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/repositories/account_repository.dart';
import 'package:dula_auth/core/security/biometric_authenticator.dart';
import 'package:dula_auth/core/security/credential_kind.dart';
import 'package:dula_auth/core/vault/secret_store.dart';
import 'package:dula_auth/core/vault/vault_service.dart';
import 'package:dula_auth/features/auth/providers/auth_provider.dart';
import 'package:dula_auth/features/auth/repositories/auth_repository.dart';
import 'package:dula_auth/features/home/providers/home_provider.dart';

const testParams = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

const strongPin = '481629';
const otherPin = '750392';
const strongPassphrase = 'rope anchor lantern';

/// Stands in for the platform biometric prompt, which cannot be driven from a
/// test. [available] mirrors device capability; [willSucceed] mirrors what the
/// user does when prompted.
class FakeBiometrics implements BiometricAuthenticator {
  bool available;
  bool willSucceed;
  int prompts = 0;

  FakeBiometrics({this.available = true, this.willSucceed = true});

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return available && willSucceed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemorySecretStore store;
  late VaultService vault;
  late FakeBiometrics biometrics;
  late AuthRepository repository;

  /// Builds a container over the shared store, so a second container models
  /// relaunching the app against the same device state.
  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        accountRepositoryProvider.overrideWithValue(
          AccountRepository(store: store, vault: vault),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<AuthNotifier> notifierFrom(ProviderContainer container) async {
    final notifier = container.read(authStateProvider.notifier);
    await notifier.ready;
    return notifier;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = InMemorySecretStore({});
    vault = VaultService(store, params: testParams);
    biometrics = FakeBiometrics();
    repository = AuthRepository(
      store: store,
      vault: vault,
      biometrics: biometrics,
    );
  });

  group('first run', () {
    test('asks for setup instead of an unlock', () async {
      final auth = await notifierFrom(buildContainer());

      expect(auth.state.isSetupRequired, isTrue);
      expect(auth.state.isLocked, isFalse);
    });

    test('a PIN setup opens the vault and records the kind', () async {
      final auth = await notifierFrom(buildContainer());

      final error = await auth.setupCredential(strongPin, CredentialKind.pin);

      expect(error, isNull);
      expect(auth.state.isLocked, isFalse);
      expect(auth.state.masterKey, isNotNull);
      expect(await vault.credentialKind(), CredentialKind.pin);
    });

    test('a passphrase setup records the passphrase kind', () async {
      final auth = await notifierFrom(buildContainer());

      final error = await auth.setupCredential(
        strongPassphrase,
        CredentialKind.passphrase,
      );

      expect(error, isNull);
      expect(await vault.credentialKind(), CredentialKind.passphrase);
    });

    test('a weak PIN is refused and creates no vault', () async {
      final auth = await notifierFrom(buildContainer());

      final error = await auth.setupCredential('123456', CredentialKind.pin);

      expect(error, isNotNull);
      expect(await vault.isInitialized(), isFalse,
          reason: 'a refused credential must not leave a vault behind');
      expect(auth.state.isSetupRequired, isTrue);
    });

    test('a too-short passphrase is refused', () async {
      final auth = await notifierFrom(buildContainer());

      final error = await auth.setupCredential(
        'short',
        CredentialKind.passphrase,
      );

      expect(error, isNotNull);
      expect(await vault.isInitialized(), isFalse);
    });
  });

  group('returning user', () {
    test('starts locked, presenting the kind that was chosen', () async {
      final first = await notifierFrom(buildContainer());
      await first.setupCredential(strongPassphrase, CredentialKind.passphrase);

      final relaunched = await notifierFrom(buildContainer());

      expect(relaunched.state.isSetupRequired, isFalse);
      expect(relaunched.state.isLocked, isTrue);
      expect(relaunched.state.credentialKind, CredentialKind.passphrase);
    });

    test('the right credential unlocks', () async {
      final first = await notifierFrom(buildContainer());
      await first.setupCredential(strongPin, CredentialKind.pin);

      final relaunched = await notifierFrom(buildContainer());
      final unlocked = await relaunched.unlockWithCredential(strongPin);

      expect(unlocked, isTrue);
      expect(relaunched.state.isLocked, isFalse);
      expect(relaunched.state.masterKey, isNotNull);
    });

    test('the wrong credential leaves the vault closed', () async {
      final first = await notifierFrom(buildContainer());
      await first.setupCredential(strongPin, CredentialKind.pin);

      final relaunched = await notifierFrom(buildContainer());
      final unlocked = await relaunched.unlockWithCredential(otherPin);

      expect(unlocked, isFalse);
      expect(relaunched.state.isLocked, isTrue);
      expect(relaunched.state.masterKey, isNull);
      expect(relaunched.state.failedAttempts, 1);
    });

    test('repeated failures impose a lockout', () async {
      final first = await notifierFrom(buildContainer());
      await first.setupCredential(strongPin, CredentialKind.pin);

      final relaunched = await notifierFrom(buildContainer());
      for (var i = 0; i < 3; i++) {
        await relaunched.unlockWithCredential(otherPin);
      }

      expect(relaunched.state.isLockedOut, isTrue);
    });

    test('a lockout refuses even the correct credential', () async {
      final first = await notifierFrom(buildContainer());
      await first.setupCredential(strongPin, CredentialKind.pin);

      final relaunched = await notifierFrom(buildContainer());
      for (var i = 0; i < 3; i++) {
        await relaunched.unlockWithCredential(otherPin);
      }

      expect(await relaunched.unlockWithCredential(strongPin), isFalse,
          reason: 'the lockout is the point; guessing must cost time');
    });

    test('a successful unlock clears the failure count', () async {
      final first = await notifierFrom(buildContainer());
      await first.setupCredential(strongPin, CredentialKind.pin);

      final relaunched = await notifierFrom(buildContainer());
      await relaunched.unlockWithCredential(otherPin);
      await relaunched.unlockWithCredential(strongPin);

      expect(relaunched.state.failedAttempts, 0);
      expect(await repository.getFailedAttempts(), 0);
    });

    test('locking discards the key held in memory', () async {
      final auth = await notifierFrom(buildContainer());
      await auth.setupCredential(strongPin, CredentialKind.pin);

      auth.lock();

      expect(auth.state.isLocked, isTrue);
      expect(auth.state.masterKey, isNull);
    });
  });

  group('biometric unlock', () {
    test('is off until the user turns it on', () async {
      final auth = await notifierFrom(buildContainer());
      await auth.setupCredential(strongPin, CredentialKind.pin);

      expect(auth.settings.biometricUnlockEnabled, isFalse);
    });

    test('does not cache the vault key while it is off', () async {
      // A cached key is only justified by biometrics needing to restore it.
      // Storing it regardless leaves the vault key at rest for no benefit.
      final auth = await notifierFrom(buildContainer());
      await auth.setupCredential(strongPin, CredentialKind.pin);

      expect(await repository.getStoredMasterKey(), isNull);
    });

    test('caches the vault key once enabled', () async {
      final auth = await notifierFrom(buildContainer());
      await auth.setupCredential(strongPin, CredentialKind.pin);

      await auth.setBiometricUnlockEnabled(true);

      expect(await repository.getStoredMasterKey(), isNotNull);
    });

    test('discards the cached key when switched back off', () async {
      final auth = await notifierFrom(buildContainer());
      await auth.setupCredential(strongPin, CredentialKind.pin);
      await auth.setBiometricUnlockEnabled(true);

      await auth.setBiometricUnlockEnabled(false);

      expect(await repository.getStoredMasterKey(), isNull,
          reason: 'turning biometrics off must not leave the key behind');
    });

    test('cannot be enabled on a device without biometrics', () async {
      biometrics.available = false;
      final auth = await notifierFrom(buildContainer());
      await auth.setupCredential(strongPin, CredentialKind.pin);

      final enabled = await auth.setBiometricUnlockEnabled(true);

      expect(enabled, isFalse);
      expect(await repository.getStoredMasterKey(), isNull);
    });

    test('unlocks when the prompt succeeds', () async {
      final first = await notifierFrom(buildContainer());
      await first.setupCredential(strongPin, CredentialKind.pin);
      await first.setBiometricUnlockEnabled(true);

      final relaunched = await notifierFrom(buildContainer());
      final unlocked = await relaunched.unlockWithBiometrics();

      expect(unlocked, isTrue);
      expect(relaunched.state.masterKey, isNotNull);
    });

    test('fails closed when the prompt is refused', () async {
      final first = await notifierFrom(buildContainer());
      await first.setupCredential(strongPin, CredentialKind.pin);
      await first.setBiometricUnlockEnabled(true);

      biometrics.willSucceed = false;
      final relaunched = await notifierFrom(buildContainer());
      final unlocked = await relaunched.unlockWithBiometrics();

      expect(unlocked, isFalse);
      expect(relaunched.state.isLocked, isTrue);
      expect(relaunched.state.masterKey, isNull);
    });

    test('does not prompt while it is disabled', () async {
      final first = await notifierFrom(buildContainer());
      await first.setupCredential(strongPin, CredentialKind.pin);

      final relaunched = await notifierFrom(buildContainer());
      await relaunched.unlockWithBiometrics();

      expect(biometrics.prompts, 0);
    });
  });

  group('credential rotation policy', () {
    Future<void> seedCredentialSetLongAgo() async {
      await store.write(
        AuthRepository.credentialLastSetKey,
        DateTime.now().subtract(const Duration(days: 400)).toIso8601String(),
      );
    }

    test('an old credential is not expired by default', () async {
      // Regression guard: rotation was documented as opt-in but applied to
      // every user, forcing a rotation prompt nobody asked for.
      final first = await notifierFrom(buildContainer());
      await first.setupCredential(strongPin, CredentialKind.pin);
      await seedCredentialSetLongAgo();

      final relaunched = await notifierFrom(buildContainer());

      expect(relaunched.state.isCredentialExpired, isFalse);
    });

    test('an old credential expires once rotation is enabled', () async {
      final first = await notifierFrom(buildContainer());
      await first.setupCredential(strongPin, CredentialKind.pin);
      await seedCredentialSetLongAgo();
      SharedPreferences.setMockInitialValues({
        'settings_credentialRotationEnabled': true,
        'settings_credentialRotationDays': 90,
      });

      final relaunched = await notifierFrom(buildContainer());

      expect(relaunched.state.isCredentialExpired, isTrue);
    });
  });

  group('changing the credential', () {
    test('switches from a PIN to a passphrase without losing accounts',
        () async {
      final auth = await notifierFrom(buildContainer());
      await auth.setupCredential(strongPin, CredentialKind.pin);

      final accounts = AccountRepository(store: store, vault: vault);
      await accounts.addAccount(
        OtpAccount(
          id: '1',
          issuer: 'GitHub',
          accountName: 'dev@example.com',
          secret: 'JBSWY3DPEHPK3PXP',
        ),
        masterKey: auth.state.masterKey,
      );

      final error = await auth.changeCredential(
        current: strongPin,
        next: strongPassphrase,
        kind: CredentialKind.passphrase,
      );

      expect(error, isNull);
      expect(await vault.credentialKind(), CredentialKind.passphrase);

      final key = (await vault.unlock(strongPassphrase)).key!;
      final loaded = await accounts.getAccounts(masterKey: key);
      expect(loaded.single.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('refuses a new credential that fails policy', () async {
      final auth = await notifierFrom(buildContainer());
      await auth.setupCredential(strongPin, CredentialKind.pin);

      final error = await auth.changeCredential(
        current: strongPin,
        next: '123456',
        kind: CredentialKind.pin,
      );

      expect(error, isNotNull);
      expect((await vault.unlock(strongPin)).isUnlocked, isTrue,
          reason: 'the original credential must keep working');
    });

    test('refuses when the current credential is wrong', () async {
      final auth = await notifierFrom(buildContainer());
      await auth.setupCredential(strongPin, CredentialKind.pin);

      final error = await auth.changeCredential(
        current: otherPin,
        next: strongPassphrase,
        kind: CredentialKind.passphrase,
      );

      expect(error, isNotNull);
      expect(await vault.credentialKind(), CredentialKind.pin);
    });

    test('re-caches the key for biometrics under the new credential',
        () async {
      final auth = await notifierFrom(buildContainer());
      await auth.setupCredential(strongPin, CredentialKind.pin);
      await auth.setBiometricUnlockEnabled(true);

      await auth.changeCredential(
        current: strongPin,
        next: strongPassphrase,
        kind: CredentialKind.passphrase,
      );

      // The old cached key would no longer open a re-keyed vault, so leaving
      // it in place would break biometric unlock silently.
      final cached = await repository.getStoredMasterKey();
      final expected = (await vault.unlock(strongPassphrase)).key;
      expect(cached, expected);
    });
  });
}

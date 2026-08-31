import 'dart:convert';

import 'package:base32/base32.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/repositories/account_repository.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_uri.dart';
import 'package:dula_auth/core/security/biometric_authenticator.dart';
import 'package:dula_auth/core/security/credential_kind.dart';
import 'package:dula_auth/core/settings/settings_repository.dart';
import 'package:dula_auth/core/vault/secret_store.dart';
import 'package:dula_auth/core/vault/vault_service.dart';
import 'package:dula_auth/core/widgets/app_lifecycle_wrapper.dart';
import 'package:dula_auth/features/auth/providers/auth_provider.dart';
import 'package:dula_auth/features/auth/repositories/auth_repository.dart';
import 'package:dula_auth/features/home/screens/home_screen.dart';

/// Biometric stub.
///
/// Whether the host has Windows Hello enrolled would otherwise decide which
/// screens appear, making this suite pass or fail on machine configuration
/// rather than on the code.
class _StubBiometrics implements BiometricAuthenticator {
  final bool available;
  final bool approves;

  const _StubBiometrics({this.available = false, this.approves = true});

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async => available && approves;
}

/// End-to-end coverage of the real widget tree against the real
/// platform-backed secure store: credential setup, adding accounts, code
/// generation, lock, and unlock.
///
/// Uses production KDF parameters, so this also proves unlock stays responsive
/// at the cost settings the app actually ships (ADR-0010).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const store = FlutterSecretStore();
  final vault = VaultService(store);
  final accounts = AccountRepository(store: store, vault: vault);
  final settings = SettingsRepository();

  const pin = '481629';
  const otherPin = '750392';
  const passphrase = 'rope anchor lantern';

  Future<void> wipe() async {
    await AuthRepository(store: store, vault: vault).clearAuthData();
    await settings.clear();
  }

  setUp(wipe);
  tearDownAll(wipe);

  Future<void> pumpApp(
    WidgetTester tester, {
    _StubBiometrics biometrics = const _StubBiometrics(),
  }) async {
    final branding = await BrandingConfig.load();
    await tester.pumpWidget(
      ProviderScope(
        // A fresh key forces a new element, and so a new provider container.
        // Without it a second pumpApp merely updates the existing scope, which
        // keeps the old (possibly unlocked) auth state — that is an app resume,
        // not the relaunch these tests mean to exercise.
        key: UniqueKey(),
        overrides: [
          brandingConfigProvider.overrideWithValue(branding),
          authRepositoryProvider.overrideWithValue(
            AuthRepository(store: store, vault: vault, biometrics: biometrics),
          ),
        ],
        child: MaterialApp(
          title: branding.appName,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: branding.primarySeedColor,
              brightness: Brightness.dark,
            ),
          ),
          home: const AppLifecycleWrapper(child: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// Picks a credential type on the first-run choice screen.
  Future<void> chooseKind(WidgetTester tester, CredentialKind kind) async {
    await tester.tap(find.text(kind.label));
    await tester.pumpAndSettle();
  }

  Future<void> enterPin(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tester.tap(find.widgetWithText(InkWell, digit).first);
      await tester.pump(const Duration(milliseconds: 60));
    }
    // Argon2id derivation runs here, so allow real time to elapse.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  Future<void> enterPassphrase(
    WidgetTester tester,
    String value,
    String buttonLabel,
  ) async {
    // Tap first: after the field is cleared programmatically between steps,
    // the test harness's text input needs the focus re-established or the
    // entered text goes nowhere.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, value);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, buttonLabel));
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  group('first run', () {
    testWidgets('offers a choice of credential', (tester) async {
      await pumpApp(tester);

      expect(find.text('How would you like to unlock?'), findsOneWidget);
      expect(find.text(CredentialKind.pin.label), findsOneWidget);
      expect(find.text(CredentialKind.passphrase.label), findsOneWidget);
    });

    testWidgets('creating a PIN unlocks the app', (tester) async {
      await pumpApp(tester);
      await chooseKind(tester, CredentialKind.pin);

      expect(find.text('Create 6-Digit PIN'), findsOneWidget);
      await enterPin(tester, pin);

      expect(find.text('Confirm PIN'), findsOneWidget,
          reason: 'setup must ask for confirmation');
      await enterPin(tester, pin);

      expect(find.text('No Accounts Yet'), findsOneWidget,
          reason: 'a completed setup lands on the account list');
      expect(await vault.credentialKind(), CredentialKind.pin);
    });

    testWidgets('creating a passphrase unlocks the app', (tester) async {
      await pumpApp(tester);
      await chooseKind(tester, CredentialKind.passphrase);

      expect(find.text('Create Passphrase'), findsOneWidget);
      await enterPassphrase(tester, passphrase, 'Continue');

      expect(find.text('Confirm Passphrase'), findsOneWidget);
      await enterPassphrase(tester, passphrase, 'Confirm');

      expect(find.text('No Accounts Yet'), findsOneWidget);
      expect(await vault.credentialKind(), CredentialKind.passphrase,
          reason: 'the lock screen needs this to show a text field');
    });

    testWidgets('rejects a weak PIN before it is ever stored', (tester) async {
      await pumpApp(tester);
      await chooseKind(tester, CredentialKind.pin);

      // 123456 is both a sequential run and on the breached-PIN blocklist; the
      // blocklist check runs first, so that is the message the user sees.
      await enterPin(tester, '123456');

      expect(find.textContaining('too common'), findsOneWidget);
      expect(find.text('Confirm PIN'), findsNothing,
          reason: 'a rejected PIN must not advance to confirmation');
      expect(await vault.isInitialized(), isFalse,
          reason: 'a rejected PIN must not create a vault');
    });

    testWidgets('rejects a short passphrase before it is ever stored',
        (tester) async {
      await pumpApp(tester);
      await chooseKind(tester, CredentialKind.passphrase);

      await enterPassphrase(tester, 'short', 'Continue');

      expect(find.textContaining('at least 12'), findsOneWidget);
      expect(await vault.isInitialized(), isFalse);
    });

    testWidgets('mismatched confirmation does not create a vault',
        (tester) async {
      await pumpApp(tester);
      await chooseKind(tester, CredentialKind.pin);

      await enterPin(tester, pin);
      await enterPin(tester, otherPin);

      expect(find.textContaining('do not match'), findsOneWidget);
      expect(await vault.isInitialized(), isFalse);
    });

    testWidgets('offers biometrics only where the platform supports them',
        (tester) async {
      await pumpApp(tester, biometrics: const _StubBiometrics(available: true));
      await chooseKind(tester, CredentialKind.pin);
      await enterPin(tester, pin);
      await enterPin(tester, pin);

      expect(find.text('Unlock with biometrics?'), findsOneWidget,
          reason: 'a capable device should be offered the faster unlock');

      // Declining must still complete setup — biometrics are never required.
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('No Accounts Yet'), findsOneWidget);
      expect(await store.read(AuthRepository.masterKeyKey), isNull,
          reason: 'declining biometrics must not cache the vault key');
    });
  });

  group('unlocking', () {
    testWidgets('stored accounts appear with a live code after unlock',
        (tester) async {
      // Seed the vault as a returning user with two enrolled accounts.
      final key = await vault.initialize(pin, kind: CredentialKind.pin);
      await accounts.addAccount(
        OtpAccount(
          id: '1',
          issuer: 'GitHub',
          accountName: 'dev@example.com',
          secret: 'JBSWY3DPEHPK3PXP',
        ),
        masterKey: key,
      );
      await accounts.addAccount(
        OtpAccount(
          id: '2',
          issuer: 'AWS',
          accountName: 'ops@example.com',
          secret: 'KRSXG5CTMVRXEZLU',
        ),
        masterKey: key,
      );

      await pumpApp(tester);
      expect(find.text('Enter PIN'), findsOneWidget,
          reason: 'an existing vault must be locked on launch');

      await enterPin(tester, pin);

      // Both accounts are listed — the app is no longer single-account.
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('AWS'), findsOneWidget);
      expect(find.text('dev@example.com'), findsOneWidget);

      // And a six-digit code is rendered for them.
      final codeFinder = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            RegExp(r'^\d{3} \d{3}$').hasMatch(w.data!),
      );
      expect(codeFinder, findsNWidgets(2));
    });

    testWidgets('a passphrase vault asks for a passphrase, not a keypad',
        (tester) async {
      await vault.initialize(passphrase, kind: CredentialKind.passphrase);

      await pumpApp(tester);

      expect(find.text('Enter Passphrase'), findsOneWidget);
      expect(find.widgetWithText(InkWell, '1'), findsNothing,
          reason: 'a keypad cannot express a passphrase');

      await tester.enterText(find.byType(TextField).first, passphrase);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('No Accounts Yet'), findsOneWidget);
    });

    testWidgets('an enabled fingerprint opens the vault on launch',
        (tester) async {
      // Set up with biometrics accepted, then relaunch: the lock screen
      // prompts on its own and the cached key opens the vault.
      await pumpApp(tester, biometrics: const _StubBiometrics(available: true));
      await chooseKind(tester, CredentialKind.pin);
      await enterPin(tester, pin);
      await enterPin(tester, pin);
      await tester.tap(find.text('Enable biometric unlock'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await pumpApp(tester, biometrics: const _StubBiometrics(available: true));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('No Accounts Yet'), findsOneWidget);
    });

    testWidgets('a refused fingerprint leaves the credential in charge',
        (tester) async {
      await pumpApp(tester, biometrics: const _StubBiometrics(available: true));
      await chooseKind(tester, CredentialKind.pin);
      await enterPin(tester, pin);
      await enterPin(tester, pin);
      await tester.tap(find.text('Enable biometric unlock'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await pumpApp(
        tester,
        biometrics: const _StubBiometrics(available: true, approves: false),
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('Enter PIN'), findsOneWidget,
          reason: 'a failed fingerprint must fall back, never let you in');

      // And the PIN still works, which is the guarantee that matters.
      await enterPin(tester, pin);
      expect(find.text('No Accounts Yet'), findsOneWidget);
    });

    testWidgets('a wrong PIN keeps the vault closed', (tester) async {
      await vault.initialize(pin, kind: CredentialKind.pin);
      await pumpApp(tester);

      await enterPin(tester, otherPin);

      expect(find.text('Incorrect PIN'), findsOneWidget);
      expect(find.text('No Accounts Yet'), findsNothing);
    });

    testWidgets('secrets are unreadable without the right credential',
        (tester) async {
      final key = await vault.initialize(pin, kind: CredentialKind.pin);
      await accounts.addAccount(
        OtpAccount(
          id: '1',
          issuer: 'GitHub',
          accountName: 'dev@example.com',
          secret: 'JBSWY3DPEHPK3PXP',
        ),
        masterKey: key,
      );

      // A key derived from a different credential must not open the secret.
      final otherVault = VaultService(InMemorySecretStore({}));
      final wrongKey = await otherVault.initialize(otherPin);

      final loaded = await accounts.getAccounts(masterKey: wrongKey);

      expect(loaded.single.loadError, isNotNull);
      expect(loaded.single.secret, isNot('JBSWY3DPEHPK3PXP'));
    });

    testWidgets('unlock at production KDF cost stays responsive',
        (tester) async {
      await vault.initialize(pin, kind: CredentialKind.pin);

      final stopwatch = Stopwatch()..start();
      final result = await vault.unlock(pin);
      stopwatch.stop();

      expect(result.isUnlocked, isTrue);
      // ignore: avoid_print
      print('Production unlock took ${stopwatch.elapsedMilliseconds} ms '
          '(Argon2id m=${KdfParams.owaspDefault.memoryKiB} KiB)');
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
    });
  });

  group('OTP types', () {
    testWidgets('renders an 8-digit SHA-256 credential correctly',
        (tester) async {
      // Regression guard for the parameter-dropping bug: digits/period/
      // algorithm used to be parsed and then discarded, so a credential like
      // this rendered a 6-digit SHA-1 code — plausible, and wrong.
      final key = await vault.initialize(pin, kind: CredentialKind.pin);
      final scanned = OtpUri.parse(
        'otpauth://totp/Bank:ops@example.com?secret=JBSWY3DPEHPK3PXP'
        '&digits=8&period=60&algorithm=SHA256',
        id: '1',
      )!;
      await accounts.addAccount(scanned, masterKey: key);

      await pumpApp(tester);
      await enterPin(tester, pin);

      expect(find.text('Bank'), findsOneWidget);
      // 8-digit codes are grouped 4+4.
      expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
            w.data != null &&
            RegExp(r'^\d{4} \d{4}$').hasMatch(w.data!)),
        findsOneWidget,
      );

      final stored = (await accounts.getAccounts(masterKey: key)).single;
      expect(stored.digits, 8);
      expect(stored.period, 60);
      expect(stored.algorithm, OtpAlgorithm.sha256);
    });

    testWidgets('renders a Steam credential as five characters',
        (tester) async {
      final key = await vault.initialize(pin, kind: CredentialKind.pin);
      await accounts.addAccount(
        OtpUri.parse(
          'otpauth://steam/Steam:gamer?secret=JBSWY3DPEHPK3PXP',
          id: '1',
        )!,
        masterKey: key,
      );

      await pumpApp(tester);
      await enterPin(tester, pin);

      expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
            w.data != null &&
            RegExp(r'^[23456789BCDFGHJKMNPQRTVWXY]{5}$').hasMatch(w.data!)),
        findsOneWidget,
      );
    });

    testWidgets('an HOTP credential offers an advance control', (tester) async {
      final key = await vault.initialize(pin, kind: CredentialKind.pin);
      await accounts.addAccount(
        OtpUri.parse(
          'otpauth://hotp/Token:alice?secret=JBSWY3DPEHPK3PXP&counter=0',
          id: '1',
        )!,
        masterKey: key,
      );

      await pumpApp(tester);
      await enterPin(tester, pin);

      // Counter-based codes never expire on a clock, so they show a refresh
      // action rather than a countdown dial.
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final stored = (await accounts.getAccounts(masterKey: key)).single;
      expect(stored.counter, 1,
          reason: 'advancing must persist the new counter');
    });
  });

  group('account management', () {
    testWidgets('search narrows the list to matching accounts',
        (tester) async {
      final key = await vault.initialize(pin, kind: CredentialKind.pin);
      await accounts.addAccount(
        OtpAccount(
            id: '1',
            issuer: 'GitHub',
            accountName: 'dev@example.com',
            secret: 'JBSWY3DPEHPK3PXP'),
        masterKey: key,
      );
      await accounts.addAccount(
        OtpAccount(
            id: '2',
            issuer: 'AWS',
            accountName: 'ops@example.com',
            secret: 'KRSXG5CTMVRXEZLU'),
        masterKey: key,
      );

      await pumpApp(tester);
      await enterPin(tester, pin);

      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('AWS'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'git');
      await tester.pumpAndSettle();

      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('AWS'), findsNothing);
    });

    testWidgets('toggling favorite persists and filters via the chip',
        (tester) async {
      final key = await vault.initialize(pin, kind: CredentialKind.pin);
      await accounts.addAccount(
        OtpAccount(
            id: '1',
            issuer: 'GitHub',
            accountName: 'dev@example.com',
            secret: 'JBSWY3DPEHPK3PXP'),
        masterKey: key,
      );
      await accounts.addAccount(
        OtpAccount(
            id: '2',
            issuer: 'AWS',
            accountName: 'ops@example.com',
            secret: 'KRSXG5CTMVRXEZLU'),
        masterKey: key,
      );

      await pumpApp(tester);
      await enterPin(tester, pin);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to favorites'));
      await tester.pumpAndSettle();

      final stored = await accounts.getAccounts(masterKey: key);
      expect(stored.firstWhere((a) => a.issuer == 'GitHub').isFavorite, isTrue);

      await tester.tap(find.text('★ Favorites'));
      await tester.pumpAndSettle();

      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('AWS'), findsNothing);
    });

    testWidgets('adding a tag persists and appears as a filter chip',
        (tester) async {
      final key = await vault.initialize(pin, kind: CredentialKind.pin);
      await accounts.addAccount(
        OtpAccount(
            id: '1',
            issuer: 'GitHub',
            accountName: 'dev@example.com',
            secret: 'JBSWY3DPEHPK3PXP'),
        masterKey: key,
      );

      await pumpApp(tester);
      await enterPin(tester, pin);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage tags'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'work');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final stored =
          (await accounts.getAccounts(masterKey: key)).single;
      expect(stored.tags, ['work']);
      expect(find.widgetWithText(FilterChip, 'work'), findsOneWidget);
    });

    testWidgets('editing an account persists the change without a new id',
        (tester) async {
      final key = await vault.initialize(pin, kind: CredentialKind.pin);
      await accounts.addAccount(
        OtpAccount(
            id: '1',
            issuer: 'GitHub',
            accountName: 'dev@example.com',
            secret: 'JBSWY3DPEHPK3PXP'),
        masterKey: key,
      );

      await pumpApp(tester);
      await enterPin(tester, pin);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Account'), findsOneWidget);
      expect(find.text('Scan QR Code with Camera'), findsNothing,
          reason: 'there is nothing to scan when editing text fields');

      final issuerField = find.widgetWithText(TextFormField,
          'Issuer (e.g. Google, GitHub)');
      await tester.enterText(issuerField, 'GitHub Enterprise');
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();

      final stored =
          (await accounts.getAccounts(masterKey: key)).single;
      expect(stored.id, '1', reason: 'editing must not create a new account');
      expect(stored.issuer, 'GitHub Enterprise');
      expect(stored.secret, 'JBSWY3DPEHPK3PXP');
    });

    testWidgets('a corrupted account is isolated, not blocking the list',
        (tester) async {
      final key = await vault.initialize(pin, kind: CredentialKind.pin);
      await accounts.addAccount(
        OtpAccount(
            id: '1',
            issuer: 'GitHub',
            accountName: 'dev@example.com',
            secret: 'JBSWY3DPEHPK3PXP'),
        masterKey: key,
      );
      await accounts.addAccount(
        OtpAccount(
            id: '2',
            issuer: 'AWS',
            accountName: 'ops@example.com',
            secret: 'KRSXG5CTMVRXEZLU'),
        masterKey: key,
      );

      // Corrupt the second account's ciphertext directly in storage.
      final raw = jsonDecode(await store.read(VaultService.accountsKey) as String)
          as List;
      final entry = raw.firstWhere((e) => e['id'] == '2') as Map<String, dynamic>;
      final sealed = base64.decode(entry['secret'] as String);
      sealed[sealed.length ~/ 2] ^= 0x01;
      entry['secret'] = base64.encode(sealed);
      await store.write(VaultService.accountsKey, jsonEncode(raw));

      await pumpApp(tester);
      await enterPin(tester, pin);

      // The healthy account still renders normally...
      expect(find.text('GitHub'), findsOneWidget);
      final codeFinder = find.byWidgetPredicate(
        (w) => w is Text && w.data != null && RegExp(r'^\d{3} \d{3}$').hasMatch(w.data!),
      );
      expect(codeFinder, findsOneWidget);

      // ...and the corrupted one is clearly marked rather than crashing the
      // whole screen.
      expect(find.text('AWS'), findsOneWidget);
      expect(find.textContaining('Could not read'), findsOneWidget);

      // Swiping it away removes only that account, once confirmed.
      await tester.drag(find.text('AWS'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DELETE'));
      await tester.pumpAndSettle();

      // The corrupted card is gone and only the healthy account remains —
      // the user-visible proof the delete worked.
      expect(find.text('AWS'), findsNothing);
      expect(find.text('GitHub'), findsOneWidget);

      // Re-reading storage through a second, independent AccountRepository
      // races the native secure-storage write on Windows if checked
      // immediately; a brief real wait lets that write flush before this
      // out-of-band check, same as the production write path already does.
      await tester.pump(const Duration(seconds: 1));
      final remaining = await accounts.getAccounts(masterKey: key);
      expect(remaining.single.id, '1');
    });

    testWidgets('drag-reorder persists the new order', (tester) async {
      final key = await vault.initialize(pin, kind: CredentialKind.pin);
      await accounts.addAccount(
        OtpAccount(
            id: '1',
            issuer: 'One',
            accountName: 'a@example.com',
            secret: 'JBSWY3DPEHPK3PXP'),
        masterKey: key,
      );
      await accounts.addAccount(
        OtpAccount(
            id: '2',
            issuer: 'Two',
            accountName: 'b@example.com',
            secret: 'KRSXG5CTMVRXEZLU'),
        masterKey: key,
      );

      await pumpApp(tester);
      await enterPin(tester, pin);

      expect(find.byType(ReorderableListView), findsOneWidget,
          reason: 'the unfiltered list must be manually reorderable');

      // A single tester.drag() does not reliably register as a reorder
      // gesture on ReorderableListView — it needs a held pointer with
      // intermediate moves, the same pattern Flutter's own reorderable-list
      // tests use, rather than one instantaneous drag.
      final handle = find.byIcon(Icons.drag_handle);
      expect(handle, findsWidgets);
      final gesture = await tester.startGesture(tester.getCenter(handle.first));
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 80));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();

      final stored = await accounts.getAccounts(masterKey: key);
      expect(stored.map((a) => a.id), ['2', '1']);
    });
  });

  group('settings', () {
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
    }

    testWidgets('are reachable from the account list', (tester) async {
      await vault.initialize(pin, kind: CredentialKind.pin);
      await pumpApp(tester);
      await enterPin(tester, pin);

      await openSettings(tester);

      expect(find.text('Unlock with biometrics'), findsOneWidget);
      expect(find.text('Change PIN or passphrase'), findsOneWidget);
    });

    testWidgets('explain rather than offer biometrics where unsupported',
        (tester) async {
      await vault.initialize(pin, kind: CredentialKind.pin);
      await pumpApp(tester);
      await enterPin(tester, pin);

      await openSettings(tester);

      expect(
        find.textContaining('Not available on this device'),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsOneWidget,
          reason: 'only the rotation switch should remain');
    });

    testWidgets('the auto-lock delay persists', (tester) async {
      await vault.initialize(pin, kind: CredentialKind.pin);
      await pumpApp(tester);
      await enterPin(tester, pin);
      await openSettings(tester);

      await tester.tap(find.text('After 30 seconds').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('After 5 minutes').last);
      await tester.pumpAndSettle();

      expect((await settings.load()).autoLock.label, 'After 5 minutes');
    });

    testWidgets('forced rotation is off out of the box', (tester) async {
      await vault.initialize(pin, kind: CredentialKind.pin);
      await pumpApp(tester);
      await enterPin(tester, pin);
      await openSettings(tester);

      expect(find.text('Off — recommended'), findsOneWidget,
          reason: 'NIST advises against forced rotation; it must be opt-in');
    });
  });

  group('backup import', () {
    // File-based import (own backup, Aegis, 2FAS) opens a native OS file
    // dialog via file_picker, which cannot be driven by an automated test —
    // that logic is covered directly in test/core/backup/. This suite
    // exercises the paste-a-code path end to end, through the real widget
    // tree and the real vault, which needs no native dialog.

    Future<void> openImportScreen(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      // The Backup section sits below the fold on a small window; scroll it
      // into view before tapping rather than hitting whatever else is there.
      await tester.ensureVisible(find.text('Import accounts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import accounts'));
      await tester.pumpAndSettle();
    }

    testWidgets('a pasted otpauth link is added after review', (tester) async {
      await vault.initialize(pin, kind: CredentialKind.pin);
      await pumpApp(tester);
      await enterPin(tester, pin);
      await openImportScreen(tester);

      await tester.enterText(
        find.byType(TextField).first,
        'otpauth://totp/GitHub:dev@example.com?secret=JBSWY3DPEHPK3PXP',
      );
      await tester.ensureVisible(find.text('Import from code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import from code'));
      await tester.pumpAndSettle();

      expect(find.text('NEW (1)'), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);

      await tester.ensureVisible(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('dev@example.com'), findsOneWidget);

      final key = (await vault.unlock(pin)).key!;
      final stored = await accounts.getAccounts(masterKey: key);
      expect(stored.single.secret, 'JBSWY3DPEHPK3PXP');
    });

    testWidgets('a batch migration code lets the user deselect entries',
        (tester) async {
      await vault.initialize(pin, kind: CredentialKind.pin);
      await pumpApp(tester);
      await enterPin(tester, pin);
      await openImportScreen(tester);

      await tester.enterText(
        find.byType(TextField).first,
        _migrationUriWith(issuers: ['One', 'Two']),
      );
      await tester.ensureVisible(find.text('Import from code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import from code'));
      await tester.pumpAndSettle();

      expect(find.text('NEW (2)'), findsOneWidget);
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);

      // Deselect "Two" before committing.
      await tester.ensureVisible(find.widgetWithText(CheckboxListTile, 'Two'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Two'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Import (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import (1)'));
      await tester.pumpAndSettle();

      final key = (await vault.unlock(pin)).key!;
      final stored = await accounts.getAccounts(masterKey: key);
      expect(stored.map((a) => a.issuer), ['One']);
    });

    testWidgets('an unreadable code shows an error and imports nothing',
        (tester) async {
      await vault.initialize(pin, kind: CredentialKind.pin);
      await pumpApp(tester);
      await enterPin(tester, pin);
      await openImportScreen(tester);

      await tester.enterText(
        find.byType(TextField).first,
        'this is not a code at all',
      );
      await tester.ensureVisible(find.text('Import from code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import from code'));
      await tester.pumpAndSettle();

      expect(find.textContaining('does not look like'), findsOneWidget);
      expect(find.text('New'), findsNothing);

      final key = (await vault.unlock(pin)).key!;
      expect(await accounts.getAccounts(masterKey: key), isEmpty);
    });

    testWidgets('importing the same code twice treats the second as a duplicate',
        (tester) async {
      final key = await vault.initialize(pin, kind: CredentialKind.pin);
      await accounts.addAccount(
        OtpAccount(
          id: 'seed',
          issuer: 'GitHub',
          accountName: 'dev@example.com',
          secret: 'JBSWY3DPEHPK3PXP',
        ),
        masterKey: key,
      );

      await pumpApp(tester);
      await enterPin(tester, pin);
      await openImportScreen(tester);

      await tester.enterText(
        find.byType(TextField).first,
        'otpauth://totp/GitHub:dev@example.com?secret=JBSWY3DPEHPK3PXP',
      );
      await tester.ensureVisible(find.text('Import from code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import from code'));
      await tester.pumpAndSettle();

      expect(find.text('ALREADY IN YOUR VAULT (1)'), findsOneWidget);
      expect(find.text('NEW ('), findsNothing);
    });
  });
}

/// Builds an `otpauth-migration://` payload with one entry per issuer, using
/// the same protobuf wire-format rules the decoder implements — written
/// independently here rather than imported from it, so this test cannot pass
/// merely because both sides share a bug.
String _migrationUriWith({required List<String> issuers}) {
  List<int> varint(int value) {
    final out = <int>[];
    var v = value;
    while (true) {
      final byte = v & 0x7f;
      v >>= 7;
      if (v != 0) {
        out.add(byte | 0x80);
      } else {
        out.add(byte);
        break;
      }
    }
    return out;
  }

  List<int> tag(int fieldNumber, int wireType) =>
      varint((fieldNumber << 3) | wireType);

  List<int> lengthDelimited(int fieldNumber, List<int> data) =>
      [...tag(fieldNumber, 2), ...varint(data.length), ...data];

  final secretBytes = base32.decode('JBSWY3DPEHPK3PXP');
  final payload = <int>[];
  for (final issuer in issuers) {
    final entry = <int>[
      ...lengthDelimited(1, secretBytes),
      ...lengthDelimited(2, utf8.encode('user@example.com')),
      ...lengthDelimited(3, utf8.encode(issuer)),
    ];
    payload.addAll(lengthDelimited(1, entry));
  }

  return 'otpauth-migration://offline?data='
      '${Uri.encodeComponent(base64.encode(payload))}';
}

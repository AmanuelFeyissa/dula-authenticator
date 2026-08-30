import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/repositories/account_repository.dart';
import 'package:dula_auth/core/models/totp_account.dart';
import 'package:dula_auth/core/vault/secret_store.dart';
import 'package:dula_auth/core/vault/vault_service.dart';
import 'package:dula_auth/core/widgets/app_lifecycle_wrapper.dart';
import 'package:dula_auth/features/home/screens/home_screen.dart';

/// End-to-end coverage of the real widget tree against the real
/// platform-backed secure store: PIN setup, adding accounts, code generation,
/// lock, and unlock.
///
/// Uses production KDF parameters, so this also proves unlock stays responsive
/// at the cost settings the app actually ships (ADR-0010).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const store = FlutterSecretStore();
  final vault = VaultService(store);
  final accounts = AccountRepository(store: store, vault: vault);

  const pin = '481629';
  const otherPin = '750392';

  setUp(() async {
    // Each test starts from a clean install.
    await vault.reset();
  });

  tearDownAll(() async {
    await vault.reset();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    final branding = await BrandingConfig.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [brandingConfigProvider.overrideWithValue(branding)],
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

  Future<void> enterPin(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tester.tap(find.widgetWithText(InkWell, digit).first);
      await tester.pump(const Duration(milliseconds: 60));
    }
    // Argon2id derivation runs here, so allow real time to elapse.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  testWidgets('first run asks the user to create a PIN', (tester) async {
    await pumpApp(tester);

    expect(find.text('Create 6-Digit PIN'), findsOneWidget);
  });

  testWidgets('creating a PIN unlocks the app', (tester) async {
    await pumpApp(tester);

    await enterPin(tester, pin);
    expect(find.text('Confirm PIN'), findsOneWidget,
        reason: 'setup must ask for confirmation');

    await enterPin(tester, pin);

    expect(find.text('No Accounts Yet'), findsOneWidget,
        reason: 'a completed setup lands on the account list');
  });

  testWidgets('rejects a weak PIN before it is ever stored', (tester) async {
    await pumpApp(tester);

    // 123456 is both a sequential run and on the breached-PIN blocklist; the
    // blocklist check runs first, so that is the message the user sees.
    await enterPin(tester, '123456');

    expect(find.textContaining('too common'), findsOneWidget);
    expect(find.text('Confirm PIN'), findsNothing,
        reason: 'a rejected PIN must not advance to confirmation');
    expect(await vault.isInitialized(), isFalse,
        reason: 'a rejected PIN must not create a vault');
  });

  testWidgets('mismatched confirmation does not create a vault',
      (tester) async {
    await pumpApp(tester);

    await enterPin(tester, pin);
    await enterPin(tester, otherPin);

    expect(find.textContaining('do not match'), findsOneWidget);
    expect(await vault.isInitialized(), isFalse);
  });

  testWidgets('stored accounts appear with a live code after unlock',
      (tester) async {
    // Seed the vault as a returning user with two enrolled accounts.
    final key = await vault.initialize(pin);
    await accounts.addAccount(
      TotpAccount(
        id: '1',
        issuer: 'GitHub',
        accountName: 'dev@example.com',
        secret: 'JBSWY3DPEHPK3PXP',
      ),
      masterKey: key,
    );
    await accounts.addAccount(
      TotpAccount(
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
      (w) => w is Text && w.data != null && RegExp(r'^\d{3} \d{3}$').hasMatch(w.data!),
    );
    expect(codeFinder, findsNWidgets(2));
  });

  testWidgets('a wrong PIN keeps the vault closed', (tester) async {
    await vault.initialize(pin);
    await pumpApp(tester);

    await enterPin(tester, otherPin);

    expect(find.text('Incorrect PIN'), findsOneWidget);
    expect(find.text('No Accounts Yet'), findsNothing);
  });

  testWidgets('secrets are unreadable without the right credential',
      (tester) async {
    final key = await vault.initialize(pin);
    await accounts.addAccount(
      TotpAccount(
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

    expect(
      () => accounts.getAccounts(masterKey: wrongKey),
      throwsA(isA<VaultDecryptionException>()),
    );
  });

  testWidgets('unlock at production KDF cost stays responsive', (tester) async {
    await vault.initialize(pin);

    final stopwatch = Stopwatch()..start();
    final result = await vault.unlock(pin);
    stopwatch.stop();

    expect(result.isUnlocked, isTrue);
    // ignore: avoid_print
    print('Production unlock took ${stopwatch.elapsedMilliseconds} ms '
        '(Argon2id m=${KdfParams.owaspDefault.memoryKiB} KiB)');
    expect(stopwatch.elapsedMilliseconds, lessThan(3000));
  });
}

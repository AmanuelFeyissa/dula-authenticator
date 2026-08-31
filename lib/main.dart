import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dula_auth/core/app_version.dart';
import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/core/config/deployment_config.dart';
import 'package:dula_auth/core/crypto/vault_crypto.dart';
import 'package:dula_auth/core/security/lockout_policy.dart';
import 'package:dula_auth/core/security/passphrase_policy.dart';
import 'package:dula_auth/core/security/pin_policy.dart';
import 'package:dula_auth/core/settings/app_settings.dart';
import 'package:dula_auth/core/theme/app_theme.dart';
import 'package:dula_auth/core/widgets/app_lifecycle_wrapper.dart';
import 'package:dula_auth/features/home/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final branding = await BrandingConfig.load();
  final deployment = await DeploymentConfig.load();
  final packageInfo = await PackageInfo.fromPlatform();
  _applyDeploymentConfig(deployment);
  runApp(
    ProviderScope(
      overrides: [
        brandingConfigProvider.overrideWithValue(branding),
        deploymentConfigProvider.overrideWithValue(deployment),
        packageInfoProvider.overrideWithValue(packageInfo),
      ],
      child: MyApp(branding: branding),
    ),
  );
}

/// Pushes [config] into every static-utility policy class that has no
/// dependency-injection path of its own — see
/// docs/adr/0016-deployment-configuration.md Decision item 2. Must run
/// before any of these classes is used, so it happens before [runApp].
void _applyDeploymentConfig(DeploymentConfig config) {
  PinPolicy.configure(pinLength: config.pinLength);
  PassphrasePolicy.configure(
    minLength: config.passphraseMinLength,
    recommendedLength: config.passphraseRecommendedLength,
    maxLength: config.passphraseMaxLength,
  );
  KdfParams.configureDefault(KdfParams(
    memoryKiB: config.argon2MemoryKiB,
    iterations: config.argon2Iterations,
    parallelism: config.argon2Parallelism,
  ));
  LockoutPolicy.configure(config.lockoutSteps);
  AppSettings.configureDefaults(
    autoLock: config.defaultAutoLock,
    rotationDays: config.credentialRotationDefaultDays,
    minRotationDays: config.credentialRotationMinDays,
    maxRotationDays: config.credentialRotationMaxDays,
  );
}

class MyApp extends StatelessWidget {
  final BrandingConfig branding;

  const MyApp({super.key, required this.branding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: branding.appName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(branding),
      // AppLifecycleWrapper manages the lock screen overlay
      home: const AppLifecycleWrapper(
        child: HomeScreen(),
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dula_auth/core/settings/app_settings.dart';

/// One failed-unlock lockout threshold: at [attempts] or more consecutive
/// failures, the credential is refused for [lockoutDuration].
class LockoutStep {
  final int attempts;
  final Duration lockoutDuration;

  const LockoutStep({required this.attempts, required this.lockoutDuration});

  @override
  bool operator ==(Object other) =>
      other is LockoutStep &&
      other.attempts == attempts &&
      other.lockoutDuration == lockoutDuration;

  @override
  int get hashCode => Object.hash(attempts, lockoutDuration);
}

/// Runtime, deployer-configurable security policy and product tunables.
///
/// See docs/adr/0016-deployment-configuration.md: this is the security-policy
/// counterpart to `lib/core/branding/branding_config.dart` — deliberately a
/// *separate* file from `branding.json` because these fields change security
/// behaviour (lockout, PIN length, KDF cost), not just visual identity.
///
/// Only fields with no `const`-default-parameter constraint elsewhere read
/// this directly via [deploymentConfigProvider]. PIN/passphrase policy,
/// Argon2id tuning, lockout thresholds, and `AppSettings`'s own defaults are
/// pushed into those classes' mutable `configure*` statics once at startup
/// (see `main()`) because they are consumed by static-utility call sites with
/// no dependency-injection path today — see ADR-0016 Decision item 2 for why.
class DeploymentConfig {
  final int pinLength;
  final int passphraseMinLength;
  final int passphraseRecommendedLength;
  final int passphraseMaxLength;

  final int argon2MemoryKiB;
  final int argon2Iterations;
  final int argon2Parallelism;

  final List<LockoutStep> lockoutSteps;

  final AutoLockDelay defaultAutoLock;
  final int credentialRotationDefaultDays;
  final int credentialRotationMinDays;
  final int credentialRotationMaxDays;
  final List<int> credentialRotationOptionsDays;

  /// Prefix for exported backup file names. `null` means "derive from the
  /// loaded [BrandingConfig.appName]" — see `BackupExportScreen`.
  final String? backupFileNamePrefix;

  final int copiedToClipboardSnackbarSeconds;

  const DeploymentConfig({
    required this.pinLength,
    required this.passphraseMinLength,
    required this.passphraseRecommendedLength,
    required this.passphraseMaxLength,
    required this.argon2MemoryKiB,
    required this.argon2Iterations,
    required this.argon2Parallelism,
    required this.lockoutSteps,
    required this.defaultAutoLock,
    required this.credentialRotationDefaultDays,
    required this.credentialRotationMinDays,
    required this.credentialRotationMaxDays,
    required this.credentialRotationOptionsDays,
    required this.backupFileNamePrefix,
    required this.copiedToClipboardSnackbarSeconds,
  });

  static const String _assetPath = 'assets/config/deployment_config.json';

  /// Every value exactly as it was hardcoded before this config existed, so
  /// a missing or malformed `deployment_config.json` changes nothing.
  static const DeploymentConfig fallback = DeploymentConfig(
    pinLength: 6,
    passphraseMinLength: 12,
    passphraseRecommendedLength: 15,
    passphraseMaxLength: 256,
    argon2MemoryKiB: 19456,
    argon2Iterations: 2,
    argon2Parallelism: 1,
    lockoutSteps: [
      LockoutStep(attempts: 3, lockoutDuration: Duration(seconds: 30)),
      LockoutStep(attempts: 5, lockoutDuration: Duration(minutes: 5)),
      LockoutStep(attempts: 10, lockoutDuration: Duration(hours: 1)),
    ],
    defaultAutoLock: AutoLockDelay.thirtySeconds,
    credentialRotationDefaultDays: 90,
    credentialRotationMinDays: 1,
    credentialRotationMaxDays: 3650,
    credentialRotationOptionsDays: [30, 60, 90, 180, 365],
    backupFileNamePrefix: null,
    copiedToClipboardSnackbarSeconds: 1,
  );

  /// Loads from [_assetPath]. Falls back to [fallback] if the asset is
  /// missing or malformed, so a broken deployment config never prevents the
  /// app from starting.
  static Future<DeploymentConfig> load() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      return parse(raw);
    } catch (_) {
      return fallback;
    }
  }

  /// Parses [raw] JSON into a [DeploymentConfig]. Each field falls back to
  /// [fallback]'s value independently when missing or the wrong type, so one
  /// bad field doesn't discard an otherwise-valid file. Throws only when
  /// [raw] itself isn't valid JSON — [load] catches that and uses [fallback]
  /// wholesale.
  static DeploymentConfig parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final security =
        json['security'] is Map ? json['security'] as Map<String, dynamic> : const {};
    final backup =
        json['backup'] is Map ? json['backup'] as Map<String, dynamic> : const {};
    final ui = json['ui'] is Map ? json['ui'] as Map<String, dynamic> : const {};

    return DeploymentConfig(
      pinLength: _intAtLeast(security['pinLength'], _minPinLength) ?? fallback.pinLength,
      passphraseMinLength: _intAtLeast(
              security['passphraseMinLength'], _minPassphraseMinLength) ??
          fallback.passphraseMinLength,
      passphraseRecommendedLength: _int(security['passphraseRecommendedLength']) ??
          fallback.passphraseRecommendedLength,
      passphraseMaxLength:
          _int(security['passphraseMaxLength']) ?? fallback.passphraseMaxLength,
      argon2MemoryKiB: _intAtLeast(security['argon2MemoryKiB'], _minArgon2MemoryKiB) ??
          fallback.argon2MemoryKiB,
      argon2Iterations:
          _intAtLeast(security['argon2Iterations'], _minArgon2Iterations) ??
              fallback.argon2Iterations,
      argon2Parallelism:
          _intAtLeast(security['argon2Parallelism'], _minArgon2Parallelism) ??
              fallback.argon2Parallelism,
      lockoutSteps: _parseLockoutSteps(security['lockoutSteps']) ?? fallback.lockoutSteps,
      defaultAutoLock:
          _parseAutoLock(security['defaultAutoLock']) ?? fallback.defaultAutoLock,
      credentialRotationDefaultDays: _int(security['credentialRotationDefaultDays']) ??
          fallback.credentialRotationDefaultDays,
      credentialRotationMinDays: _int(security['credentialRotationMinDays']) ??
          fallback.credentialRotationMinDays,
      credentialRotationMaxDays: _int(security['credentialRotationMaxDays']) ??
          fallback.credentialRotationMaxDays,
      credentialRotationOptionsDays:
          _parseIntList(security['credentialRotationOptionsDays']) ??
              fallback.credentialRotationOptionsDays,
      backupFileNamePrefix:
          backup['fileNamePrefix'] is String ? backup['fileNamePrefix'] as String : null,
      copiedToClipboardSnackbarSeconds: _int(ui['copiedToClipboardSnackbarSeconds']) ??
          fallback.copiedToClipboardSnackbarSeconds,
    );
  }

  // Safety floors: a below-floor value in deployment_config.json (typo or
  // otherwise) falls back to the default rather than silently shipping a
  // weaker policy than what the app ships with today.
  static const int _minPinLength = 4;
  static const int _minPassphraseMinLength = 8; // NIST SP 800-63B floor.
  static const int _minArgon2MemoryKiB = 19456; // OWASP minimum.
  static const int _minArgon2Iterations = 2;
  static const int _minArgon2Parallelism = 1;

  static int? _int(Object? v) => v is int ? v : null;

  static int? _intAtLeast(Object? v, int min) {
    final value = _int(v);
    if (value == null || value < min) return null;
    return value;
  }

  static List<LockoutStep>? _parseLockoutSteps(Object? v) {
    if (v is! List) return null;
    if (v.isEmpty) return const []; // Explicitly disables lockout.
    final steps = <LockoutStep>[];
    for (final item in v) {
      if (item is! Map) return null;
      final attempts = _int(item['attempts']);
      final seconds = _int(item['seconds']);
      if (attempts == null || seconds == null) return null;
      steps.add(LockoutStep(attempts: attempts, lockoutDuration: Duration(seconds: seconds)));
    }
    return steps;
  }

  static List<int>? _parseIntList(Object? v) {
    if (v is! List || v.isEmpty) return null;
    final result = <int>[];
    for (final item in v) {
      if (item is! int) return null;
      result.add(item);
    }
    return result;
  }

  static AutoLockDelay? _parseAutoLock(Object? v) {
    if (v is! String) return null;
    for (final option in AutoLockDelay.values) {
      if (option.name == v) return option;
    }
    return null;
  }
}

/// Overridden with the loaded [DeploymentConfig] in `main()` before
/// [runApp], so widgets that read UI-level tunables (backup file naming,
/// snackbar duration, rotation dropdown options) can do so synchronously.
final deploymentConfigProvider = Provider<DeploymentConfig>((ref) {
  throw UnimplementedError(
    'deploymentConfigProvider must be overridden in main() with a loaded DeploymentConfig.',
  );
});

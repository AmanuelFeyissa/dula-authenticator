/// How long the app may sit in the background before it locks itself.
///
/// Callers: `lib/core/settings/settings_repository.dart` (persists
/// [AutoLockDelay.name]), `lib/core/widgets/app_lifecycle_wrapper.dart` (arms
/// the lock timer), and the settings screen. The member names are a storage
/// format — they are written into SharedPreferences verbatim.
///
/// Added for the user instruction "go ahead on phase 3", implementing
/// ADR-0011 item 5: the hardcoded 30-second lock becomes a user setting,
/// because 30 seconds is right for a shared workstation and needlessly
/// hostile on a personal desktop.
enum AutoLockDelay {
  immediate(label: 'Immediately', duration: Duration.zero),
  thirtySeconds(label: 'After 30 seconds', duration: Duration(seconds: 30)),
  oneMinute(label: 'After 1 minute', duration: Duration(minutes: 1)),
  fiveMinutes(label: 'After 5 minutes', duration: Duration(minutes: 5)),

  /// Stays unlocked until the user locks it or the app exits. There is no
  /// delay to wait for, hence a null [duration].
  never(label: 'Never', duration: null);

  const AutoLockDelay({required this.label, required this.duration});

  final String label;
  final Duration? duration;

  /// Reads a stored value, falling back to [AppSettings.defaultAutoLock].
  ///
  /// The fallback deliberately is not [never]: an unreadable preference must
  /// never be able to silently switch locking off.
  static AutoLockDelay fromName(String? name) {
    for (final option in AutoLockDelay.values) {
      if (option.name == name) return option;
    }
    return AppSettings.defaultAutoLock;
  }
}

/// User-configurable security behaviour.
///
/// Callers: `lib/core/settings/settings_repository.dart` (persistence),
/// `lib/features/settings/**` (the screen and its provider),
/// `lib/core/widgets/app_lifecycle_wrapper.dart` (auto-lock) and
/// `lib/features/auth/providers/auth_provider.dart` (biometrics, rotation).
/// Data schema: [toMap] keys are the SharedPreferences keys.
///
/// Everything here exists because ADR-0011 requires these to be choices rather
/// than assumptions: the app should not decide for a user whether biometrics
/// are acceptable, how patient their auto-lock should be, or whether their
/// organization's compliance regime forces credential rotation.
class AppSettings {
  /// Deployer-configurable via `assets/config/deployment_config.json`'s
  /// `security.defaultAutoLock`/`security.credentialRotation*` fields (see
  /// docs/adr/0016-deployment-configuration.md) through [configureDefaults].
  /// Mutable statics rather than constructor parameters, and the reason this
  /// class's constructor is no longer `const`: a mutable static cannot be a
  /// `const` default-parameter literal, and every caller that previously
  /// wrote `const AppSettings()` now writes `AppSettings()`.
  static AutoLockDelay defaultAutoLock = AutoLockDelay.thirtySeconds;
  static int defaultRotationDays = 90;
  static int minRotationDays = 1;
  static int maxRotationDays = 3650;

  /// Sets the defaults above. Call once at startup, before any
  /// [AppSettings] is constructed. Omitted parameters keep their current
  /// value.
  static void configureDefaults({
    AutoLockDelay? autoLock,
    int? rotationDays,
    int? minRotationDays,
    int? maxRotationDays,
  }) {
    defaultAutoLock = autoLock ?? defaultAutoLock;
    defaultRotationDays = rotationDays ?? defaultRotationDays;
    AppSettings.minRotationDays = minRotationDays ?? AppSettings.minRotationDays;
    AppSettings.maxRotationDays = maxRotationDays ?? AppSettings.maxRotationDays;
  }

  /// Restores the historical defaults. Test-only — call in `tearDown` after
  /// any test that calls [configureDefaults].
  static void resetDefaultsForTesting() {
    defaultAutoLock = AutoLockDelay.thirtySeconds;
    defaultRotationDays = 90;
    minRotationDays = 1;
    maxRotationDays = 3650;
  }

  /// Grace period before a backgrounded app locks itself.
  final AutoLockDelay autoLock;

  /// Whether biometric unlock is offered. Off until the user opts in, and
  /// switching it off must also discard the cached vault key.
  final bool biometricUnlockEnabled;

  /// Forced periodic credential rotation.
  ///
  /// Off by default: NIST SP 800-63B advises against mandatory periodic
  /// rotation of user-chosen secrets absent evidence of compromise, because it
  /// drives predictable increment-the-last-digit patterns. Retained as a
  /// toggle for deployments whose compliance regime requires it.
  final bool credentialRotationEnabled;

  /// Rotation period in days, applied only when [credentialRotationEnabled].
  final int credentialRotationDays;

  AppSettings({
    AutoLockDelay? autoLock,
    this.biometricUnlockEnabled = false,
    this.credentialRotationEnabled = false,
    int? credentialRotationDays,
  })  : autoLock = autoLock ?? defaultAutoLock,
        credentialRotationDays = credentialRotationDays ?? defaultRotationDays;

  /// Whether a credential set on [lastSet] must now be rotated.
  ///
  /// Returns false whenever rotation is disabled, whatever the date — the
  /// policy has to be opted into before it can expire anything.
  bool isCredentialExpired(DateTime? lastSet, {DateTime? now}) {
    if (!credentialRotationEnabled) return false;
    if (lastSet == null) return false;
    final elapsed = (now ?? DateTime.now()).difference(lastSet);
    return elapsed.inDays >= credentialRotationDays;
  }

  AppSettings copyWith({
    AutoLockDelay? autoLock,
    bool? biometricUnlockEnabled,
    bool? credentialRotationEnabled,
    int? credentialRotationDays,
  }) {
    return AppSettings(
      autoLock: autoLock ?? this.autoLock,
      biometricUnlockEnabled:
          biometricUnlockEnabled ?? this.biometricUnlockEnabled,
      credentialRotationEnabled:
          credentialRotationEnabled ?? this.credentialRotationEnabled,
      credentialRotationDays:
          credentialRotationDays ?? this.credentialRotationDays,
    );
  }

  Map<String, Object?> toMap() => {
        'autoLock': autoLock.name,
        'biometricUnlockEnabled': biometricUnlockEnabled,
        'credentialRotationEnabled': credentialRotationEnabled,
        'credentialRotationDays': credentialRotationDays,
      };

  /// Reads stored settings. Every field falls back to its default rather than
  /// throwing, so a partially written or hand-edited store still yields a
  /// usable — and safe — configuration.
  factory AppSettings.fromMap(Map<String, Object?> map) {
    // Type-checked rather than cast: a stored value of the wrong type is a
    // corrupt setting, not a crash. Casting here would let one bad
    // preferences entry stop the app from starting at all.
    final rawDays = map['credentialRotationDays'];
    final days = rawDays is int ? rawDays : defaultRotationDays;
    final rawAutoLock = map['autoLock'];
    final rawBiometrics = map['biometricUnlockEnabled'];
    final rawRotation = map['credentialRotationEnabled'];

    return AppSettings(
      autoLock:
          AutoLockDelay.fromName(rawAutoLock is String ? rawAutoLock : null),
      biometricUnlockEnabled: rawBiometrics is bool ? rawBiometrics : false,
      credentialRotationEnabled: rawRotation is bool ? rawRotation : false,
      credentialRotationDays: days.clamp(minRotationDays, maxRotationDays),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.autoLock == autoLock &&
      other.biometricUnlockEnabled == biometricUnlockEnabled &&
      other.credentialRotationEnabled == credentialRotationEnabled &&
      other.credentialRotationDays == credentialRotationDays;

  @override
  int get hashCode => Object.hash(
        autoLock,
        biometricUnlockEnabled,
        credentialRotationEnabled,
        credentialRotationDays,
      );
}

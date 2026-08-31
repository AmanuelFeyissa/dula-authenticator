import 'package:dula_auth/core/security/pin_policy.dart';

/// The knowledge factor protecting the vault.
///
/// Chosen by the user at registration and recorded in the vault metadata, so
/// the lock screen knows which input to present before anything is decrypted
/// (see docs/adr/0011-authentication-and-unlock-model.md).
///
/// Callers: `lib/core/security/credential_policy.dart`, `lib/core/crypto/
/// vault_meta.dart`, `lib/features/auth/**` (notifier and screens).
///
/// The enum member names are a **storage format**: they are written verbatim
/// into the `cred` field of the `vault_meta` record. Renaming a member renames
/// the stored value and orphans existing vaults.
///
/// Added for the user instruction "go ahead on phase 3".
enum CredentialKind {
  pin(
    explanation: 'Quick to enter. Best when you unlock many times a day and '
        'your device is yours alone.',
  ),
  passphrase(
    explanation: 'Harder to guess than a short PIN. Best on a desktop, or '
        'when these codes protect high-value accounts.',
  );

  const CredentialKind({required this.explanation});

  /// One honest line about the trade-off. ADR-0011 requires the choice be
  /// presented plainly, with neither option framed as a punishment.
  final String explanation;

  /// Short name for the choice, shown on the setup screen. [pin]'s label
  /// reflects the deployer-configured `PinPolicy.pinLength` (see
  /// docs/adr/0016-deployment-configuration.md) rather than a hardcoded "6".
  String get label => switch (this) {
        CredentialKind.pin => '${PinPolicy.pinLength}-digit PIN',
        CredentialKind.passphrase => 'Passphrase',
      };

  /// Reads a stored kind.
  ///
  /// Anything unrecognised resolves to [passphrase] rather than [pin], and the
  /// direction matters: the passphrase screen is a text field, which can also
  /// type six digits, while the PIN keypad cannot type a passphrase. Guessing
  /// [pin] for a passphrase vault would leave the user staring at a keypad
  /// that cannot express their credential.
  static CredentialKind fromName(String? name) {
    for (final kind in CredentialKind.values) {
      if (kind.name == name) return kind;
    }
    return CredentialKind.passphrase;
  }
}

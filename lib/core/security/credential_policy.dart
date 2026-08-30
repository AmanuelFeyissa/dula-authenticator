import 'package:dula_auth/core/security/credential_kind.dart';
import 'package:dula_auth/core/security/passphrase_policy.dart';
import 'package:dula_auth/core/security/pin_policy.dart';

/// Single entry point for credential strength, whichever kind the user chose.
///
/// Exists so no caller has to remember which policy applies: an `if (isPin)`
/// scattered across the setup screen, the change-credential flow and the auth
/// notifier is exactly how one path ends up skipping validation.
///
/// Callers: `lib/features/auth/providers/auth_provider.dart` (setup and
/// change-credential) and the auth setup/lock screens. Delegates to the
/// existing `PinPolicy` and `PassphrasePolicy`. No data schema — pure
/// dispatch, nothing is persisted here.
///
/// Added for the user instruction "go ahead on phase 3".
/// See docs/adr/0011-authentication-and-unlock-model.md.
class CredentialPolicy {
  /// Returns `null` if [value] is acceptable for [kind], or the reason it is
  /// not, ready to show the user.
  static String? validate(CredentialKind kind, String value) {
    switch (kind) {
      case CredentialKind.pin:
        return PinPolicy.validate(value);
      case CredentialKind.passphrase:
        return PassphrasePolicy.validate(value);
    }
  }
}

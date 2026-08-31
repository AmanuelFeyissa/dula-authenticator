/// Advisory strength rating for a passphrase, used to guide the user during
/// setup. Guidance only — [PassphrasePolicy.validate] decides acceptance.
///
/// Callers: `test/core/security/passphrase_policy_test.dart` today; the auth
/// notifier and credential setup screen once they are updated in this phase.
/// Peer of `lib/core/security/pin_policy.dart`. No data schema — nothing here
/// is persisted; the passphrase only ever reaches `VaultService.initialize`.
/// Written for the user instruction "go ahead on phase 3", implementing
/// ADR-0011's PIN-or-passphrase credential choice.
enum PassphraseStrength { weak, fair, good, strong }

/// Strength rules for the passphrase credential.
///
/// Deliberately shaped by NIST SP 800-63B rather than by traditional
/// composition rules: length is the requirement, character-class mandates
/// ("must contain a symbol") are not imposed, and the value is checked against
/// commonly-used and predictable values instead. Composition rules push users
/// toward `Password1!` — long, memorable, low-ceremony passphrases are the
/// outcome this is trying to produce.
///
/// See docs/adr/0011-authentication-and-unlock-model.md.
class PassphrasePolicy {
  /// Floor for acceptance. NIST SP 800-63B sets 8 as the minimum for
  /// user-chosen secrets; this vault is attackable offline by anyone who
  /// obtains the device, so the floor is raised.
  ///
  /// Deployer-configurable via `assets/config/deployment_config.json`'s
  /// `security.passphraseMinLength` (see
  /// docs/adr/0016-deployment-configuration.md) through [configure] — a
  /// mutable static for the same reason as `PinPolicy.pinLength`: this
  /// class is a stateless utility with no existing dependency-injection
  /// path.
  static int minLength = 12;

  /// Length at which NIST's own recommendation for user-chosen passwords is
  /// met. Surfaced as guidance, not enforced.
  static int recommendedLength = 15;

  /// Verifiers must accept long secrets (NIST requires at least 64). The cap
  /// exists only to bound input, not to discourage length.
  static int maxLength = 256;

  /// Sets [minLength]/[recommendedLength]/[maxLength]. Call once at startup,
  /// before any passphrase is validated. Omitted parameters keep their
  /// current value.
  static void configure({int? minLength, int? recommendedLength, int? maxLength}) {
    PassphrasePolicy.minLength = minLength ?? PassphrasePolicy.minLength;
    PassphrasePolicy.recommendedLength =
        recommendedLength ?? PassphrasePolicy.recommendedLength;
    PassphrasePolicy.maxLength = maxLength ?? PassphrasePolicy.maxLength;
  }

  /// Restores the default thresholds. Test-only — call in `tearDown` after
  /// any test that calls [configure].
  static void resetForTesting() {
    minLength = 12;
    recommendedLength = 15;
    maxLength = 256;
  }

  /// Predictable values, stored in normalized form (see [_normalize]).
  ///
  /// A deliberately small, curated list rather than a bundled breach corpus:
  /// shipping a multi-megabyte wordlist would bloat every platform build for
  /// diminishing returns, and the real defence against offline guessing is
  /// Argon2id (ADR-0010) plus length. This catches the values a human actually
  /// types when asked to invent a passphrase on the spot.
  static const Set<String> _commonPassphrases = {
    // The famous xkcd example — now one of the most-guessed passphrases there is.
    'correcthorsebatterystaple',
    'correcthorsebattery',
    // Stock phrases people reach for.
    'password', 'passphrase', 'mypassword', 'mypassphrase',
    'thisismypassword', 'thisismypassphrase', 'secretpassword',
    'passwordpassword', 'passw0rd', 'p4ssw0rd', 'passwd',
    'letmein', 'letmeinplease', 'openthedoor', 'opensesame',
    'changeme', 'changeit', 'defaultpassword', 'temporarypassword',
    'secret', 'topsecret', 'nothingtoseehere', 'trustno1',
    'iloveyou', 'ilovemywife', 'ilovemyhusband', 'welcome',
    'administrator', 'admin', 'root', 'toor', 'guest',
    'qwerty', 'qwertyuiop', 'azerty', 'monkey', 'dragon',
    'football', 'baseball', 'superman', 'batman', 'starwars',
    'princess', 'sunshine', 'whatever', 'hunter', 'hunter2',
    // Quotations and pangrams used as "clever" passphrases.
    'tobeornottobe', 'thequickbrownfox',
    'thequickbrownfoxjumpsoverthelazydog',
    'allworkandnoplaymakesjackadullboy',
    'maytheforcebewithyou', 'thereisnoplacelikehome',
    'thecakeisalie', 'hellothereworld', 'helloworld',
  };

  /// Rows of a QWERTY keyboard, concatenated so a walk across row boundaries
  /// ("qwertyuiopasdf") is still recognised as a walk.
  static const String _keyboardWalk = '1234567890qwertyuiopasdfghjklzxcvbnm';

  /// Returns `null` if [passphrase] satisfies policy, or a human-readable
  /// reason it was rejected.
  ///
  /// The value is never trimmed: a trimmed passphrase would differ from what
  /// the user typed, so leading and trailing spaces count and are preserved.
  static String? validate(String passphrase) {
    if (passphrase.isEmpty) {
      return 'Enter a passphrase.';
    }

    if (passphrase.trim().isEmpty) {
      return 'A passphrase cannot be only spaces.';
    }

    if (passphrase.length < minLength) {
      return 'Passphrase must be at least $minLength characters.';
    }

    if (passphrase.length > maxLength) {
      return 'Passphrase must be at most $maxLength characters.';
    }

    final normalized = _normalize(passphrase);

    // Checked with a trailing digit run removed as well, because "password" and
    // "password1234" cost an attacker the same: appending digits is the first
    // mangling rule every cracking ruleset applies.
    if (_commonPassphrases.contains(normalized) ||
        _commonPassphrases.contains(_withoutTrailingDigits(normalized))) {
      return 'This passphrase is well known. Please choose another.';
    }

    if (_isSingleCharacterRepeated(passphrase)) {
      return 'A repeated character is not a passphrase.';
    }

    if (_isConsecutiveRun(normalized)) {
      return 'Passphrase cannot be a simple run of letters or digits.';
    }

    if (_isKeyboardWalk(normalized)) {
      return 'Passphrase cannot be a straight run across the keyboard.';
    }

    return null;
  }

  /// Advisory rating shown while the user types.
  ///
  /// Anything [validate] rejects is weak by definition, so a long but
  /// predictable value is never rated well on length alone.
  static PassphraseStrength strengthOf(String passphrase) {
    if (validate(passphrase) != null) return PassphraseStrength.weak;

    // Length is only worth what the alphabet behind it is worth: "ababab..."
    // is twenty characters drawn from two symbols, and a search over two
    // symbols is not a search. Narrow values are capped regardless of length.
    final distinct = passphrase.split('').toSet().length;
    if (distinct < 5) return PassphraseStrength.weak;

    final length = passphrase.length;
    PassphraseStrength byLength;
    if (length < recommendedLength) {
      byLength = PassphraseStrength.weak;
    } else if (length < 25) {
      byLength = PassphraseStrength.fair;
    } else if (length < 35) {
      byLength = PassphraseStrength.good;
    } else {
      byLength = PassphraseStrength.strong;
    }

    if (distinct < 10 && byLength.index > PassphraseStrength.fair.index) {
      return PassphraseStrength.fair;
    }
    return byLength;
  }

  /// Lowercases and drops separators, so "Correct Horse-Battery Staple" and
  /// "correcthorsebatterystaple" are recognised as the same value.
  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _withoutTrailingDigits(String value) =>
      value.replaceFirst(RegExp(r'\d+$'), '');

  static bool _isSingleCharacterRepeated(String value) =>
      value.split('').every((c) => c == value[0]);

  /// Detects `abcdefgh` and `12345678`, in either direction. Digit runs wrap
  /// at nine, because `7890123` is the same idea as `1234567`.
  static bool _isConsecutiveRun(String value) {
    if (value.length < 2) return false;

    final isAllDigits = RegExp(r'^[0-9]+$').hasMatch(value);
    final units = value.codeUnits;

    bool runs(int step) {
      for (var i = 0; i < units.length - 1; i++) {
        if (isAllDigits) {
          final current = units[i] - 0x30;
          final next = units[i + 1] - 0x30;
          if ((current + step + 10) % 10 != next) return false;
        } else {
          if (units[i] + step != units[i + 1]) return false;
        }
      }
      return true;
    }

    return runs(1) || runs(-1);
  }

  static bool _isKeyboardWalk(String value) {
    if (value.length < 4) return false;
    final reversed = value.split('').reversed.join();
    return _keyboardWalk.contains(value) || _keyboardWalk.contains(reversed);
  }
}

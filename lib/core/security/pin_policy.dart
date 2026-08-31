/// Strength rules for the numeric PIN credential.
///
/// Cryptography lives in `lib/core/crypto/`; this module is purely policy —
/// deciding whether a chosen PIN is acceptable. A PIN's 10^6 keyspace is small
/// regardless of how it is hashed (see ADR-0010 and ADR-0011), so rejecting the
/// predictable values attackers try first is a meaningful part of the defence.
class PinPolicy {
  /// Required PIN length. Deployer-configurable via
  /// `assets/config/deployment_config.json`'s `security.pinLength` (see
  /// docs/adr/0016-deployment-configuration.md) through [configure] — a
  /// mutable static rather than a constructor parameter because this class
  /// is a stateless utility called directly from UI code with no existing
  /// dependency-injection path.
  ///
  /// Changing this away from the default (6) forfeits [_commonPins] and the
  /// sequential/repeating-pattern checks below: they are curated
  /// specifically for 6-digit PINs, and [validate] skips them entirely at
  /// any other length rather than risk misapplying them.
  static int pinLength = 6;

  /// Sets [pinLength]. Call once at startup, before any PIN is validated.
  static void configure({required int pinLength}) {
    PinPolicy.pinLength = pinLength;
  }

  /// Restores the default length. Test-only — call in `tearDown` after any
  /// test that calls [configure].
  static void resetForTesting() {
    pinLength = 6;
  }

  // ---------------------------------------------------------------------------
  // Common 6-digit PIN blocklist.
  // Sources: NIST SP 800-63B, academic studies on PIN re-use, and public breach
  // datasets. Covers the most frequently observed 6-digit PINs worldwide.
  // ---------------------------------------------------------------------------
  static const Set<String> _commonPins = {
    // Pure sequential / repeating (also caught by the pattern checks below).
    '000000', '111111', '222222', '333333', '444444', '555555',
    '666666', '777777', '888888', '999999',
    '123456', '654321', '012345', '098765',
    '234567', '345678', '456789', '567890',
    '987654', '876543', '765432',

    // Top breached PINs from public datasets.
    '123123', '121212', '112233', '123321', '321321',
    '111222', '222111', '333444', '444333', '555666',
    '666555', '777888', '888777', '999000', '000999',
    '112211', '221122', '334455', '445566', '556677',
    '667788', '778899', '889900', '998877', '887766',
    '776655', '665544', '554433', '443322', '332211',
    '554411', '221133', '443311', '665522', '776633',

    // Repeated pairs / triplets.
    '001001', '002002', '003003', '004004', '005005',
    '006006', '007007', '008008', '009009',
    '010101', '020202', '030303', '040404', '050505',
    '060606', '070707', '080808', '090909',
    '100100', '200200', '300300', '400400', '500500',
    '600600', '700700', '800800', '900900',
    '110011', '220022', '330033', '440044', '550055',
    '660066', '770077', '880088', '990099',
    '101010', '202020', '303030', '404040', '505050',
    '606060', '707070', '808080', '909090',
    '987987', '111000', '000111', '222000', '000222',

    // Keyboard walks on a 3x4 numpad.
    '147258', '258369', '369258', '852741', '741852',
    '159357', '357159', '753951', '951357',
    '123654', '456123', '789456', '147896',

    // Dates and years masquerading as PINs.
    '190000', '200000', '199000', '198000', '197000',
    '196000', '195000', '196969', '197070', '198080',
    '199090', '200001', '200100', '199900', '198900',
    '197800', '202100', '202200', '202300',
    '202400', '202500',

    // Birth-year patterns.
    '196001', '196101', '196201', '196301', '196401',
    '196501', '196601', '196701', '196801', '196901',
    '197001', '197101', '197201', '197301', '197401',
    '197501', '197601', '197701', '197801', '197901',
    '198001', '198101', '198201', '198301', '198401',
    '198501', '198601', '198701', '198801', '198901',
    '199001', '199101', '199201', '199301', '199401',
    '199501', '199601', '199701', '199801', '199901',
    '200101', '200201', '200301', '200401',
    '200501', '200601', '200701', '200801', '200901',

    // Other frequently observed values.
    '696969', '111213', '131211', '246810', '135790',
    '246801', '123450', '543210', '012300', '100200',
    '102030', '111100', '100001', '200002', '110000',
    '120000', '100000', '000001', '000010', '000100',
    '001000', '010000',
  };

  /// Returns `null` if [pin] satisfies policy, or a human-readable reason.
  static String? validate(String pin) {
    if (pin.length != pinLength) {
      return 'PIN must be exactly $pinLength digits.';
    }

    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      return 'PIN must contain digits only.';
    }

    if (pin.split('').every((c) => c == pin[0])) {
      return 'PIN cannot use the same digit repeated $pinLength times.';
    }

    // The remaining checks are curated for 6-digit PINs (see [pinLength]'s
    // doc comment) — some of them assume a fixed length when slicing the
    // string into pairs, so they only run at the default length.
    if (pinLength != 6) return null;

    if (_commonPins.contains(pin)) {
      return 'This PIN is too common. Please choose a less predictable one.';
    }

    if (_isFullyAscending(pin)) {
      return 'PIN cannot be a simple ascending sequence.';
    }

    if (_isFullyDescending(pin)) {
      return 'PIN cannot be a simple descending sequence.';
    }

    if (_hasMixedSequentialRepeating(pin)) {
      return 'PIN cannot use mixed sequential or repeating patterns (e.g. 112233).';
    }

    if (_hasRepeatingGroup(pin)) {
      return 'PIN cannot be a repeated pair or triplet (e.g. 121212).';
    }

    return null;
  }

  /// Whether [pin] matches a weak *pattern*.
  ///
  /// Answers only the pattern question — a PIN of the wrong length is invalid
  /// for a different reason and is not "sequential or repeating". Use
  /// [validate] to enforce the whole policy.
  static bool isWeakPattern(String pin) {
    if (pin.length != pinLength) return false;
    return validate(pin) != null;
  }

  static bool _isFullyAscending(String pin) {
    for (var i = 0; i < pin.length - 1; i++) {
      final cur = int.tryParse(pin[i]);
      final next = int.tryParse(pin[i + 1]);
      if (cur == null || next == null || next != cur + 1) return false;
    }
    return true;
  }

  static bool _isFullyDescending(String pin) {
    for (var i = 0; i < pin.length - 1; i++) {
      final cur = int.tryParse(pin[i]);
      final next = int.tryParse(pin[i + 1]);
      if (cur == null || next == null || next != cur - 1) return false;
    }
    return true;
  }

  /// Detects patterns like 112233 / 554433: three repeated-digit pairs whose
  /// values run in sequence.
  static bool _hasMixedSequentialRepeating(String pin) {
    final pairs = [pin.substring(0, 2), pin.substring(2, 4), pin.substring(4, 6)];
    if (!pairs.every((p) => p[0] == p[1])) return false;

    final values = pairs.map((p) => int.parse(p[0])).toList();
    var ascending = true;
    var descending = true;
    for (var i = 0; i < values.length - 1; i++) {
      if (values[i + 1] != values[i] + 1) ascending = false;
      if (values[i + 1] != values[i] - 1) descending = false;
    }
    return ascending || descending;
  }

  /// Detects a 2- or 3-digit group repeated to fill six digits
  /// (121212, 456456).
  static bool _hasRepeatingGroup(String pin) {
    final pair = pin.substring(0, 2);
    if (pin.substring(2, 4) == pair && pin.substring(4, 6) == pair) return true;

    final triplet = pin.substring(0, 3);
    return pin.substring(3, 6) == triplet;
  }
}

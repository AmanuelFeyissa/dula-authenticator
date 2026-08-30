import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/totp_engine.dart';

void main() {
  group('TotpEngine RFC 6238 Test Vectors', () {
    // Test vectors from RFC 6238 Appendix B
    final String secretBase32 = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'; // "12345678901234567890" in base32
    final String secretBase32Sha256 = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA'; // 32 bytes
    final String secretBase32Sha512 = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA'; // 64 bytes
    
    test('SHA1 test vectors', () {
      final vectors = [
        {'time': 59, 'code': '94287082'},
        {'time': 1111111109, 'code': '07081804'},
        {'time': 1111111111, 'code': '14050471'},
        {'time': 1234567890, 'code': '89005924'},
        {'time': 2000000000, 'code': '69279037'},
        {'time': 20000000000, 'code': '65353130'},
      ];

      for (var v in vectors) {
        final time = DateTime.fromMillisecondsSinceEpoch((v['time'] as int) * 1000, isUtc: true);
        final code = TotpEngine.generateCode(
          secret: secretBase32,
          time: time,
          digits: 8,
          algorithm: TotpAlgorithm.sha1,
        );
        expect(code, v['code']);
      }
    });

    test('SHA256 test vectors', () {
      final vectors = [
        {'time': 59, 'code': '46119246'},
        {'time': 1111111109, 'code': '68084774'},
        {'time': 1111111111, 'code': '67062674'},
        {'time': 1234567890, 'code': '91819424'},
        {'time': 2000000000, 'code': '90698825'},
        {'time': 20000000000, 'code': '77737706'},
      ];

      for (var v in vectors) {
        final time = DateTime.fromMillisecondsSinceEpoch((v['time'] as int) * 1000, isUtc: true);
        final code = TotpEngine.generateCode(
          secret: secretBase32Sha256,
          time: time,
          digits: 8,
          algorithm: TotpAlgorithm.sha256,
        );
        expect(code, v['code']);
      }
    });

    test('SHA512 test vectors', () {
      final vectors = [
        {'time': 59, 'code': '90693936'},
        {'time': 1111111109, 'code': '25091201'},
        {'time': 1111111111, 'code': '99943326'},
        {'time': 1234567890, 'code': '93441116'},
        {'time': 2000000000, 'code': '38618901'},
        {'time': 20000000000, 'code': '47863826'},
      ];

      for (var v in vectors) {
        final time = DateTime.fromMillisecondsSinceEpoch((v['time'] as int) * 1000, isUtc: true);
        final code = TotpEngine.generateCode(
          secret: secretBase32Sha512,
          time: time,
          digits: 8,
          algorithm: TotpAlgorithm.sha512,
        );
        expect(code, v['code']);
      }
    });

    test('Standard 6-digit TOTP generation', () {
      // Time: 01 Jan 2000 00:00:00 GMT (946684800 seconds)
      final secret = 'JBSWY3DPEHPK3PXP'; // "Hello!\xDE\xAD\xBE\xEF"
      final time = DateTime.fromMillisecondsSinceEpoch(946684800 * 1000, isUtc: true);
      
      final code = TotpEngine.generateCode(
        secret: secret,
        time: time,
      );
      
      expect(code.length, 6);
    });

    test('Remaining seconds calculation', () {
      final time1 = DateTime.fromMillisecondsSinceEpoch(45000, isUtc: true); // 45 seconds
      expect(TotpEngine.getRemainingSeconds(time: time1, period: 30), 15);
      
      final time2 = DateTime.fromMillisecondsSinceEpoch(60000, isUtc: true); // 60 seconds
      expect(TotpEngine.getRemainingSeconds(time: time2, period: 30), 30);
    });
  });
}

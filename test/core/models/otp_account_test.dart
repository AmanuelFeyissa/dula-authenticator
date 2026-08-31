import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/models/otp_account.dart';

OtpAccount _account({
  List<String> tags = const [],
  bool isFavorite = false,
}) =>
    OtpAccount(
      id: '1',
      issuer: 'GitHub',
      accountName: 'dev@example.com',
      secret: 'JBSWY3DPEHPK3PXP',
      tags: tags,
      isFavorite: isFavorite,
    );

void main() {
  group('defaults', () {
    test('has no tags and is not a favorite by default', () {
      const account = OtpAccount(
        id: '1',
        issuer: 'GitHub',
        accountName: 'dev@example.com',
        secret: 'JBSWY3DPEHPK3PXP',
      );

      expect(account.tags, isEmpty);
      expect(account.isFavorite, isFalse);
    });

    test('has no load error by default', () {
      const account = OtpAccount(
        id: '1',
        issuer: 'GitHub',
        accountName: 'dev@example.com',
        secret: 'JBSWY3DPEHPK3PXP',
      );

      expect(account.loadError, isNull);
    });
  });

  group('copyWith', () {
    test('updates tags without touching other fields', () {
      final account = _account();
      final updated = account.copyWith(tags: ['work', 'critical']);

      expect(updated.tags, ['work', 'critical']);
      expect(updated.issuer, account.issuer);
    });

    test('updates isFavorite independently', () {
      final account = _account();
      final updated = account.copyWith(isFavorite: true);

      expect(updated.isFavorite, isTrue);
    });

    test('clears tags when explicitly given an empty list', () {
      final account = _account(tags: ['work']);
      final updated = account.copyWith(tags: []);

      expect(updated.tags, isEmpty);
    });
  });

  group('serialization', () {
    test('round-trips tags through toMap/fromMap', () {
      final account = _account(tags: ['work', 'critical']);
      final restored = OtpAccount.fromMap(account.toMap());

      expect(restored.tags, ['work', 'critical']);
    });

    test('round-trips isFavorite through toMap/fromMap', () {
      final account = _account(isFavorite: true);
      final restored = OtpAccount.fromMap(account.toMap());

      expect(restored.isFavorite, isTrue);
    });

    test('a record with no tags/isFavorite field defaults cleanly', () {
      // A stored record from before this field existed lacks the keys
      // entirely — this must not throw and must not be treated as corrupt.
      final restored = OtpAccount.fromMap({
        'id': '1',
        'issuer': 'GitHub',
        'accountName': 'dev@example.com',
        'secret': 'JBSWY3DPEHPK3PXP',
      });

      expect(restored.tags, isEmpty);
      expect(restored.isFavorite, isFalse);
    });

    test('does not serialize loadError', () {
      // loadError is a runtime-only annotation set by AccountRepository after
      // a failed decrypt; persisting it would be nonsensical (it describes a
      // failure that happened in this session, not a fact about the account).
      final account = _account().copyWith(loadError: 'GCM authentication failed');

      expect(account.toMap().containsKey('loadError'), isFalse);
    });

    test('fromMap never produces a loadError', () {
      final restored = OtpAccount.fromMap({
        'id': '1',
        'issuer': 'GitHub',
        'accountName': 'dev@example.com',
        'secret': 'JBSWY3DPEHPK3PXP',
        'loadError': 'someone hand-edited this in',
      });

      expect(restored.loadError, isNull);
    });

    test('an unreadable tags value defaults to empty rather than throwing', () {
      final restored = OtpAccount.fromMap({
        'id': '1',
        'issuer': 'GitHub',
        'accountName': 'dev@example.com',
        'secret': 'JBSWY3DPEHPK3PXP',
        'tags': 'not-a-list',
      });

      expect(restored.tags, isEmpty);
    });
  });
}

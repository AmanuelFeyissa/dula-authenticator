import 'package:flutter_test/flutter_test.dart';
import 'package:dula_auth/core/backup/import_merge.dart';
import 'package:dula_auth/core/models/otp_account.dart';

OtpAccount _account({
  String id = '1',
  String issuer = 'GitHub',
  String accountName = 'dev@example.com',
  String secret = 'JBSWY3DPEHPK3PXP',
}) =>
    OtpAccount(id: id, issuer: issuer, accountName: accountName, secret: secret);

void main() {
  group('new accounts', () {
    test('an incoming account with no match is a new account', () {
      final plan = ImportMerge.plan(
        existing: [],
        incoming: [_account()],
      );

      expect(plan.newAccounts, hasLength(1));
      expect(plan.duplicates, isEmpty);
    });

    test('a different secret under the same issuer/account is new, not a duplicate', () {
      final plan = ImportMerge.plan(
        existing: [_account(secret: 'JBSWY3DPEHPK3PXP')],
        incoming: [_account(secret: 'KRSXG5CTMVRXEZLU')],
      );

      expect(plan.newAccounts, hasLength(1));
      expect(plan.duplicates, isEmpty);
    });
  });

  group('duplicates', () {
    test('matches on identical issuer, account name, and secret', () {
      final existing = _account(id: 'existing-1');
      final plan = ImportMerge.plan(
        existing: [existing],
        incoming: [_account(id: 'incoming-1')],
      );

      expect(plan.newAccounts, isEmpty);
      expect(plan.duplicates, hasLength(1));
      expect(plan.duplicates.single.incoming.id, 'incoming-1');
      expect(plan.duplicates.single.existing.id, 'existing-1');
    });

    test('matches regardless of issuer/account casing', () {
      final plan = ImportMerge.plan(
        existing: [_account(issuer: 'GitHub', accountName: 'Dev@Example.com')],
        incoming: [_account(issuer: 'GITHUB', accountName: 'dev@example.com')],
      );

      expect(plan.duplicates, hasLength(1));
    });

    test('matches regardless of secret casing', () {
      final plan = ImportMerge.plan(
        existing: [_account(secret: 'jbswy3dpehpk3pxp')],
        incoming: [_account(secret: 'JBSWY3DPEHPK3PXP')],
      );

      expect(plan.duplicates, hasLength(1));
    });

    test('matches regardless of surrounding whitespace', () {
      final plan = ImportMerge.plan(
        existing: [_account(issuer: ' GitHub ', accountName: ' dev@example.com ')],
        incoming: [_account(issuer: 'GitHub', accountName: 'dev@example.com')],
      );

      expect(plan.duplicates, hasLength(1));
    });
  });

  group('mixed batches', () {
    test('classifies each incoming account independently', () {
      final existing = [_account(issuer: 'GitHub')];
      final plan = ImportMerge.plan(
        existing: existing,
        incoming: [
          _account(id: 'dup', issuer: 'GitHub'),
          _account(id: 'new', issuer: 'AWS'),
        ],
      );

      expect(plan.newAccounts.map((a) => a.id), ['new']);
      expect(plan.duplicates.map((d) => d.incoming.id), ['dup']);
    });

    test('two identical incoming accounts both match the one existing account',
        () {
      // Neither incoming entry is compared against the other — only against
      // what is already stored — so importing the same file twice is a
      // deterministic no-op rather than depending on processing order.
      final existing = [_account(issuer: 'GitHub')];
      final plan = ImportMerge.plan(
        existing: existing,
        incoming: [
          _account(id: 'a', issuer: 'GitHub'),
          _account(id: 'b', issuer: 'GitHub'),
        ],
      );

      expect(plan.duplicates, hasLength(2));
      expect(plan.newAccounts, isEmpty);
    });
  });

  group('empty inputs', () {
    test('nothing incoming yields an empty plan', () {
      final plan = ImportMerge.plan(existing: [_account()], incoming: []);
      expect(plan.newAccounts, isEmpty);
      expect(plan.duplicates, isEmpty);
    });

    test('nothing existing means everything incoming is new', () {
      final plan = ImportMerge.plan(
        existing: [],
        incoming: [_account(id: 'a'), _account(id: 'b', issuer: 'AWS')],
      );
      expect(plan.newAccounts, hasLength(2));
    });
  });
}

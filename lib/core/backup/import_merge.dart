import 'package:dula_auth/core/models/otp_account.dart';

/// One incoming account that already matches something in the vault.
class ImportDuplicate {
  final OtpAccount incoming;
  final OtpAccount existing;
  const ImportDuplicate({required this.incoming, required this.existing});
}

/// The result of classifying an incoming batch against the current vault.
class ImportPlan {
  /// Accounts with no match — safe to add outright.
  final List<OtpAccount> newAccounts;

  /// Accounts that match something already stored. Held for review rather
  /// than silently skipped or silently overwritten.
  final List<ImportDuplicate> duplicates;

  const ImportPlan({required this.newAccounts, required this.duplicates});
}

/// Classifies an import batch against the existing vault before anything is
/// written.
///
/// Callers: `lib/features/backup/**` (the import review screen decides what
/// to do with each list; this module only classifies). No data schema —
/// operates on in-memory [OtpAccount] lists.
///
/// Implements ADR-0013 §6: "importing merges into the existing vault, with
/// duplicate detection ... and an explicit review step before committing —
/// never a silent overwrite." A duplicate is identical issuer, account name,
/// and secret; that combination identifying "the same credential" is a
/// judgment call, but it is the one every comparable app (Aegis, 2FAS) also
/// uses, because two credentials that share a secret but differ only in
/// display text are still the same underlying enrollment.
class ImportMerge {
  static ImportPlan plan({
    required List<OtpAccount> existing,
    required List<OtpAccount> incoming,
  }) {
    final newAccounts = <OtpAccount>[];
    final duplicates = <ImportDuplicate>[];

    for (final candidate in incoming) {
      final match = _findMatch(candidate, existing);
      if (match != null) {
        duplicates.add(ImportDuplicate(incoming: candidate, existing: match));
      } else {
        newAccounts.add(candidate);
      }
    }

    return ImportPlan(newAccounts: newAccounts, duplicates: duplicates);
  }

  static OtpAccount? _findMatch(
    OtpAccount candidate,
    List<OtpAccount> existing,
  ) {
    for (final account in existing) {
      if (_key(account) == _key(candidate)) return account;
    }
    return null;
  }

  static String _key(OtpAccount account) => [
        account.issuer.trim().toLowerCase(),
        account.accountName.trim().toLowerCase(),
        account.secret.trim().toUpperCase(),
      ].join(' ');
}

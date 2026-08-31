import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dula_auth/core/backup/import_merge.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/widgets/responsive_layout.dart';
import 'package:dula_auth/features/home/providers/home_provider.dart';

/// Review step before an import is committed.
///
/// Caller: `lib/features/backup/screens/backup_import_screen.dart`, pushed
/// with the accounts a source parser already decoded. No data schema of its
/// own — it classifies the incoming batch against the vault via
/// [ImportMerge] and, on commit, calls `AccountListNotifier.addAccount` for
/// whatever the user kept selected.
///
/// Implements ADR-0013 §6: import is never a silent overwrite. New accounts
/// are pre-selected; accounts that match something already stored are
/// pre-deselected, since re-adding a match by default would just be a
/// confusing duplicate the user did not ask for — but nothing is hidden, and
/// the user can bring any of them back in.
///
/// Added for the user instruction "go ahead with phase 4".
class BackupImportReviewScreen extends ConsumerStatefulWidget {
  final List<OtpAccount> incoming;
  final String sourceLabel;

  const BackupImportReviewScreen({
    super.key,
    required this.incoming,
    required this.sourceLabel,
  });

  @override
  ConsumerState<BackupImportReviewScreen> createState() =>
      _BackupImportReviewScreenState();
}

class _BackupImportReviewScreenState
    extends ConsumerState<BackupImportReviewScreen> {
  late ImportPlan _plan;
  late Set<String> _selectedIncomingIds;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    // A corrupted account's secret is ciphertext, not a real value
    // (ADR-0015 §7) — it can never meaningfully match an incoming plaintext
    // secret, so it is excluded rather than left to coincidentally not-match.
    final existing = (ref.read(accountListProvider).value ?? const [])
        .where((a) => a.loadError == null)
        .toList();
    _plan = ImportMerge.plan(existing: existing, incoming: widget.incoming);
    // New accounts are opted in by default; duplicates are opted out, since
    // the vault already has something matching them.
    _selectedIncomingIds = _plan.newAccounts.map((a) => a.id).toSet();
  }

  Future<void> _commit() async {
    setState(() => _committing = true);

    final toImport = [
      ..._plan.newAccounts,
      ..._plan.duplicates.map((d) => d.incoming),
    ].where((a) => _selectedIncomingIds.contains(a.id));

    var added = 0;
    for (final account in toImport) {
      final ok =
          await ref.read(accountListProvider.notifier).addAccount(account);
      if (ok) added++;
    }

    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 1 ? 'Added 1 account.' : 'Added $added accounts.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalIncoming = widget.incoming.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Review import')),
      body: ResponsiveLayout(
        maxWidth: 700,
        padding: const EdgeInsets.all(16),
        child: totalIncoming == 0
            ? const Center(child: Text('This source had no accounts to import.'))
            : ListView(
                children: [
                  Text(
                    '${widget.sourceLabel} — $totalIncoming account'
                    '${totalIncoming == 1 ? '' : 's'} found.',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_plan.newAccounts.isNotEmpty) ...[
                    _SectionHeader('New (${_plan.newAccounts.length})'),
                    for (final account in _plan.newAccounts)
                      _AccountTile(
                        account: account,
                        selected: _selectedIncomingIds.contains(account.id),
                        onChanged: (v) => setState(() {
                          v
                              ? _selectedIncomingIds.add(account.id)
                              : _selectedIncomingIds.remove(account.id);
                        }),
                      ),
                    const SizedBox(height: 16),
                  ],
                  if (_plan.duplicates.isNotEmpty) ...[
                    _SectionHeader(
                      'Already in your vault (${_plan.duplicates.length})',
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'These match an account you already have (same '
                        'issuer, account, and secret). They are not selected '
                        'by default — nothing is ever overwritten.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
                    for (final duplicate in _plan.duplicates)
                      _AccountTile(
                        account: duplicate.incoming,
                        selected:
                            _selectedIncomingIds.contains(duplicate.incoming.id),
                        onChanged: (v) => setState(() {
                          v
                              ? _selectedIncomingIds.add(duplicate.incoming.id)
                              : _selectedIncomingIds.remove(duplicate.incoming.id);
                        }),
                      ),
                  ],
                ],
              ),
      ),
      floatingActionButton: totalIncoming == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: _committing || _selectedIncomingIds.isEmpty
                  ? null
                  : _commit,
              icon: _committing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text('Import (${_selectedIncomingIds.length})'),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.tealAccent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final OtpAccount account;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _AccountTile({
    required this.account,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: selected,
      onChanged: (v) => onChanged(v ?? false),
      title: Text(
        account.issuer.isNotEmpty ? account.issuer : 'Authenticator',
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        account.accountName,
        style: const TextStyle(color: Colors.white54),
      ),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

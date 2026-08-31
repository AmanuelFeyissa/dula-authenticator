import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dula_auth/core/backup/backup_file_io.dart';
import 'package:dula_auth/core/backup/backup_service.dart';
import 'package:dula_auth/core/widgets/responsive_layout.dart';
import 'package:dula_auth/features/auth/widgets/passphrase_field.dart';
import 'package:dula_auth/features/home/providers/home_provider.dart';

/// Export the vault to a local encrypted file.
///
/// Caller: `lib/features/settings/screens/settings_screen.dart`. No data
/// schema of its own — reads the decrypted account list already held by
/// `accountListProvider` and hands it to `BackupService.export`, then
/// `BackupFileIO.save` writes the result to a location the user chooses.
///
/// The export passphrase is deliberately **independent of the unlock
/// credential** — the field says so, and `BackupService.export` enforces
/// passphrase policy regardless of what the vault's own credential kind is.
/// See docs/adr/0013-backup-export-and-import.md §2.
///
/// Added for the user instruction "go ahead with phase 4".
class BackupExportScreen extends ConsumerStatefulWidget {
  const BackupExportScreen({super.key});

  @override
  ConsumerState<BackupExportScreen> createState() =>
      _BackupExportScreenState();
}

class _BackupExportScreenState extends ConsumerState<BackupExportScreen> {
  final TextEditingController _passphrase = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (_passphrase.text != _confirm.text) {
      setState(() => _error = 'The two entries do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    // A corrupted account's `secret` is still ciphertext, not a usable
    // value (ADR-0015 §7) — exporting it would write garbage into the
    // backup and silently corrupt whatever imports it later.
    final accounts = (ref.read(accountListProvider).value ?? const [])
        .where((a) => a.loadError == null)
        .toList();
    final result = await BackupService.export(accounts, _passphrase.text);

    if (!mounted) return;

    switch (result) {
      case BackupExportRejected(:final reason):
        setState(() {
          _busy = false;
          _error = reason;
        });
        return;
      case BackupExportSuccess(:final fileContent):
        final stamp = DateTime.now().toIso8601String().split('T').first;
        final saved = await BackupFileIO.save(
          content: fileContent,
          suggestedName: 'dula-auth-backup-$stamp.json',
        );
        if (!mounted) return;
        setState(() => _busy = false);
        if (saved) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup saved.')),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountCount = ref.watch(accountListProvider).value?.length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Export backup')),
      body: ResponsiveLayout(
        maxWidth: 560,
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text(
              accountCount == 1
                  ? '1 account will be exported.'
                  : '$accountCount accounts will be exported.',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'This passphrase protects the file, and is separate from your '
              'unlock PIN or passphrase — anyone who obtains this file will '
              'try to guess it offline, so choose something strong. Nothing '
              'is sent anywhere; you choose where the file is saved.',
              style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 24),
            PassphraseField(
              controller: _passphrase,
              label: 'Backup passphrase',
              showStrength: true,
              autofocus: true,
              enabled: !_busy,
              onSubmitted: () {},
            ),
            const SizedBox(height: 16),
            PassphraseField(
              controller: _confirm,
              label: 'Repeat passphrase',
              enabled: !_busy,
              errorText: _error,
              onSubmitted: _export,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt),
              label: const Text('Save backup file'),
            ),
          ],
        ),
      ),
    );
  }
}

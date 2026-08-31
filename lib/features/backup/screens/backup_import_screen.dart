import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dula_auth/core/backup/aegis_import.dart';
import 'package:dula_auth/core/backup/backup_file_io.dart';
import 'package:dula_auth/core/backup/backup_service.dart';
import 'package:dula_auth/core/backup/google_authenticator_migration.dart';
import 'package:dula_auth/core/backup/import_source_detector.dart';
import 'package:dula_auth/core/backup/third_party_import_result.dart';
import 'package:dula_auth/core/backup/twofas_import.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/otp/otp_uri.dart';
import 'package:dula_auth/core/theme/app_theme.dart';
import 'package:dula_auth/core/widgets/responsive_layout.dart';
import 'package:dula_auth/core/widgets/section_header.dart';
import 'package:dula_auth/features/auth/widgets/passphrase_field.dart';
import 'package:dula_auth/features/backup/screens/backup_import_review_screen.dart';

/// Entry point for importing accounts, from a pasted code or a file.
///
/// Caller: `lib/features/settings/screens/settings_screen.dart`. No data
/// schema of its own — each source parser owns its own shape, and this
/// screen only dispatches to the right one and forwards the result to
/// [BackupImportReviewScreen].
///
/// Supports, in the priority order ADR-0013 sets: plain `otpauth://` links
/// and Google Authenticator `otpauth-migration://` payloads (pasted text),
/// this app's own encrypted export, and Aegis / 2FAS JSON exports (files).
/// Camera scanning is deliberately not duplicated here — Add Account already
/// owns that path for single `otpauth://` credentials; extending it to
/// recognise a migration QR as well is left as a follow-up rather than a
/// second copy of the scanner in this screen.
///
/// Added for the user instruction "go ahead with phase 4".
class BackupImportScreen extends ConsumerStatefulWidget {
  const BackupImportScreen({super.key});

  @override
  ConsumerState<BackupImportScreen> createState() => _BackupImportScreenState();
}

class _BackupImportScreenState extends ConsumerState<BackupImportScreen> {
  final TextEditingController _pasteController = TextEditingController();
  final TextEditingController _passphraseController = TextEditingController();
  bool _busy = false;
  String? _error;

  int _idCounter = 0;
  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  @override
  void dispose() {
    _pasteController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  void _openReview(List<OtpAccount> accounts, String sourceLabel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BackupImportReviewScreen(
          incoming: accounts,
          sourceLabel: sourceLabel,
        ),
      ),
    );
  }

  Future<void> _submitPastedCode() async {
    final code = _pasteController.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    List<OtpAccount>? accounts;
    var sourceLabel = 'Pasted code';

    if (code.toLowerCase().startsWith('otpauth-migration://')) {
      accounts = GoogleAuthenticatorMigration.parse(code, newId: _newId);
      sourceLabel = 'Google Authenticator export';
    } else if (code.toLowerCase().startsWith('otpauth://')) {
      final single = OtpUri.parse(code, id: _newId());
      accounts = single == null ? null : [single];
    }

    if (!mounted) return;
    setState(() => _busy = false);

    if (accounts == null) {
      setState(() => _error =
          'That does not look like an otpauth:// or otpauth-migration:// code.');
      return;
    }
    _openReview(accounts, sourceLabel);
  }

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final content = await BackupFileIO.pickAndRead(
      allowedExtensions: const ['json', '2fas'],
    );

    if (!mounted) return;
    setState(() => _busy = false);
    if (content == null) return; // Cancelled, or unreadable as text.

    switch (ImportSourceDetector.detect(content)) {
      case BackupSourceKind.ownFormat:
        if (mounted) await _promptForOwnFormatPassphrase(content);
      case BackupSourceKind.aegis:
        _handleThirdParty(
          AegisImport.parse(content, newId: _newId),
          'Aegis export',
        );
      case BackupSourceKind.twoFas:
        _handleThirdParty(
          TwoFasImport.parse(content, newId: _newId),
          '2FAS export',
        );
      case BackupSourceKind.unrecognized:
        setState(() => _error =
            'This file is not a backup this app recognises (own export, '
            'Aegis, or 2FAS).');
    }
  }

  void _handleThirdParty(ThirdPartyImportResult result, String sourceLabel) {
    switch (result) {
      case ThirdPartyImportSuccess(:final accounts):
        _openReview(accounts, sourceLabel);
      case ThirdPartyImportRequiresPassword():
        setState(() => _error =
            '$sourceLabel is password-protected. This app cannot decrypt '
            'it — re-export without a password and try again.');
      case ThirdPartyImportUnrecognized():
        setState(() =>
            _error = 'This does not look like a valid $sourceLabel.');
    }
  }

  Future<void> _promptForOwnFormatPassphrase(String content) async {
    _passphraseController.clear();
    const dialogError = null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Backup passphrase'),
          content: PassphraseField(
            controller: _passphraseController,
            label: 'Passphrase',
            autofocus: true,
            errorText: dialogError,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final result =
        await BackupService.import(content, _passphraseController.text);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case BackupImportSuccess(:final accounts):
        _openReview(accounts, 'Your backup');
      case BackupImportWrongPassphrase():
        setState(() => _error = 'That passphrase did not open the backup.');
      case BackupImportMalformed():
        setState(() =>
            _error = 'This file could not be read as a backup from this app.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import accounts')),
      body: ResponsiveLayout(
        maxWidth: 600,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ListView(
          children: [
            const SectionHeader('From a code'),
            const SizedBox(height: 8),
            const Text(
              'Paste an otpauth:// link, or the otpauth-migration:// text '
              'from a Google Authenticator export.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pasteController,
              maxLines: 3,
              enabled: !_busy,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'otpauth://... or otpauth-migration://...',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _submitPastedCode,
              child: const Text('Import from code'),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader('From a file'),
            const SizedBox(height: 8),
            const Text(
              'A backup exported from this app, or an Aegis or 2FAS export '
              '(unencrypted only — this app does not decrypt password-'
              'protected exports from other apps).',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose a file'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 20),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

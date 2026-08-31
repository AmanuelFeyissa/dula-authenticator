import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dula_auth/core/app_version.dart';
import 'package:dula_auth/core/branding/branded_logo.dart';
import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/core/config/deployment_config.dart';
import 'package:dula_auth/core/settings/app_settings.dart';
import 'package:dula_auth/core/widgets/responsive_layout.dart';
import 'package:dula_auth/features/auth/providers/auth_provider.dart';
import 'package:dula_auth/features/auth/screens/change_credential_screen.dart';
import 'package:dula_auth/features/backup/screens/backup_export_screen.dart';
import 'package:dula_auth/features/backup/screens/backup_import_screen.dart';
import 'package:dula_auth/features/settings/providers/settings_provider.dart';

/// Security settings.
///
/// Caller: `lib/features/home/screens/home_screen.dart`. Reads and writes
/// `settingsProvider`, and calls `AuthNotifier.setBiometricUnlockEnabled` and
/// `resetApp`. No data schema of its own — persistence belongs to
/// `SettingsRepository` and `AuthRepository`.
///
/// Added for the user instruction "go ahead on phase 3". Every security
/// behaviour the app has that a reasonable person might want off is on this
/// screen, per the standing requirement that these be choices rather than
/// impositions (ADR-0011).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final auth = ref.watch(authStateProvider);
    final branding = ref.watch(brandingConfigProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: branding.primarySeedColor,
        foregroundColor: Colors.white,
        title: const Text('Settings'),
      ),
      body: ResponsiveLayout(
        maxWidth: 700,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: ListView(
          children: [
            const _SectionHeader('Unlocking'),
            _biometricTile(context, ref, settings, auth),
            ListTile(
              leading: const Icon(Icons.password, color: Colors.white70),
              title: const Text('Change PIN or passphrase'),
              subtitle: Text(
                'Currently: ${auth.credentialKind.label}',
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ChangeCredentialScreen(),
                ),
              ),
            ),
            const Divider(color: Colors.white12, height: 32),
            const _SectionHeader('Automatic locking'),
            ListTile(
              leading: const Icon(Icons.lock_clock, color: Colors.white70),
              title: const Text('Lock when the app is in the background'),
              subtitle: Text(
                settings.autoLock.label,
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: DropdownButton<AutoLockDelay>(
                value: settings.autoLock,
                dropdownColor: const Color(0xFF1E1B4B),
                underline: const SizedBox.shrink(),
                onChanged: (value) {
                  if (value != null) {
                    ref.read(settingsProvider.notifier).setAutoLock(value);
                  }
                },
                items: [
                  for (final option in AutoLockDelay.values)
                    DropdownMenuItem(
                      value: option,
                      child: Text(option.label),
                    ),
                ],
              ),
            ),
            if (settings.autoLock == AutoLockDelay.never)
              const _Advisory(
                'The app will stay unlocked until you close it. Anyone with '
                'your unlocked device can read your codes.',
              ),
            const Divider(color: Colors.white12, height: 32),
            const _SectionHeader('Organization policy'),
            SwitchListTile(
              secondary: const Icon(Icons.event_repeat, color: Colors.white70),
              title: const Text('Require periodic credential changes'),
              subtitle: Text(
                settings.credentialRotationEnabled
                    ? 'Every ${settings.credentialRotationDays} days'
                    : 'Off — recommended',
                style: const TextStyle(color: Colors.white54),
              ),
              value: settings.credentialRotationEnabled,
              onChanged: (value) => ref
                  .read(settingsProvider.notifier)
                  .setCredentialRotationEnabled(value),
            ),
            const _Advisory(
              'NIST SP 800-63B advises against forced periodic changes: they '
              'push people toward predictable variations of one secret. This '
              'exists for deployments whose compliance rules require it.',
            ),
            if (settings.credentialRotationEnabled)
              _rotationPeriodTile(ref, settings),
            const Divider(color: Colors.white12, height: 32),
            const _SectionHeader('Backup'),
            ListTile(
              leading: const Icon(Icons.save_alt, color: Colors.white70),
              title: const Text('Export backup'),
              subtitle: const Text(
                'Save every account to a local encrypted file.',
                style: TextStyle(color: Colors.white54),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BackupExportScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.white70),
              title: const Text('Import accounts'),
              subtitle: const Text(
                'From this app\'s backup, a code, Aegis, or 2FAS.',
                style: TextStyle(color: Colors.white54),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BackupImportScreen()),
              ),
            ),
            const Divider(color: Colors.white12, height: 32),
            const _SectionHeader('About'),
            ListTile(
              leading: const BrandedLogo(size: 28),
              title: Text(branding.appName),
              subtitle: Text(
                'Version ${ref.watch(packageInfoProvider).version} · Apache License 2.0\n'
                'Developed by ${branding.developerName}',
                style: const TextStyle(color: Colors.white54),
              ),
              isThreeLine: true,
            ),
            const Divider(color: Colors.white12, height: 32),
            const _SectionHeader('Danger zone'),
            ListTile(
              leading:
                  const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: const Text(
                'Erase everything',
                style: TextStyle(color: Colors.redAccent),
              ),
              subtitle: const Text(
                'Deletes every account and returns the app to first-run setup.',
                style: TextStyle(color: Colors.white54),
              ),
              onTap: () => _confirmReset(context, ref),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _biometricTile(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
    AuthState auth,
  ) {
    // A device without a biometric implementation gets an explanation rather
    // than a switch that silently does nothing (ADR-0005, ADR-0006).
    if (!auth.biometricsAvailable) {
      return const ListTile(
        leading: Icon(Icons.fingerprint, color: Colors.white24),
        title: Text(
          'Unlock with biometrics',
          style: TextStyle(color: Colors.white38),
        ),
        subtitle: Text(
          'Not available on this device. Your PIN or passphrase is the only '
          'way in, which is by design — it always works.',
          style: TextStyle(color: Colors.white38),
        ),
        enabled: false,
      );
    }

    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint, color: Colors.tealAccent),
      title: const Text('Unlock with biometrics'),
      subtitle: const Text(
        'Faster, and your PIN or passphrase keeps working.',
        style: TextStyle(color: Colors.white54),
      ),
      value: settings.biometricUnlockEnabled,
      onChanged: (value) async {
        final applied = await ref
            .read(authStateProvider.notifier)
            .setBiometricUnlockEnabled(value);
        if (!applied && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Biometrics could not be enabled on this device.'),
            ),
          );
        }
      },
    );
  }

  Widget _rotationPeriodTile(WidgetRef ref, AppSettings settings) {
    final options = ref.watch(deploymentConfigProvider).credentialRotationOptionsDays;
    return ListTile(
      leading: const SizedBox(width: 24),
      title: const Text('Change every'),
      trailing: DropdownButton<int>(
        value: options.contains(settings.credentialRotationDays)
            ? settings.credentialRotationDays
            : AppSettings.defaultRotationDays,
        dropdownColor: const Color(0xFF1E1B4B),
        underline: const SizedBox.shrink(),
        onChanged: (value) {
          if (value != null) {
            ref
                .read(settingsProvider.notifier)
                .setCredentialRotationDays(value);
          }
        },
        items: [
          for (final days in options)
            DropdownMenuItem(value: days, child: Text('$days days')),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B4B),
        title: const Text('Erase everything?'),
        content: const Text(
          'Every enrolled account will be deleted from this device and cannot '
          'be recovered. You will lose access to any account whose codes are '
          'only stored here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'ERASE',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(authStateProvider.notifier).resetApp();
    // The lifecycle wrapper swaps to first-run setup on its own; this screen
    // just needs to get out of the way.
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.tealAccent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

/// A plain explanation under a setting, for the cases where the honest answer
/// is longer than a subtitle.
class _Advisory extends StatelessWidget {
  final String text;

  const _Advisory(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }
}

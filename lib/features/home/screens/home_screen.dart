import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/otp/otp_type.dart';
import 'package:dula_auth/core/widgets/responsive_layout.dart';
import 'package:dula_auth/features/home/providers/home_provider.dart';
import 'package:flutter/services.dart';
import 'package:dula_auth/core/branding/branded_logo.dart';
import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/features/accounts/screens/add_account_screen.dart';
import 'package:dula_auth/features/settings/screens/settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsState = ref.watch(accountListProvider);
    final theme = Theme.of(context);
    final branding = ref.watch(brandingConfigProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: branding.primarySeedColor,
        leading: const Padding(
          padding: EdgeInsets.all(8.0),
          child: BrandedLogo(),
        ),
        title: Text(
          branding.appName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings, color: Colors.white),
            onSelected: (value) {
              if (value == 'about') {
                _showAboutDialog(context, branding);
              } else if (value == 'settings') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.tune, color: Colors.black54),
                    SizedBox(width: 12),
                    Text('Settings'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.black54),
                    SizedBox(width: 12),
                    Text('About'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ResponsiveLayout(
        maxWidth: 800,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: accountsState.when(
          data: (accounts) {
            if (accounts.isEmpty) {
              return _buildEmptyState(context);
            }

            return ListView.builder(
              itemCount: accounts.length,
              itemBuilder: (context, index) {
                final account = accounts[index];
                return _AccountCard(account: account);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToAddAccount(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Account'),
      ),
    );
  }

  void _navigateToAddAccount(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (c) => const AddAccountScreen()),
    );
  }

  void _showAboutDialog(BuildContext context, BrandingConfig branding) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B4B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandedLogo(size: 80),
            const SizedBox(height: 20),
            Text(
              '${branding.appName} Authenticator',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Version 1.0.0',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const Divider(color: Colors.white24, height: 32),
            _buildInfoRow('Developer', branding.developerName),
            _buildInfoRow('License', 'Apache License 2.0'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('CLOSE'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 80, color: Colors.white24),
          const SizedBox(height: 24),
          Text(
            'No Accounts Yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Scan a QR code to begin',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  final OtpAccount account;

  const _AccountCard({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeAsync = ref.watch(currentTimerProvider);
    final now = timeAsync.value ?? DateTime.now();

    // A secret that cannot produce a code is shown as an error rather than
    // rendered as plausible-but-wrong digits.
    String code;
    String? codeError;
    try {
      code = account.generateCode(time: now);
    } on FormatException {
      code = '';
      codeError = 'Invalid secret';
    }

    final isCounterBased = account.type == OtpType.hotp;
    final int remainingSeconds = account.secondsRemaining(time: now);
    final double progress =
        isCounterBased ? 0 : remainingSeconds / account.period;

    final formattedCode = _formatCode(code);

    return Dismissible(
      key: Key(account.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Account'),
            content: Text('Are you sure you want to remove ${account.accountName}?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCEL')),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('DELETE', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        ref.read(accountListProvider.notifier).deleteAccount(account.id);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: code));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Code copied to clipboard',
                textAlign: TextAlign.center,
              ),
              duration: Duration(seconds: 1),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.issuer.isNotEmpty ? account.issuer : 'Authenticator',
                      style: const TextStyle(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      account.accountName,
                      style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      codeError ?? formattedCode,
                      style: TextStyle(
                        fontSize: codeError != null ? 20 : 34,
                        color: codeError != null
                            ? Colors.redAccent
                            : Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: codeError != null ? 0 : 2.0,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCounterBased)
                // HOTP codes do not expire on a clock; the user advances the
                // counter explicitly when they need the next one.
                Tooltip(
                  message: 'Generate next code',
                  child: IconButton(
                    iconSize: 32,
                    color: Colors.tealAccent,
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ref
                        .read(accountListProvider.notifier)
                        .advanceCounter(account.id),
                  ),
                )
              else
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white12,
                        color: remainingSeconds <= 5
                            ? Colors.redAccent
                            : Colors.tealAccent,
                        strokeWidth: 4,
                      ),
                      Center(
                        child: Text(
                          remainingSeconds.toString(),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: remainingSeconds <= 5
                                ? Colors.redAccent
                                : Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Groups a code for readability: 6-digit as 3+3, 8-digit as 4+4.
  /// Steam's five characters are left intact.
  static String _formatCode(String code) {
    if (code.length == 6) return '${code.substring(0, 3)} ${code.substring(3)}';
    if (code.length == 8) return '${code.substring(0, 4)} ${code.substring(4)}';
    return code;
  }
}

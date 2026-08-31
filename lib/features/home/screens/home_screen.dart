import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/otp/otp_type.dart';
import 'package:dula_auth/core/widgets/responsive_layout.dart';
import 'package:dula_auth/features/home/providers/home_provider.dart';
import 'package:flutter/services.dart';
import 'package:dula_auth/core/app_version.dart';
import 'package:dula_auth/core/branding/branded_logo.dart';
import 'package:dula_auth/core/branding/branding_config.dart';
import 'package:dula_auth/core/config/deployment_config.dart';
import 'package:dula_auth/features/accounts/screens/add_account_screen.dart';
import 'package:dula_auth/features/settings/screens/settings_screen.dart';

/// The account list: search, tag/favorite filtering, manual reordering, and
/// per-account actions (edit, favorite, tags, delete).
///
/// See docs/adr/0015-account-management.md. Manual drag-reorder is only
/// offered against the unfiltered list — reordering a filtered subset has no
/// unambiguous meaning for where a dropped item lands in the full list, so a
/// search or filter in effect switches the list to a plain, non-draggable
/// view rather than guessing.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _activeTag;
  bool _favoritesOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _filtering =>
      _query.isNotEmpty || _activeTag != null || _favoritesOnly;

  List<OtpAccount> _filtered(List<OtpAccount> accounts) {
    if (!_filtering) return accounts;
    final query = _query.toLowerCase();
    return accounts.where((a) {
      if (_favoritesOnly && !a.isFavorite) return false;
      if (_activeTag != null && !a.tags.contains(_activeTag)) return false;
      if (query.isEmpty) return true;
      return a.issuer.toLowerCase().contains(query) ||
          a.accountName.toLowerCase().contains(query) ||
          a.tags.any((t) => t.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: accountsState.when(
          data: (accounts) {
            if (accounts.isEmpty) return _buildEmptyState(context);

            final tags = accounts.expand((a) => a.tags).toSet().toList()
              ..sort();
            final filtered = _filtered(accounts);

            return Column(
              children: [
                _buildSearchField(),
                if (tags.isNotEmpty || accounts.any((a) => a.isFavorite))
                  _buildFilterChips(tags),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? _buildNoMatches()
                      : _filtering
                          ? _buildStaticList(filtered)
                          : _buildReorderableList(filtered),
                ),
              ],
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

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search accounts',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white38),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white38),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(List<String> tags) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          FilterChip(
            label: const Text('★ Favorites'),
            selected: _favoritesOnly,
            onSelected: (v) => setState(() => _favoritesOnly = v),
          ),
          for (final tag in tags) ...[
            const SizedBox(width: 8),
            FilterChip(
              label: Text(tag),
              selected: _activeTag == tag,
              onSelected: (v) =>
                  setState(() => _activeTag = v ? tag : null),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoMatches() {
    return const Center(
      child: Text(
        'No accounts match this search or filter.',
        style: TextStyle(color: Colors.white54),
      ),
    );
  }

  Widget _buildStaticList(List<OtpAccount> accounts) {
    return ListView.builder(
      itemCount: accounts.length,
      itemBuilder: (context, index) => accounts[index].loadError != null
          ? _CorruptedAccountCard(account: accounts[index])
          : _AccountCard(account: accounts[index]),
    );
  }

  Widget _buildReorderableList(List<OtpAccount> accounts) {
    return ReorderableListView.builder(
      itemCount: accounts.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        final ids = accounts.map((a) => a.id).toList();
        final id = ids.removeAt(oldIndex);
        ids.insert(newIndex, id);
        ref.read(accountListProvider.notifier).reorder(ids);
      },
      itemBuilder: (context, index) {
        final account = accounts[index];
        return KeyedSubtree(
          key: Key(account.id),
          child: account.loadError != null
              ? _CorruptedAccountCard(account: account)
              : _AccountCard(account: account),
        );
      },
    );
  }

  void _navigateToAddAccount(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (c) => const AddAccountScreen()),
    );
  }

  void _showAboutDialog(BuildContext context, BrandingConfig branding) {
    final version = ref.read(packageInfoProvider).version;

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
              branding.appName,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              'Version $version',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
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

/// A card for an account whose secret failed to decrypt (ADR-0015 §7).
///
/// Deliberately minimal: no code, no copy, no favorite/tag/edit actions —
/// there is nothing usable to act on beyond identifying and removing it.
class _CorruptedAccountCard extends ConsumerWidget {
  final OtpAccount account;

  const _CorruptedAccountCard({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: Key(account.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Account'),
          content: Text(
            'Remove ${account.displayName}? Its secret could not be read, '
            'so this cannot be undone by anything other than re-enrolling it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('DELETE', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
      onDismissed: (_) =>
          ref.read(accountListProvider.notifier).deleteAccount(account.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.issuer.isNotEmpty ? account.issuer : 'Authenticator',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    account.accountName,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Could not read this account\'s secret. Swipe to remove it.',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
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
          final snackbarSeconds =
              ref.read(deploymentConfigProvider).copiedToClipboardSnackbarSeconds;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Code copied to clipboard',
                textAlign: TextAlign.center,
              ),
              duration: Duration(seconds: snackbarSeconds),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                account.issuer.isNotEmpty ? account.issuer : 'Authenticator',
                                style: const TextStyle(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (account.isFavorite)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.star, size: 14, color: Colors.amberAccent),
                              ),
                          ],
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
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20),
                    onSelected: (value) => _handleMenu(context, ref, value),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'favorite',
                        child: Row(
                          children: [
                            Icon(
                              account.isFavorite ? Icons.star : Icons.star_border,
                              size: 18,
                            ),
                            const SizedBox(width: 12),
                            Text(account.isFavorite
                                ? 'Remove from favorites'
                                : 'Add to favorites'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'tags',
                        child: Row(
                          children: [
                            Icon(Icons.label_outline, size: 18),
                            SizedBox(width: 12),
                            Text('Manage tags'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 12),
                            Text('Edit'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (account.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in account.tags)
                      Chip(
                        label: Text(tag, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        side: BorderSide.none,
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleMenu(BuildContext context, WidgetRef ref, String value) {
    final notifier = ref.read(accountListProvider.notifier);
    switch (value) {
      case 'favorite':
        notifier.toggleFavorite(account.id);
      case 'tags':
        _showTagEditor(context, ref);
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AddAccountScreen(existing: account)),
        );
    }
  }

  Future<void> _showTagEditor(BuildContext context, WidgetRef ref) async {
    final tags = List<String>.from(account.tags);
    final controller = TextEditingController();

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1B4B),
          title: const Text('Tags'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in tags)
                      Chip(
                        label: Text(tag),
                        onDeleted: () => setDialogState(() => tags.remove(tag)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'New tag',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    final trimmed = value.trim();
                    if (trimmed.isNotEmpty && !tags.contains(trimmed)) {
                      setDialogState(() {
                        tags.add(trimmed);
                        controller.clear();
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(tags),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await ref.read(accountListProvider.notifier).setTags(account.id, result);
    }
  }

  /// Groups a code for readability: 6-digit as 3+3, 8-digit as 4+4.
  /// Steam's five characters are left intact.
  static String _formatCode(String code) {
    if (code.length == 6) return '${code.substring(0, 3)} ${code.substring(3)}';
    if (code.length == 8) return '${code.substring(0, 4)} ${code.substring(4)}';
    return code;
  }
}

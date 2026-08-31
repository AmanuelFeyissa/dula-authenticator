import 'package:flutter/material.dart';

import 'package:dula_auth/core/theme/app_theme.dart';

/// An uppercase, small-caps-style label introducing a group of settings or
/// fields (e.g. "SECURITY", "NEW CREDENTIAL", "FROM A CODE").
///
/// Before this widget existed, four screens each defined their own version
/// of this label with slightly different specs that had drifted apart
/// (`fontSize` 11 vs 12, `letterSpacing` 1.4 vs 1.2) despite serving the
/// same visual role — see docs/adr's Phase 6 UI-polish notes. This widget is
/// the single source of that style, via [ThemeData.textTheme.labelSmall].
class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

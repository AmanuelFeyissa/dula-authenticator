import 'package:flutter/material.dart';

import 'package:dula_auth/core/branding/branding_config.dart';

/// A single, consistent spacing scale. Before this existed, screens used
/// near-random values (8, 12, 16, 18, 20, 24, 28, 32) for conceptually
/// identical gaps — an 18px card padding next to a 16px one, a 20px screen
/// margin next to a 24px one elsewhere. Every screen should build its gaps
/// from these constants rather than a new literal.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Consistent corner radii. Before this, containers used 12, 16, or 20
/// depending on which screen wrote them, with no rule for which shape a
/// given kind of surface should have.
class AppRadius {
  const AppRadius._();

  static const double field = 12; // Text fields, small chips.
  static const double card = 16; // Account cards, choice cards, tiles.
  static const double dialog = 20; // Dialogs, bottom sheets.
}

/// The app's fixed secondary accent — used for icons, secondary buttons, and
/// section-header labels throughout the app (22 call sites before this
/// theme existed, already consistent with each other). Deliberately *not*
/// derived from [ColorScheme.tertiary]: Material 3's seed-based tertiary
/// generation can land anywhere in the palette (purple, pink, amber — not
/// necessarily teal) depending on the seed hue, and this app's actual
/// shipped logo (`assets/branding/logo.png`) already has a teal-to-blue
/// gradient, so keeping this fixed is what makes the accent continue to
/// match the logo regardless of which `primarySeedColorHex` a deployer
/// chooses.
const Color accentColor = Colors.tealAccent;

/// Builds the app's [ThemeData] from the deployer's [BrandingConfig] seed
/// color.
///
/// Previously, `main.dart` built a [ColorScheme] from the seed but then
/// overrode its `surface` with a hardcoded, unrelated dark violet
/// (`0xFF1E1B4B`), and set [ThemeData.scaffoldBackgroundColor] to the raw,
/// fully-saturated seed color instead of a proper dark surface tone. Both of
/// those overrides fought the seed-derived palette rather than using it —
/// that mismatch, not the seed color itself, was the "purple background
/// clashes with the blue logo" complaint this phase was scoped to fix.
/// Removing them lets Material 3 generate one coherent dark palette from the
/// single seed color, the way [ColorScheme.fromSeed] is meant to be used.
ThemeData buildAppTheme(BrandingConfig branding) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: branding.primarySeedColor,
    brightness: Brightness.dark,
  );

  final textTheme = _buildTextTheme(colorScheme);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: colorScheme.surface,
      titleTextStyle: textTheme.titleLarge,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.dialog),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      space: AppSpacing.xl,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        foregroundColor: accentColor,
        side: const BorderSide(color: accentColor),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
    ),
  );
}

/// The full-bleed gradient background used on the lock and credential-setup
/// screens. Previously this was a hardcoded three-stop violet gradient
/// (`0xFF4C1D95` → `0xFF5B21B6` → `0xFF1E1B4B`) duplicated verbatim in both
/// screens, entirely disconnected from the brand seed color. Deriving it
/// from [ColorScheme.primaryContainer] down to [ColorScheme.surface] ties it
/// to whatever seed color a deployer configures, and it fades into the same
/// surface tone every other screen uses, instead of a separately-hardcoded
/// dark navy.
BoxDecoration brandGradientBackground(ColorScheme colorScheme) {
  return BoxDecoration(
    gradient: LinearGradient(
      colors: [
        colorScheme.primaryContainer,
        colorScheme.surfaceContainerHighest,
        colorScheme.surface,
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
  );
}

TextTheme _buildTextTheme(ColorScheme colorScheme) {
  const base = Typography.whiteMountainView;
  return base.copyWith(
    // Brand wordmark on the lock/setup screens. Deliberately not
    // `headlineSmall` — that role is already used, at its normal Material
    // weight, for the home screen's "No Accounts Yet" empty-state title, and
    // overloading it here would have made that title unexpectedly bold and
    // wide-tracked too.
    displaySmall: base.displaySmall?.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w900,
      letterSpacing: 2.0,
    ),
    // Screen/step question headings ("How would you like to unlock?").
    titleLarge: base.titleLarge?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
    // Step titles ("Create PIN", choice-card labels).
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
    // Long explanatory paragraphs.
    bodyMedium: base.bodyMedium?.copyWith(
      fontSize: 13,
      height: 1.4,
      color: colorScheme.onSurfaceVariant,
    ),
    // Captions / hints.
    bodySmall: base.bodySmall?.copyWith(
      fontSize: 12,
      height: 1.35,
      color: colorScheme.onSurfaceVariant,
    ),
    // Uppercase section headers (SECURITY, BACKUP, ...).
    labelSmall: base.labelSmall?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.4,
      color: accentColor,
    ),
  );
}

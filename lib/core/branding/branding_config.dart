import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runtime, deployer-configurable branding for the app UI.
///
/// See docs/adr/0002-white-label-branding.md: package/bundle identifiers and
/// the OS-level app name are compile-time (per-platform build metadata), but
/// everything the UI itself displays is read from this config so any
/// organization can rebrand by editing [_assetPath] without touching Dart
/// source.
class BrandingConfig {
  /// Display name shown in the app bar, lock screen, and window title.
  final String appName;

  /// Optional asset path for a logo image. When null, the UI falls back to a
  /// built-in icon instead of shipping a placeholder image asset.
  final String? logoAssetPath;

  /// Seed color for [ColorScheme.fromSeed].
  final Color primarySeedColor;

  /// Organization name shown in the About dialog. Generic by default.
  final String organizationName;

  /// Organization department/team shown in the About dialog. Generic by
  /// default.
  final String organizationDepartment;

  /// Original author of the application, shown in the About dialog.
  ///
  /// Deployers rebranding the app may add their own organization details via
  /// [organizationName]/[organizationDepartment], but attribution to the
  /// original author is required by the Apache-2.0 NOTICE and should be
  /// preserved.
  final String developerName;

  /// Generic label for the deployer's enterprise directory system, used in
  /// lock-screen copy instead of naming a specific vendor product.
  final String directorySystemLabel;

  const BrandingConfig({
    required this.appName,
    required this.logoAssetPath,
    required this.primarySeedColor,
    required this.organizationName,
    required this.organizationDepartment,
    required this.developerName,
    required this.directorySystemLabel,
  });

  static const String _assetPath = 'assets/branding/branding.json';

  static const BrandingConfig fallback = BrandingConfig(
    appName: 'Dula Authenticator',
    logoAssetPath: 'assets/branding/logo.png',
    primarySeedColor: Color(0xFF1D4ED8),
    organizationName: 'Your Organization',
    organizationDepartment: 'IT / Security',
    developerName: 'Amanuel Feyissa Kussa',
    directorySystemLabel: "your organization's enterprise directory",
  );

  /// Loads branding from [_assetPath]. Falls back to [fallback] if the asset
  /// is missing or malformed, so a broken/edited-incorrectly branding file
  /// never prevents the app from starting.
  static Future<BrandingConfig> load() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return BrandingConfig(
        appName: json['appName'] as String? ?? fallback.appName,
        logoAssetPath: json['logoAssetPath'] as String?,
        primarySeedColor: _parseColor(json['primarySeedColorHex'] as String?) ??
            fallback.primarySeedColor,
        organizationName:
            json['organizationName'] as String? ?? fallback.organizationName,
        organizationDepartment: json['organizationDepartment'] as String? ??
            fallback.organizationDepartment,
        developerName:
            json['developerName'] as String? ?? fallback.developerName,
        directorySystemLabel: json['directorySystemLabel'] as String? ??
            fallback.directorySystemLabel,
      );
    } catch (_) {
      return fallback;
    }
  }

  static Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(cleaned.length == 6 ? 0xFF000000 | value : value);
  }
}

/// Overridden with the loaded [BrandingConfig] in `main()` before [runApp],
/// so every widget can read branding synchronously without an async gap.
final brandingConfigProvider = Provider<BrandingConfig>((ref) {
  throw UnimplementedError(
    'brandingConfigProvider must be overridden in main() with a loaded BrandingConfig.',
  );
});

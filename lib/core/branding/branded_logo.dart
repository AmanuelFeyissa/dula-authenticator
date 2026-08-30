import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dula_auth/core/branding/branding_config.dart';

/// Shows the deployer-configured logo image if [BrandingConfig.logoAssetPath]
/// is set, otherwise falls back to a generic shield icon so the app never
/// ships a placeholder image asset of its own (see ADR-0002 - the original
/// bank's logo is not redistributed with this open-source project).
class BrandedLogo extends ConsumerWidget {
  final double size;
  final Color? fallbackColor;

  const BrandedLogo({super.key, this.size = 40, this.fallbackColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(brandingConfigProvider);
    if (branding.logoAssetPath != null) {
      return Image.asset(branding.logoAssetPath!, height: size, width: size);
    }
    return Icon(
      Icons.shield_outlined,
      size: size,
      color: fallbackColor ?? Colors.white,
    );
  }
}

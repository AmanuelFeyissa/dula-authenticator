import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Overridden with the loaded [PackageInfo] in `main()` before [runApp], so
/// any screen that displays the app's real release version (About dialogs in
/// `home_screen.dart` and `settings_screen.dart`) reads one source instead of
/// each hardcoding its own literal — see
/// docs/adr/0016-deployment-configuration.md.
final packageInfoProvider = Provider<PackageInfo>((ref) {
  throw UnimplementedError(
    'packageInfoProvider must be overridden in main() with a loaded PackageInfo.',
  );
});

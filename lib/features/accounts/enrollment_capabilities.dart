import 'package:flutter/foundation.dart';

/// Enrollment-method availability by platform, verified against the actual
/// installed plugins' documented platform support rather than assumed
/// (CLAUDE.md "Platform capability — verify, don't assume"; ADR-0006).
///
/// Every platform keeps at least manual secret-key entry, which
/// `add_account_screen.dart` shows unconditionally — offices that ban
/// cameras must never be limited to a method that doesn't work for them.
class EnrollmentCapabilities {
  /// `mobile_scanner` ships camera scanning for Android, iOS, macOS, and
  /// web only — Windows and Linux have no implementation and would show a
  /// button that silently does nothing.
  static bool get cameraScanning {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// `pasteboard`'s `Pasteboard.image` supports every native platform this
  /// app ships for. Originally desktop-only in this app; extended to
  /// Android and iOS (ADR-0006 §2) to close the no-camera-office gap on
  /// mobile. Web is excluded, matching the existing image-import scope.
  static bool get clipboardImagePaste {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// Dropping a QR image file onto the window is a desktop interaction with
  /// no mobile equivalent, so this stays desktop-only.
  static bool get dragAndDropImport {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }
}

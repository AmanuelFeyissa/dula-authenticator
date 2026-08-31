import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dula_auth/features/accounts/enrollment_capabilities.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = null);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('EnrollmentCapabilities.cameraScanning (mobile_scanner support)', () {
    test('true on Android, iOS, macOS', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(EnrollmentCapabilities.cameraScanning, isTrue, reason: '$platform');
      }
    });

    test('false on Windows and Linux', () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(EnrollmentCapabilities.cameraScanning, isFalse, reason: '$platform');
      }
    });
  });

  group('EnrollmentCapabilities.clipboardImagePaste (pasteboard support)', () {
    test('true on Windows, macOS, Linux, Android, and iOS', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(EnrollmentCapabilities.clipboardImagePaste, isTrue,
            reason: '$platform');
      }
    });
  });

  group('EnrollmentCapabilities.dragAndDropImport', () {
    test('true only on desktop platforms', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(EnrollmentCapabilities.dragAndDropImport, isTrue,
            reason: '$platform');
      }
    });

    test('false on Android and iOS', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(EnrollmentCapabilities.dragAndDropImport, isFalse,
            reason: '$platform');
      }
    });
  });
}

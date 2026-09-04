import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera scanner, pushed as its own route.
///
/// Caller: `lib/features/accounts/screens/add_account_screen.dart`, via
/// `qrScanLauncherProvider`. Pops with the scanned string, or with `null` if
/// the user backs out. No data schema of its own — parsing the scanned value
/// belongs to `OtpUri`, on the Add Account screen.
///
/// This is a route rather than a branch inside Add Account's `build()`, and it
/// owns its [MobileScannerController] explicitly, because the previous inline
/// version left the camera running: `MobileScanner` does not dispose a
/// controller it did not create, and swapping the widget out of a build method
/// left the native Android camera surface painted over the form, so a
/// successful scan looked like nothing had happened even though the fields
/// behind it had been filled in.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    // onDetect fires for every frame the code stays in view. Without this
    // guard the route would pop repeatedly and take the Add Account screen
    // down with it.
    if (_handled) return;

    String? value;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        value = raw;
        break;
      }
    }
    if (value == null) return;

    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}

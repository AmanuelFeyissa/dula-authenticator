import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dula_auth/core/models/totp_account.dart';
import 'package:dula_auth/core/totp_engine.dart';
import 'package:dula_auth/core/widgets/responsive_layout.dart';
import 'package:dula_auth/core/branding/branded_logo.dart';
import 'package:dula_auth/features/home/providers/home_provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';
import 'package:pasteboard/pasteboard.dart';

class AddAccountScreen extends ConsumerStatefulWidget {
  const AddAccountScreen({super.key});

  @override
  ConsumerState<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends ConsumerState<AddAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _issuerController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _secretController = TextEditingController();

  bool _isScanning = false;
  bool _isDragging = false;
  bool _isDecoding = false;

  @override
  void dispose() {
    _issuerController.dispose();
    _accountNameController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  void _processFoundUrl(String code) {
    if (code.startsWith('otpauth://totp/')) {
      try {
        final uri = Uri.parse(code);
        
        final pathSegments = uri.pathSegments;
        String label = pathSegments.isNotEmpty ? pathSegments.first : '';
        label = Uri.decodeComponent(label);

        String issuer = uri.queryParameters['issuer'] ?? '';
        String accountName = label;

        if (label.contains(':')) {
          final parts = label.split(':');
          issuer = parts[0].trim();
          accountName = parts.sublist(1).join(':').trim();
        }

        final secret = uri.queryParameters['secret'] ?? '';

        setState(() {
          if (issuer.isNotEmpty) _issuerController.text = issuer;
          if (accountName.isNotEmpty) _accountNameController.text = accountName;
          _secretController.text = secret;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR Code Scanned successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid QR Code format')),
        );
      }
    } else {
      final base32Regex = RegExp(r'^[A-Z2-7=]+$');
      if (base32Regex.hasMatch(code.toUpperCase().replaceAll(' ', ''))) {
        setState(() {
          _secretController.text = code.toUpperCase().replaceAll(' ', '');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Found text secret directly')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Decoded text found, but not parsed: $code')),
        );
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      final code = barcodes.first.rawValue!;
      setState(() => _isScanning = false);
      _processFoundUrl(code);
    }
  }

  Future<void> _handlePerformDrop(PerformDropEvent event) async {
    setState(() => _isDragging = false);
    if (event.session.items.isEmpty) return;
    final reader = event.session.items.first.dataReader;
    if (reader == null) return;

    bool handled = false;
    final formatsToCheck = [Formats.png, Formats.jpeg, Formats.webp];
    for (final format in formatsToCheck) {
      if (reader.canProvide(format)) {
        handled = true;
        reader.getFile(format, (file) async {
          try {
            final bytes = await file.readAll();
            _decodeDroppedImage(bytes);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to read dropped image: $e')),
              );
            }
          }
        });
        break;
      }
    }
    
    if (!handled && mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dropped item is not a recognized image format. Please drop a valid PNG, JPG, or WEBP.')),
       );
    }
  }

  Future<void> _pasteImage() async {
    try {
      final bytes = await Pasteboard.image;
      if (!mounted) return;
      if (bytes != null && bytes.isNotEmpty) {
        _decodeDroppedImage(bytes);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No image found in clipboard.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to read clipboard: $e')),
      );
    }
  }

  Future<void> _decodeDroppedImage(Uint8List bytes) async {
    setState(() => _isDecoding = true);
    try {
      final resultText = await compute(_decodeImageIsolate, bytes);
      if (!mounted) return;
      if (resultText != null && resultText.isNotEmpty && !resultText.startsWith('ALL_ATTEMPTS_FAILED_TO_FIND_QR')) {
        _processFoundUrl(resultText);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not decode QR. Isolate output: $resultText')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error decoding image: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isDecoding = false);
      }
    }
  }

  static String? _decodeImageIsolate(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return "DECODE_ERROR: Image parsed as null";
      
      final intList = Int32List(image.width * image.height);
      int i = 0;
      for (final p in image) {
        int a = p.a.toInt();
        int r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        if (a < 255) {
          r = ((r * a) + (255 * (255 - a))) ~/ 255;
          g = ((g * a) + (255 * (255 - a))) ~/ 255;
          b = ((b * a) + (255 * (255 - a))) ~/ 255;
        }
        intList[i++] = (0xFF000000 | (r << 16) | (g << 8) | b);
      }

      LuminanceSource source = RGBLuminanceSource(image.width, image.height, intList);
      
      try {
        var hybridBitmap = BinaryBitmap(HybridBinarizer(source));
        var result = QRCodeReader().decode(hybridBitmap);
        if (result.text.isNotEmpty) return result.text;
      } catch (_) {}

      try {
        var globalBitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
        var result = QRCodeReader().decode(globalBitmap);
        if (result.text.isNotEmpty) return result.text;
      } catch (_) {}

      try {
        var invertedBitmap = BinaryBitmap(HybridBinarizer(source.invert()));
        var result = QRCodeReader().decode(invertedBitmap);
        if (result.text.isNotEmpty) return result.text;
      } catch (_) {}

      try {
        final paddedWidth = (image.width * 1.5).toInt();
        final paddedHeight = (image.height * 1.5).toInt();
        final padded = img.Image(width: paddedWidth, height: paddedHeight);
        img.fill(padded, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(padded, image, dstX: (paddedWidth - image.width) ~/ 2, dstY: (paddedHeight - image.height) ~/ 2);
        
        final paddedIntList = Int32List(padded.width * padded.height);
        int j = 0;
        for (final p in padded) {
          int r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
          int a = p.a.toInt();
          if (a < 255) {
            r = ((r * a) + (255 * (255 - a))) ~/ 255;
            g = ((g * a) + (255 * (255 - a))) ~/ 255;
            b = ((b * a) + (255 * (255 - a))) ~/ 255;
          }
          paddedIntList[j++] = (0xFF000000 | (r << 16) | (g << 8) | b);
        }
        LuminanceSource paddedSource = RGBLuminanceSource(padded.width, padded.height, paddedIntList);
        var paddedBitmap = BinaryBitmap(GlobalHistogramBinarizer(paddedSource));
        var result = QRCodeReader().decode(paddedBitmap);
        if (result.text.isNotEmpty) return result.text;
      } catch (_) {}

      try {
        final scaled = img.copyResize(image, width: image.width * 2, height: image.height * 2, interpolation: img.Interpolation.nearest);
        final paddedWidth = (scaled.width * 1.5).toInt();
        final paddedHeight = (scaled.height * 1.5).toInt();
        final padded = img.Image(width: paddedWidth, height: paddedHeight);
        img.fill(padded, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(padded, scaled, dstX: (paddedWidth - scaled.width) ~/ 2, dstY: (paddedHeight - scaled.height) ~/ 2);
        
        final paddedIntList = Int32List(padded.width * padded.height);
        int j = 0;
        for (final p in padded) {
          int r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
          int a = p.a.toInt();
          if (a < 255) {
            r = ((r * a) + (255 * (255 - a))) ~/ 255;
            g = ((g * a) + (255 * (255 - a))) ~/ 255;
            b = ((b * a) + (255 * (255 - a))) ~/ 255;
          }
          paddedIntList[j++] = (0xFF000000 | (r << 16) | (g << 8) | b);
        }
        LuminanceSource paddedSource = RGBLuminanceSource(padded.width, padded.height, paddedIntList);
        var paddedBitmap = BinaryBitmap(GlobalHistogramBinarizer(paddedSource));
        var result = QRCodeReader().decode(paddedBitmap);
        if (result.text.isNotEmpty) return result.text;
      } catch (_) {}

      return "ALL_ATTEMPTS_FAILED_TO_FIND_QR";
    } catch (e) {
      return "CRITICAL_ISOLATE_ERROR: $e";
    }
  }

  void _saveAccount() async {
    if (_formKey.currentState!.validate()) {
      final account = TotpAccount(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        issuer: _issuerController.text.trim(),
        accountName: _accountNameController.text.trim(),
        secret: _secretController.text.trim().replaceAll(' ', '').toUpperCase(),
        algorithm: TotpAlgorithm.sha1,
      );

      final success = await ref.read(accountListProvider.notifier).addAccount(account);
      if (success) {
        if (mounted) Navigator.of(context).pop();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save account')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isScanning) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF5B21B6),
          title: const Text('Scan QR Code', style: TextStyle(color: Colors.white)),
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => setState(() => _isScanning = false),
          ),
        ),
        body: MobileScanner(
          onDetect: _onDetect,
        ),
      );
    }

    return DropRegion(
      formats: Formats.standardFormats,
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (DropOverEvent event) {
        if (event.session.items.isEmpty) return DropOperation.none;
        final item = event.session.items.first;
        if (item.dataReader?.canProvide(Formats.png) == true || 
            item.dataReader?.canProvide(Formats.jpeg) == true || 
            item.dataReader?.canProvide(Formats.webp) == true) {
           WidgetsBinding.instance.addPostFrameCallback((_) {
             if (mounted && !_isDragging) setState(() => _isDragging = true);
           });
           return DropOperation.copy;
        }
        return DropOperation.none;
      },
      onDropLeave: (DropEvent event) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isDragging) setState(() => _isDragging = false);
        });
      },
      onPerformDrop: _handlePerformDrop,
      child: Scaffold(
        backgroundColor: const Color(0xFF5B21B6),
        appBar: AppBar(
          backgroundColor: const Color(0xFF5B21B6),
          leading: const Padding(
            padding: EdgeInsets.all(8.0),
            child: BrandedLogo(),
          ),
          title: const Text('Add Account', style: TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        body: Stack(
          children: [
            ResponsiveLayout(
              maxWidth: 700,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() => _isScanning = true),
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Scan QR Code with Camera'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: const BorderSide(color: Colors.tealAccent),
                                foregroundColor: Colors.tealAccent,
                              ),
                            ),
                          ),
                          if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux)) ...[
                            const SizedBox(width: 16),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pasteImage,
                                icon: const Icon(Icons.paste),
                                label: const Text('Paste Image'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  side: const BorderSide(color: Colors.tealAccent),
                                  foregroundColor: Colors.tealAccent,
                                ),
                              ),
                            ),
                          ]
                        ],
                      ),
                      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux)) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: _isDragging ? Colors.tealAccent.withValues(alpha: 0.2) : Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _isDragging ? Colors.tealAccent : Colors.white24, style: BorderStyle.solid),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.file_upload_outlined, size: 48, color: _isDragging ? Colors.tealAccent : Colors.white54),
                              const SizedBox(height: 12),
                              const Text(
                                'Drag and Drop QR Image Here',
                                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      const Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white24)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text('OR ENTER MANUALLY', style: TextStyle(color: Colors.white54, fontSize: 12)),
                          ),
                          Expanded(child: Divider(color: Colors.white24)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _issuerController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Issuer (e.g. Google, GitHub)',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          prefixIcon: Icon(Icons.business, color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _accountNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Account Name (e.g. user@email.com)',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          prefixIcon: Icon(Icons.person, color: Colors.white70),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter an account name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _secretController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Secret Key',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          prefixIcon: Icon(Icons.key, color: Colors.white70),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the setup key';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: _saveAccount,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('ADD ACCOUNT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_isDecoding)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

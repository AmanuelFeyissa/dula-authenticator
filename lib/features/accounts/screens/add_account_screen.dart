import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/otp/otp_algorithm.dart';
import 'package:dula_auth/core/otp/otp_generator.dart';
import 'package:dula_auth/core/otp/otp_type.dart';
import 'package:dula_auth/core/otp/otp_uri.dart';
import 'package:dula_auth/core/widgets/responsive_layout.dart';
import 'package:dula_auth/core/branding/branded_logo.dart';
import 'package:dula_auth/core/theme/app_theme.dart';
import 'package:dula_auth/features/accounts/enrollment_capabilities.dart';
import 'package:dula_auth/features/home/providers/home_provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';
import 'package:pasteboard/pasteboard.dart';

class AddAccountScreen extends ConsumerStatefulWidget {
  /// When supplied, the screen edits this account instead of creating a new
  /// one: every field is pre-filled and saving calls `updateAccount` rather
  /// than `addAccount`. Reusing this form rather than a second one keeps a
  /// single place that has to track `OtpUri`'s parameter set — see
  /// docs/adr/0015-account-management.md §6.
  final OtpAccount? existing;

  const AddAccountScreen({super.key, this.existing});

  @override
  ConsumerState<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends ConsumerState<AddAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _issuerController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _secretController = TextEditingController();

  OtpType _type = OtpType.totp;
  OtpAlgorithm _algorithm = OtpAlgorithm.sha1;
  final _digitsController = TextEditingController(text: '6');
  final _periodController = TextEditingController(text: '30');
  final _counterController = TextEditingController(text: '0');
  bool _showAdvanced = false;

  bool _isScanning = false;
  bool _isDragging = false;
  bool _isDecoding = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) return;

    _issuerController.text = existing.issuer;
    _accountNameController.text = existing.accountName;
    _secretController.text = existing.secret;
    _type = existing.type;
    _algorithm = existing.algorithm;
    _digitsController.text = '${existing.digits}';
    _periodController.text = '${existing.period}';
    _counterController.text = '${existing.counter}';
    _showAdvanced = existing.digits != 6 ||
        existing.period != 30 ||
        existing.algorithm != OtpAlgorithm.sha1 ||
        existing.type != OtpType.totp;
  }

  @override
  void dispose() {
    _issuerController.dispose();
    _accountNameController.dispose();
    _secretController.dispose();
    _digitsController.dispose();
    _periodController.dispose();
    _counterController.dispose();
    super.dispose();
  }

  void _processFoundUrl(String code) {
    // All otpauth parsing goes through OtpUri so that digits, period,
    // algorithm, type and counter are actually honoured. The previous inline
    // parser read those values and then discarded them, which silently
    // produced wrong codes for any non-default credential.
    final parsed = OtpUri.parse(code, id: _newId());
    if (parsed != null) {
      setState(() {
        _issuerController.text = parsed.issuer;
        _accountNameController.text = parsed.accountName;
        _secretController.text = parsed.secret;
        _type = parsed.type;
        _algorithm = parsed.algorithm;
        _digitsController.text = '${parsed.digits}';
        _periodController.text = '${parsed.period}';
        _counterController.text = '${parsed.counter}';
        _showAdvanced = parsed.digits != 6 ||
            parsed.period != 30 ||
            parsed.algorithm != OtpAlgorithm.sha1 ||
            parsed.type != OtpType.totp;
      });
      _notify('Scanned ${parsed.type.label} credential'
          '${parsed.issuer.isNotEmpty ? ' for ${parsed.issuer}' : ''}');
      return;
    }

    // Not a URI — accept a bare base32 secret, which is what many services
    // print alongside the QR code for manual entry.
    final bare = code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    try {
      OtpGenerator.decodeSecret(bare);
      setState(() => _secretController.text = bare);
      _notify('Found a setup key');
    } on FormatException {
      _notify('That code is not a recognised authenticator credential');
    }
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
    if (!_formKey.currentState!.validate()) return;

    final secret =
        _secretController.text.trim().replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

    // Reject an unusable secret here rather than storing an account that can
    // never generate a code.
    try {
      OtpGenerator.decodeSecret(secret);
    } on FormatException {
      _notify('That setup key is not valid base32');
      return;
    }

    final existing = widget.existing;
    final account = OtpAccount(
      id: existing?.id ?? _newId(),
      issuer: _issuerController.text.trim(),
      accountName: _accountNameController.text.trim(),
      secret: secret,
      type: _type,
      digits: _type == OtpType.steam
          ? 5
          : int.tryParse(_digitsController.text) ?? 6,
      period: int.tryParse(_periodController.text) ?? 30,
      algorithm: _algorithm,
      counter: int.tryParse(_counterController.text) ?? 0,
      // Metadata not shown on this form must survive an edit untouched.
      tags: existing?.tags ?? const [],
      isFavorite: existing?.isFavorite ?? false,
    );

    final notifier = ref.read(accountListProvider.notifier);
    final success = _isEditing
        ? await notifier.updateAccount(account)
        : await notifier.addAccount(account);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      _notify(_isEditing ? 'Failed to save changes' : 'Failed to save account');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isScanning) {
      return Scaffold(
        appBar: AppBar(
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

    final body = ResponsiveLayout(
      maxWidth: 700,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // There is nothing to scan when editing text fields — only
              // shown for a new enrollment.
              if (!_isEditing) ...[
                Row(
                  children: [
                    if (EnrollmentCapabilities.cameraScanning)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => _isScanning = true),
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan QR Code with Camera'),
                        ),
                      ),
                    if (EnrollmentCapabilities.cameraScanning &&
                        EnrollmentCapabilities.clipboardImagePaste)
                      const SizedBox(width: 16),
                    if (EnrollmentCapabilities.clipboardImagePaste)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pasteImage,
                          icon: const Icon(Icons.paste),
                          label: const Text('Paste Image'),
                        ),
                      ),
                  ],
                ),
                if (EnrollmentCapabilities.dragAndDropImport) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _isDragging ? Colors.tealAccent.withValues(alpha: 0.2) : Colors.white10,
                      borderRadius: BorderRadius.circular(AppRadius.card),
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
              ],
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
                      const SizedBox(height: 8),
                      // Advanced parameters. A no-camera user must be able to
                      // enroll a non-default credential by hand, otherwise the
                      // manual path would only support 6/30/SHA-1 (ADR-0006).
                      Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          initiallyExpanded: _showAdvanced,
                          onExpansionChanged: (v) =>
                              setState(() => _showAdvanced = v),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          iconColor: Colors.tealAccent,
                          collapsedIconColor: Colors.white54,
                          title: const Text(
                            'Advanced options',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          subtitle: Text(
                            '${_type.label} - ${_algorithm.label}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                          children: [
                            DropdownButtonFormField<OtpType>(
                              initialValue: _type,
                              dropdownColor:
                                  Theme.of(context).colorScheme.surfaceContainerHigh,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Code type',
                                labelStyle: TextStyle(color: Colors.white70),
                                border: OutlineInputBorder(),
                                enabledBorder: OutlineInputBorder(
                                    borderSide:
                                        BorderSide(color: Colors.white24)),
                              ),
                              items: OtpType.values
                                  .map((t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(t.label),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _type = v;
                                  if (v == OtpType.steam) {
                                    _digitsController.text = '5';
                                    _algorithm = OtpAlgorithm.sha1;
                                  } else if (_digitsController.text == '5') {
                                    _digitsController.text = '6';
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<OtpAlgorithm>(
                              initialValue: _algorithm,
                              dropdownColor:
                                  Theme.of(context).colorScheme.surfaceContainerHigh,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Algorithm',
                                labelStyle: TextStyle(color: Colors.white70),
                                border: OutlineInputBorder(),
                                enabledBorder: OutlineInputBorder(
                                    borderSide:
                                        BorderSide(color: Colors.white24)),
                              ),
                              items: OtpAlgorithm.values
                                  .map((a) => DropdownMenuItem(
                                        value: a,
                                        child: Text(a.label),
                                      ))
                                  .toList(),
                              onChanged: _type == OtpType.steam
                                  ? null
                                  : (v) => setState(() =>
                                      _algorithm = v ?? OtpAlgorithm.sha1),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _digitsController,
                                    enabled: _type != OtpType.steam,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: const InputDecoration(
                                      labelText: 'Digits',
                                      labelStyle:
                                          TextStyle(color: Colors.white70),
                                      border: OutlineInputBorder(),
                                      enabledBorder: OutlineInputBorder(
                                          borderSide:
                                              BorderSide(color: Colors.white24)),
                                    ),
                                    validator: (v) {
                                      if (_type == OtpType.steam) return null;
                                      final n = int.tryParse(v ?? '');
                                      if (n == null ||
                                          n < OtpUri.minDigits ||
                                          n > OtpUri.maxDigits) {
                                        return 'Must be 6-10';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _type == OtpType.hotp
                                      ? TextFormField(
                                          controller: _counterController,
                                          keyboardType: TextInputType.number,
                                          style: const TextStyle(
                                              color: Colors.white),
                                          decoration: const InputDecoration(
                                            labelText: 'Counter',
                                            labelStyle: TextStyle(
                                                color: Colors.white70),
                                            border: OutlineInputBorder(),
                                            enabledBorder: OutlineInputBorder(
                                                borderSide: BorderSide(
                                                    color: Colors.white24)),
                                          ),
                                          validator: (v) =>
                                              int.tryParse(v ?? '') == null
                                                  ? 'Must be a number'
                                                  : null,
                                        )
                                      : TextFormField(
                                          controller: _periodController,
                                          keyboardType: TextInputType.number,
                                          style: const TextStyle(
                                              color: Colors.white),
                                          decoration: const InputDecoration(
                                            labelText: 'Period (seconds)',
                                            labelStyle: TextStyle(
                                                color: Colors.white70),
                                            border: OutlineInputBorder(),
                                            enabledBorder: OutlineInputBorder(
                                                borderSide: BorderSide(
                                                    color: Colors.white24)),
                                          ),
                                          validator: (v) {
                                            final n = int.tryParse(v ?? '');
                                            if (n == null || n < 1 || n > 300) {
                                              return 'Must be 1-300';
                                            }
                                            return null;
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saveAccount,
                child: Text(_isEditing ? 'SAVE CHANGES' : 'ADD ACCOUNT'),
              ),
            ],
          ),
        ),
      ),
    );

    final scaffold = Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(8.0),
          child: BrandedLogo(),
        ),
        title: Text(
          _isEditing ? 'Edit Account' : 'Add Account',
          style: const TextStyle(color: Colors.white),
        ),
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
          body,
          if (_isDecoding)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );

    // Drag-and-drop QR import only applies to a new enrollment, and only
    // where the platform actually has a drop-target interaction to offer.
    if (_isEditing || !EnrollmentCapabilities.dragAndDropImport) return scaffold;

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
      child: scaffold,
    );
  }
}

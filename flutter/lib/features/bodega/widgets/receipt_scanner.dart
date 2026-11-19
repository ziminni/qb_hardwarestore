import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Opens the camera and returns the first QR / barcode text it reads, or null.
typedef ReceiptScanner = Future<String?> Function(BuildContext context);

/// True where the scanner package can open a camera: the checker's Android
/// phone (decision 25), iPhone, the Mac app (its webcam) and the web build.
/// Windows and Linux have no camera support in the package, so there the
/// checker types the OR number or uses a USB scanner that types it.
bool get cameraScanAvailable =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// The default [ReceiptScanner]: a full-screen camera view.
Future<String?> scanReceiptWithCamera(BuildContext context) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _ReceiptScannerScreen(),
      ),
    );

class _ReceiptScannerScreen extends StatefulWidget {
  const _ReceiptScannerScreen();

  @override
  State<_ReceiptScannerScreen> createState() => _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends State<_ReceiptScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128],
  );
  bool _done = false;

  /// The typed fallback for a QR code that is torn, wet or faded (owner
  /// 2026-11-19): the arrow at the bottom opens it.
  bool _typing = false;
  final _orNumber = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _orNumber.dispose();
    super.dispose();
  }

  /// A typed OR number answers exactly like a scanned one.
  void _submitTyped() {
    final value = _orNumber.text.trim();
    if (value.isEmpty || _done) return;
    _done = true;
    Navigator.of(context).pop(value);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      _done = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan the receipt QR'),
        actions: [
          IconButton(
            tooltip: 'Flashlight',
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'The camera could not start (${error.errorCode.name}). '
                  'Allow camera access for this app, or go back and type the '
                  'OR number.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _typing ? _typedEntry() : _typeArrow(),
            ),
          ),
        ],
      ),
    );
  }

  /// The hint and the arrow that opens the typed entry.
  Widget _typeArrow() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Point the camera at the QR code on the receipt',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 12),
        InkWell(
          key: const ValueKey('scanner-type-arrow'),
          borderRadius: BorderRadius.circular(24),
          onTap: () => setState(() => _typing = true),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 34),
                Text(
                  'QR damaged? Type the OR number',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// The typed entry, sliding up over the camera; the arrow folds it away.
  Widget _typedEntry() => Container(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IconButton(
          tooltip: 'Back to scanning',
          onPressed: () => setState(() => _typing = false),
          icon: const Icon(Icons.keyboard_arrow_down, size: 30),
        ),
        TextField(
          key: const ValueKey('scanner-or-field'),
          controller: _orNumber,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _submitTyped(),
          decoration: const InputDecoration(
            labelText: 'OR number',
            hintText: 'OR-20261118-0001',
            prefixIcon: Icon(Icons.receipt_long_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('scanner-or-find'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _submitTyped,
          child: const Text('Find the receipt'),
        ),
      ],
    ),
  );
}

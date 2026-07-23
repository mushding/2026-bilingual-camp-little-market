import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// QR code 備援掃描（NFC 手機不足時）。卡片貼紙的 QR 內容＝該卡 UID（跟 NFC 讀到的字串一致）。
/// 掃到第一個結果就回傳並關閉頁面；使用者可按 X 取消回傳 null。
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('掃 QR Code（卡片貼紙）')),
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        const Center(
          child: Icon(Icons.qr_code_scanner, size: 96, color: Colors.white24),
        ),
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Text('把卡片上的 QR 貼紙對準框內',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, shadows: [
                Shadow(blurRadius: 8, color: Colors.black.withValues(alpha: 0.8)),
              ])),
        ),
      ]),
    );
  }
}

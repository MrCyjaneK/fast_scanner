import 'dart:typed_data';

import 'package:fast_scanner/src/objects/barcode_capture.dart';
import 'package:fast_scanner/src/scanqrc/gray_frame.dart';

/// SCANQRC host used when `dart:ffi` is unavailable (web).
class ScanqrcEngine {
  /// Probe and start backends. No-op on unsupported platforms.
  Future<void> start() async {}

  /// Submit a live camera frame. Skipped when no backend is loaded.
  void submit(
    GrayFrame frame, {
    required void Function(BarcodeCapture capture) onHit,
    void Function({required bool detected})? onAttempt,
    Uint8List? image,
  }) {}

  /// Decode QR codes in an image file.
  Future<BarcodeCapture?> analyzeImage(String path) async => null;

  /// Shut down worker isolates.
  Future<void> shutdown() async {}
}

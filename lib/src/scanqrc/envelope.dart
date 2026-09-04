import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fast_scanner/src/enums/barcode_format.dart';
import 'package:fast_scanner/src/objects/barcode.dart';
import 'package:fast_scanner/src/objects/barcode_capture.dart';

/// Parsed SCANQRC JSON envelope (`ok`, `error`, `messages`, `failures`).
class ScanqrcEnvelope {
  /// Create an envelope.
  const ScanqrcEnvelope({
    required this.ok,
    required this.messages,
    required this.failures,
    this.error,
  });

  /// Parse the malloc'd JSON string from `_qr_detect`.
  factory ScanqrcEnvelope.parse(String json) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map) {
      return const ScanqrcEnvelope(
        ok: false,
        error: 'envelope is not an object',
        messages: <String>[],
        failures: <String>[],
      );
    }

    final Map<Object?, Object?> map = Map<Object?, Object?>.from(decoded);

    final Object? messagesRaw = map['messages'];
    final Object? failuresRaw = map['failures'];

    return ScanqrcEnvelope(
      ok: map['ok'] == true,
      error: map['error'] as String?,
      messages: messagesRaw is List
          ? messagesRaw.whereType<String>().toList()
          : const <String>[],
      failures: failuresRaw is List
          ? failuresRaw.whereType<String>().toList()
          : const <String>[],
    );
  }

  /// Whether detect completed without a fatal error.
  final bool ok;

  /// Fatal error message, if any.
  final String? error;

  /// Decoded QR payloads.
  final List<String> messages;

  /// Non-fatal decoder failures.
  final List<String> failures;

  /// Convert payloads to a [BarcodeCapture].
  BarcodeCapture toCapture({Size size = Size.zero, Uint8List? image}) {
    return BarcodeCapture(
      barcodes: messages
          .map(
            (String text) => Barcode(
              rawValue: text,
              displayValue: text,
              format: BarcodeFormat.qrCode,
            ),
          )
          .toList(),
      image: image,
      size: size,
    );
  }
}

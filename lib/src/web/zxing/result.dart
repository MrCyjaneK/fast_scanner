import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fast_scanner/src/enums/barcode_format.dart';
import 'package:fast_scanner/src/objects/barcode.dart';
import 'package:fast_scanner/src/web/zxing/result_point.dart';

/// The JS static interop class for the Result class in the ZXing library.
///
/// See also: https://github.com/zxing-js/library/blob/master/src/core/Result.ts
@JS()
extension type Result(JSObject _) implements JSObject {
  @JS('barcodeFormat')
  external int? get _barcodeFormat;

  /// Get the text of the result.
  external String? get text;

  @JS('rawBytes')
  external JSUint8Array? get _rawBytes;

  @JS('resultPoints')
  external JSArray<ResultPoint>? get _resultPoints;

  /// Get the timestamp of the result.
  external int? get timestamp;

  /// Get the barcode format of the result.
  BarcodeFormat get barcodeFormat {
    return switch (_barcodeFormat) {
      11 => BarcodeFormat.qrCode,
      _ => BarcodeFormat.unknown,
    };
  }

  /// Get the raw bytes of the result.
  Uint8List? get rawBytes => _rawBytes?.toDart;

  /// Get the corner points of the result.
  List<Offset> get resultPoints {
    final JSArray<ResultPoint>? points = _resultPoints;

    if (points == null) {
      return const [];
    }

    return points.toDart.map((point) {
      return Offset(point.x, point.y);
    }).toList();
  }

  /// Convert this result to a [Barcode].
  Barcode get toBarcode {
    return Barcode(
      format: barcodeFormat,
      displayValue: text,
      rawValue: text,
    );
  }
}

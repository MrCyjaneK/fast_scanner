import 'package:fast_scanner/src/enums/barcode_format.dart';

/// A recognized QR code.
class Barcode {
  /// Creates a new [Barcode] instance.
  const Barcode({
    this.displayValue,
    this.format = BarcodeFormat.unknown,
    this.rawValue,
  });

  /// The barcode value in a user-friendly format.
  ///
  /// For QR codes this is the same as [rawValue].
  final String? displayValue;

  /// The format of the barcode.
  final BarcodeFormat format;

  /// The raw UTF-8 value encoded in the barcode.
  final String? rawValue;
}

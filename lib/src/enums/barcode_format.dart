/// This enum defines the barcode formats the scanner can report.
enum BarcodeFormat {
  /// A barcode format that represents all unknown formats.
  unknown(-1),

  /// A barcode format that represents all known formats.
  all(0),

  /// Barcode format constant for QR Codes.
  qrCode(256);

  const BarcodeFormat(this.rawValue);

  factory BarcodeFormat.fromRawValue(int value) {
    switch (value) {
      case -1:
        return BarcodeFormat.unknown;
      case 0:
        return BarcodeFormat.all;
      case 256:
        return BarcodeFormat.qrCode;
      default:
        throw ArgumentError.value(value, 'value', 'Invalid raw value.');
    }
  }

  /// The raw value of the barcode format.
  final int rawValue;
}

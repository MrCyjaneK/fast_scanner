import 'package:fast_scanner/src/enums/barcode_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('$BarcodeFormat tests', () {
    test('can be created from raw value', () {
      const values = <int, BarcodeFormat>{
        -1: BarcodeFormat.unknown,
        0: BarcodeFormat.all,
        256: BarcodeFormat.qrCode,
      };

      for (final MapEntry<int, BarcodeFormat> entry in values.entries) {
        final BarcodeFormat result = BarcodeFormat.fromRawValue(entry.key);

        expect(result, entry.value);
      }
    });

    test('invalid raw value throws argument error', () {
      const int negative = -2;
      const int outOfRange = 1;

      expect(() => BarcodeFormat.fromRawValue(negative), throwsArgumentError);
      expect(() => BarcodeFormat.fromRawValue(outOfRange), throwsArgumentError);
    });

    test('can be converted to raw value', () {
      const values = <BarcodeFormat, int>{
        BarcodeFormat.unknown: -1,
        BarcodeFormat.all: 0,
        BarcodeFormat.qrCode: 256,
      };

      for (final MapEntry<BarcodeFormat, int> entry in values.entries) {
        final int result = entry.key.rawValue;

        expect(result, entry.value);
      }
    });
  });
}

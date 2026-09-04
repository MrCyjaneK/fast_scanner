import 'dart:typed_data';

/// An 8-bit grayscale image in row-major order.
class GrayFrame {
  /// Create a grayscale frame.
  const GrayFrame({
    required this.pixels,
    required this.width,
    required this.height,
    required this.stride,
  });

  /// Row-major luma samples. Length must be at least `height * stride`.
  final Uint8List pixels;

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// Bytes per row, which may be larger than [width].
  final int stride;
}

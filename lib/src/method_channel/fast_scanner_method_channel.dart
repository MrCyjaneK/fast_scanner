import 'dart:async';

import 'package:fast_scanner/src/enums/fast_scanner_authorization_state.dart';
import 'package:fast_scanner/src/enums/fast_scanner_error_code.dart';
import 'package:fast_scanner/src/enums/torch_state.dart';
import 'package:fast_scanner/src/fast_scanner_exception.dart';
import 'package:fast_scanner/src/fast_scanner_platform_interface.dart';
import 'package:fast_scanner/src/fast_scanner_view_attributes.dart';
import 'package:fast_scanner/src/objects/barcode_capture.dart';
import 'package:fast_scanner/src/objects/start_options.dart';
import 'package:fast_scanner/src/scanqrc/scanqrc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// An implementation of [MobileScannerPlatform] that uses method channels.
class MethodChannelMobileScanner extends MobileScannerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel(
    'dev.steenbakker.fast_scanner/scanner/method',
  );

  /// The event channel that sends camera frames and device state.
  @visibleForTesting
  final eventChannel = const EventChannel(
    'dev.steenbakker.fast_scanner/scanner/event',
  );

  Stream<Map<Object?, Object?>>? _eventsStream;

  Stream<Map<Object?, Object?>> get eventsStream {
    _eventsStream ??=
        eventChannel.receiveBroadcastStream().cast<Map<Object?, Object?>>();

    return _eventsStream!;
  }

  int? _textureId;
  bool _returnImage = false;
  StreamSubscription<Map<Object?, Object?>>? _frameSubscription;

  final ScanqrcEngine _scanqrc = ScanqrcEngine();
  final StreamController<BarcodeCapture?> _barcodesController =
      StreamController<BarcodeCapture?>.broadcast();
  final StreamController<bool> _scanAttemptsController =
      StreamController<bool>.broadcast();

  /// Request permission to access the camera.
  ///
  /// Throws a [MobileScannerException] if the permission is not granted.
  Future<void> _requestCameraPermission() async {
    try {
      final MobileScannerAuthorizationState authorizationState =
          MobileScannerAuthorizationState.fromRawValue(
        await methodChannel.invokeMethod<int>('state') ?? 0,
      );

      switch (authorizationState) {
        // Authorization was already granted, no need to request it again.
        case MobileScannerAuthorizationState.authorized:
          return;
        // Android does not have an undetermined authorization state.
        // So if the permission was denied, request it again.
        case MobileScannerAuthorizationState.denied:
        case MobileScannerAuthorizationState.undetermined:
          final bool permissionGranted =
              await methodChannel.invokeMethod<bool>('request') ?? false;

          if (!permissionGranted) {
            throw const MobileScannerException(
              errorCode: MobileScannerErrorCode.permissionDenied,
            );
          }
      }
    } on PlatformException catch (error) {
      // If the permission state is invalid, that is an error.
      throw MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
        errorDetails: MobileScannerErrorDetails(
          code: error.code,
          details: error.details as Object?,
          message: error.message,
        ),
      );
    }
  }

  void _ensureFrameListener() {
    _frameSubscription ??= eventsStream.listen(_onEvent);
  }

  void _onEvent(Map<Object?, Object?> event) {
    if (event['name'] != 'frame') {
      return;
    }

    final Object? gray = event['gray'];
    if (gray is! Uint8List) {
      return;
    }

    final int? width = (event['width'] as num?)?.toInt();
    final int? height = (event['height'] as num?)?.toInt();
    final int? stride = (event['stride'] as num?)?.toInt();
    if (width == null || height == null || stride == null) {
      return;
    }
    if (width <= 0 || height <= 0 || stride < width) {
      return;
    }

    _scanqrc.submit(
      GrayFrame(
        pixels: gray,
        width: width,
        height: height,
        stride: stride,
      ),
      image: _returnImage ? gray : null,
      onHit: (BarcodeCapture capture) {
        if (!_barcodesController.isClosed) {
          _barcodesController.add(capture);
        }
      },
      onAttempt: ({required bool detected}) {
        if (!_scanAttemptsController.isClosed) {
          _scanAttemptsController.add(detected);
        }
      },
    );
  }

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodesController.stream;

  @override
  Stream<bool> get scanAttemptsStream => _scanAttemptsController.stream;

  @override
  Stream<TorchState> get torchStateStream {
    return eventsStream
        .where((event) => event['name'] == 'torchState')
        .map((event) => TorchState.fromRawValue(event['data'] as int? ?? 0));
  }

  @override
  Stream<double> get zoomScaleStateStream {
    return eventsStream
        .where((event) => event['name'] == 'zoomScaleState')
        .map((event) => event['data'] as double? ?? 0.0);
  }

  @override
  Future<BarcodeCapture?> analyzeImage(String path) {
    return _scanqrc.analyzeImage(path);
  }

  @override
  Widget buildCameraView() {
    if (_textureId == null) {
      return const SizedBox();
    }

    return Texture(textureId: _textureId!);
  }

  @override
  Future<void> resetZoomScale() async {
    await methodChannel.invokeMethod<void>('resetScale');
  }

  @override
  Future<void> setZoomScale(double zoomScale) async {
    await methodChannel.invokeMethod<void>('setScale', zoomScale);
  }

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    if (_textureId != null) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerAlreadyInitialized,
        errorDetails: MobileScannerErrorDetails(
          message:
              'The scanner was already started. Call stop() before calling start() again.',
        ),
      );
    }

    await _requestCameraPermission();
    _returnImage = startOptions.returnImage;
    await _scanqrc.start();
    _ensureFrameListener();

    Map<String, Object?>? startResult;

    try {
      startResult = await methodChannel.invokeMapMethod<String, Object?>(
        'start',
        startOptions.toMap(),
      );
    } on PlatformException catch (error) {
      throw MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
        errorDetails: MobileScannerErrorDetails(
          code: error.code,
          details: error.details as Object?,
          message: error.message,
        ),
      );
    }

    if (startResult == null) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
        errorDetails: MobileScannerErrorDetails(
          message: 'The start method did not return a view configuration.',
        ),
      );
    }

    final int? textureId = startResult['textureId'] as int?;

    if (textureId == null) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
        errorDetails: MobileScannerErrorDetails(
          message: 'The start method did not return a texture id.',
        ),
      );
    }

    _textureId = textureId;

    final int? numberOfCameras = startResult['numberOfCameras'] as int?;
    final TorchState currentTorchState = TorchState.fromRawValue(
      startResult['currentTorchState'] as int? ?? -1,
    );

    final Map<Object?, Object?>? sizeInfo =
        startResult['size'] as Map<Object?, Object?>?;
    final double? width = sizeInfo?['width'] as double?;
    final double? height = sizeInfo?['height'] as double?;

    final Size size;

    if (width == null || height == null) {
      size = Size.zero;
    } else {
      size = Size(width, height);
    }

    return MobileScannerViewAttributes(
      currentTorchMode: currentTorchState,
      numberOfCameras: numberOfCameras,
      size: size,
    );
  }

  @override
  Future<void> stop() async {
    if (_textureId == null) {
      return;
    }

    _textureId = null;

    await methodChannel.invokeMethod<void>('stop');
  }

  @override
  Future<void> toggleTorch() async {
    await methodChannel.invokeMethod<void>('toggleTorch');
  }

  @override
  Future<void> updateScanWindow(Rect? window) async {
    if (_textureId == null) {
      return;
    }

    List<double>? points;

    if (window != null) {
      points = [window.left, window.top, window.right, window.bottom];
    }

    await methodChannel.invokeMethod<void>(
      'updateScanWindow',
      {'rect': points},
    );
  }

  @override
  Future<void> dispose() async {
    await _frameSubscription?.cancel();
    _frameSubscription = null;
    await _scanqrc.shutdown();
    await stop();
  }
}

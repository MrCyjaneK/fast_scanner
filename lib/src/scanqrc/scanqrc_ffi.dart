import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:fast_scanner/src/objects/barcode_capture.dart';
import 'package:fast_scanner/src/scanqrc/envelope.dart';
import 'package:fast_scanner/src/scanqrc/gray_frame.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _InitDart = int Function();
typedef _DetectDart = Pointer<Utf8> Function(
  Pointer<Uint8>,
  int,
  int,
  int,
);
typedef _FreeDart = void Function(Pointer<Utf8>);
typedef _ShutdownDart = void Function();

class _KnownBackend {
  const _KnownBackend({required this.name, required this.prefix});

  final String name;
  final String prefix;
}

const List<_KnownBackend> _knownBackends = <_KnownBackend>[
  _KnownBackend(name: 'simple', prefix: 'SCANQRC_simple'),
  _KnownBackend(name: 'boofcvc', prefix: 'SCANQRC_boofcvc'),
];

class _SpawnArgs {
  const _SpawnArgs({
    required this.libName,
    required this.prefix,
    required this.handshake,
    required this.replies,
    required this.backendIndex,
  });

  final String libName;
  final String prefix;
  final SendPort handshake;
  final SendPort replies;
  final int backendIndex;
}

class _DetectMsg {
  const _DetectMsg({
    required this.id,
    required this.pixels,
    required this.width,
    required this.height,
    required this.stride,
  });

  final int id;
  final Uint8List pixels;
  final int width;
  final int height;
  final int stride;
}

class _ShutdownMsg {
  const _ShutdownMsg();
}

class _DetectResult {
  const _DetectResult({
    required this.backendIndex,
    required this.id,
    required this.json,
  });

  final int backendIndex;
  final int id;
  final String? json;
}

class _BackendIsolate {
  _BackendIsolate({
    required this.name,
    required this.commands,
    required this.isolate,
  });

  final String name;
  final SendPort commands;
  final Isolate isolate;
  bool busy = false;
}

/// Loads SCANQRC plugins and runs `_qr_detect` on one isolate per backend.
class ScanqrcEngine {
  ScanqrcEngine();

  final List<_BackendIsolate> _backends = <_BackendIsolate>[];
  final Map<int, Completer<String?>> _pending = <int, Completer<String?>>{};
  ReceivePort? _replies;
  StreamSubscription<dynamic>? _replySub;
  bool _started = false;
  int _nextId = 0;

  /// Probe `libsimple` / `libboofcvc` and spawn a worker isolate for each hit.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    _replies = ReceivePort();
    _replySub = _replies!.listen(_onReply);

    for (var i = 0; i < _knownBackends.length; i++) {
      final _KnownBackend known = _knownBackends[i];
      final String? libName = _libFileName(known.name);
      if (libName == null) {
        continue;
      }

      try {
        DynamicLibrary.open(libName);
      } on Object {
        continue;
      }

      final ReceivePort handshake = ReceivePort();
      Isolate? isolate;
      try {
        isolate = await Isolate.spawn(
          _scanqrcIsolateMain,
          _SpawnArgs(
            libName: libName,
            prefix: known.prefix,
            handshake: handshake.sendPort,
            replies: _replies!.sendPort,
            backendIndex: _backends.length,
          ),
        );
        final Object? port = await handshake.first.timeout(
          const Duration(seconds: 5),
        );
        handshake.close();
        if (port is! SendPort) {
          isolate.kill(priority: Isolate.immediate);
          continue;
        }
        _backends.add(
          _BackendIsolate(
            name: known.name,
            commands: port,
            isolate: isolate,
          ),
        );
      } on Object {
        isolate?.kill(priority: Isolate.immediate);
        handshake.close();
      }
    }
  }

  /// Submit a live frame. Backends that are still detecting skip this frame.
  void submit(
    GrayFrame frame, {
    required void Function(BarcodeCapture capture) onHit,
    void Function({required bool detected})? onAttempt,
    Uint8List? image,
  }) {
    if (_backends.isEmpty) {
      return;
    }

    final Size size = Size(
      frame.width.toDouble(),
      frame.height.toDouble(),
    );

    for (final _BackendIsolate backend in _backends) {
      if (backend.busy) {
        continue;
      }
      backend.busy = true;
      final int id = _nextId++;
      _pending[id] = Completer<String?>()
        ..future.then((String? json) {
          var detected = false;
          try {
            if (json == null) {
              return;
            }
            final ScanqrcEnvelope envelope = ScanqrcEnvelope.parse(json);
            if (!envelope.ok || envelope.messages.isEmpty) {
              return;
            }
            detected = true;
            onHit(envelope.toCapture(size: size, image: image));
          } on Object {
            return;
          } finally {
            onAttempt?.call(detected: detected);
          }
        });
      backend.commands.send(
        _DetectMsg(
          id: id,
          pixels: frame.pixels,
          width: frame.width,
          height: frame.height,
          stride: frame.stride,
        ),
      );
    }
  }

  /// Decode an image file on disk through every loaded backend.
  Future<BarcodeCapture?> analyzeImage(String path) async {
    await start();
    final GrayFrame? frame = await _decodeFileToGray(path);
    if (frame == null) {
      return null;
    }

    if (_backends.isEmpty) {
      return const BarcodeCapture();
    }

    final List<BarcodeCapture> captures = await Future.wait(
      _backends.map((backend) => _detectStill(backend, frame)),
    );

    final barcodes = [
      for (final BarcodeCapture capture in captures) ...capture.barcodes,
    ];

    return BarcodeCapture(
      barcodes: barcodes,
      size: Size(frame.width.toDouble(), frame.height.toDouble()),
    );
  }

  Future<BarcodeCapture> _detectStill(
    _BackendIsolate backend,
    GrayFrame frame,
  ) async {
    if (backend.busy) {
      return const BarcodeCapture();
    }
    backend.busy = true;
    final int id = _nextId++;
    final Completer<String?> completer = Completer<String?>();
    _pending[id] = completer;
    backend.commands.send(
      _DetectMsg(
        id: id,
        pixels: frame.pixels,
        width: frame.width,
        height: frame.height,
        stride: frame.stride,
      ),
    );
    final String? json = await completer.future;
    if (json == null) {
      return const BarcodeCapture();
    }
    return ScanqrcEnvelope.parse(json).toCapture(
      size: Size(frame.width.toDouble(), frame.height.toDouble()),
    );
  }

  /// Stop worker isolates and unload plugins.
  Future<void> shutdown() async {
    for (final _BackendIsolate backend in _backends) {
      backend.commands.send(const _ShutdownMsg());
    }
    _backends.clear();
    for (final Completer<String?> pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.complete(null);
      }
    }
    _pending.clear();
    await _replySub?.cancel();
    _replySub = null;
    _replies?.close();
    _replies = null;
    _started = false;
  }

  void _onReply(Object? message) {
    if (message is! _DetectResult) {
      return;
    }
    if (message.backendIndex >= 0 && message.backendIndex < _backends.length) {
      _backends[message.backendIndex].busy = false;
    }
    final Completer<String?>? completer = _pending.remove(message.id);
    if (completer != null && !completer.isCompleted) {
      completer.complete(message.json);
    }
  }
}

String? _libFileName(String name) {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'lib$name.so';
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return 'lib$name.dylib';
    default:
      return null;
  }
}

Future<GrayFrame?> _decodeFileToGray(String path) async {
  try {
    final Uint8List bytes = await File(path).readAsBytes();
    final Codec codec = await instantiateImageCodec(bytes);
    final FrameInfo frame = await codec.getNextFrame();
    final Image image = frame.image;
    final ByteData? data = await image.toByteData();
    final int width = image.width;
    final int height = image.height;
    image.dispose();
    codec.dispose();
    if (data == null) {
      return null;
    }
    final Uint8List rgba = data.buffer.asUint8List();
    final Uint8List gray = Uint8List(width * height);
    for (var i = 0, p = 0; i < gray.length; i++, p += 4) {
      gray[i] = (77 * rgba[p] + 150 * rgba[p + 1] + 29 * rgba[p + 2]) >> 8;
    }
    return GrayFrame(
      pixels: gray,
      width: width,
      height: height,
      stride: width,
    );
  } on Object {
    return null;
  }
}

void _scanqrcIsolateMain(_SpawnArgs args) {
  late final _InitDart init;
  late final _DetectDart detect;
  late final _FreeDart free;
  late final _ShutdownDart shutdown;

  try {
    final DynamicLibrary lib = DynamicLibrary.open(args.libName);
    init =
        lib.lookupFunction<Int32 Function(), _InitDart>('${args.prefix}_init');
    detect = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Uint8>, Int32, Int32, Int32),
        _DetectDart>(
      '${args.prefix}_qr_detect',
    );
    free = lib.lookupFunction<Void Function(Pointer<Utf8>), _FreeDart>(
        '${args.prefix}_qr_free',);
    shutdown = lib.lookupFunction<Void Function(), _ShutdownDart>(
      '${args.prefix}_shutdown',
    );
  } on Object {
    args.handshake.send(null);
    return;
  }

  init();

  final ReceivePort commands = ReceivePort();
  args.handshake.send(commands.sendPort);

  commands.listen((Object? message) {
    if (message is _ShutdownMsg) {
      shutdown();
      commands.close();
      Isolate.exit();
    }
    if (message is! _DetectMsg) {
      return;
    }

    final int n = message.height * message.stride;
    final Pointer<Uint8> ptr = malloc<Uint8>(n);
    final Uint8List view = ptr.asTypedList(n);
    final int copyLen = message.pixels.length < n ? message.pixels.length : n;
    view.setRange(0, copyLen, message.pixels);
    if (copyLen < n) {
      view.fillRange(copyLen, n, 0);
    }

    String? json;
    try {
      final Pointer<Utf8> jsonPtr = detect(
        ptr,
        message.width,
        message.height,
        message.stride,
      );
      if (jsonPtr != nullptr) {
        json = jsonPtr.toDartString();
        free(jsonPtr);
      }
    } finally {
      malloc.free(ptr);
    }

    args.replies.send(
      _DetectResult(
        backendIndex: args.backendIndex,
        id: message.id,
        json: json,
      ),
    );
  });
}

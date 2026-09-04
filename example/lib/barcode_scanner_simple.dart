import 'dart:async';

import 'package:fast_scanner/fast_scanner.dart';
import 'package:flutter/material.dart';

class BarcodeScannerSimple extends StatefulWidget {
  const BarcodeScannerSimple({super.key});

  @override
  State<BarcodeScannerSimple> createState() => _BarcodeScannerSimpleState();
}

class _BarcodeScannerSimpleState extends State<BarcodeScannerSimple> {
  static const Duration _window = Duration(seconds: 10);

  final MobileScannerController _controller = MobileScannerController();

  Barcode? _barcode;
  final List<DateTime> _scanTimes = <DateTime>[];
  final List<_FrameSample> _frames = <_FrameSample>[];
  double _rate = 0;
  double _highRate = 0;
  int _frameCount = 0;
  int _failedCount = 0;
  double _successRate = 0;
  double _highSuccessRate = 0;
  Timer? _ticker;
  StreamSubscription<bool>? _attemptsSub;

  @override
  void initState() {
    super.initState();
    _attemptsSub = _controller.scanAttempts.listen(_handleAttempt);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _recomputeStats();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_attemptsSub?.cancel());
    _controller.dispose();
    super.dispose();
  }

  Widget _buildBarcode(Barcode? value) {
    if (value == null) {
      return const Text(
        'Scan something!',
        overflow: TextOverflow.fade,
        style: TextStyle(color: Colors.white),
      );
    }

    return Text(
      value.displayValue ?? 'No display value.',
      overflow: TextOverflow.fade,
      style: const TextStyle(color: Colors.white),
    );
  }

  void _handleBarcode(BarcodeCapture barcodes) {
    if (barcodes.barcodes.isEmpty) {
      return;
    }

    final DateTime now = DateTime.now();
    _scanTimes.addAll(
      List<DateTime>.filled(barcodes.barcodes.length, now),
    );

    if (mounted) {
      setState(() {
        _barcode = barcodes.barcodes.first;
      });
    }
    _recomputeStats();
  }

  void _handleAttempt(bool detected) {
    _frames.add(_FrameSample(time: DateTime.now(), hit: detected));
    _recomputeStats();
  }

  void _recomputeStats() {
    final DateTime cutoff = DateTime.now().subtract(_window);
    _scanTimes.removeWhere((DateTime time) => time.isBefore(cutoff));
    _frames.removeWhere((_FrameSample frame) => frame.time.isBefore(cutoff));

    final double rate = _scanTimes.length / _window.inSeconds;
    final int frameCount = _frames.length;
    final int failedCount =
        _frames.where((_FrameSample frame) => !frame.hit).length;
    final double successRate =
        frameCount == 0 ? 0 : (frameCount - failedCount) / frameCount * 100;
    final double highRate = rate > _highRate ? rate : _highRate;
    final double highSuccessRate =
        frameCount == 0 || successRate <= _highSuccessRate
            ? _highSuccessRate
            : successRate;

    if (!mounted) {
      return;
    }
    if (rate == _rate &&
        highRate == _highRate &&
        frameCount == _frameCount &&
        failedCount == _failedCount &&
        successRate == _successRate &&
        highSuccessRate == _highSuccessRate) {
      return;
    }

    setState(() {
      _rate = rate;
      _highRate = highRate;
      _frameCount = frameCount;
      _failedCount = failedCount;
      _successRate = successRate;
      _highSuccessRate = highSuccessRate;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Simple scanner')),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcode,
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.black.withValues(alpha: 0.4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_rate.toStringAsFixed(1)} QR/s   best ${_highRate.toStringAsFixed(1)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_frameCount frames · $_failedCount failed · '
                    '${_successRate.toStringAsFixed(1)}%   '
                    'best ${_highSuccessRate.toStringAsFixed(1)}%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              alignment: Alignment.bottomCenter,
              height: 100,
              color: Colors.black.withValues(alpha: 0.4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(child: Center(child: _buildBarcode(_barcode))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameSample {
  const _FrameSample({required this.time, required this.hit});

  final DateTime time;
  final bool hit;
}

package dev.steenbakker.fast_scanner

import dev.steenbakker.fast_scanner.objects.MobileScannerStartParameters

typealias FrameCallback = (pixels: ByteArray, width: Int, height: Int, stride: Int) -> Unit
typealias AnalyzerErrorCallback = (message: String) -> Unit
typealias AnalyzerSuccessCallback = (barcodes: List<Map<String, Any?>>?) -> Unit
typealias MobileScannerErrorCallback = (error: String) -> Unit
typealias TorchStateCallback = (state: Int) -> Unit
typealias ZoomScaleStateCallback = (zoomScale: Double) -> Unit
typealias MobileScannerStartedCallback = (parameters: MobileScannerStartParameters) -> Unit

package dev.steenbakker.fast_scanner

import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.zxing.Result
import io.flutter.Log

class UniversalQrCodeAnalyzer(
    private val onQrCodesDetected: (qrCode: Result) -> Unit
) : ImageAnalysis.Analyzer {
    val barcodeMap: MutableList<Map<String, Any?>> = mutableListOf()

    private val qrAnalyzerBoofcv = QrCodeAnalyzerBoofcv{ qrResult ->
        onQrCodesDetected(qrResult)
    }

    private val qrAnalyzerZxing = QrCodeAnalyzerZxing { qrResult ->
        onQrCodesDetected(qrResult)
    }

    override fun analyze(image: ImageProxy) {
        qrAnalyzerBoofcv.analyze(image);
        qrAnalyzerZxing.analyze(image);
        image.close();
    }

}
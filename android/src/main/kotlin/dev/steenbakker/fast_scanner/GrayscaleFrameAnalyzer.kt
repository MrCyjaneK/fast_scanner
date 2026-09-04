package dev.steenbakker.fast_scanner

import android.graphics.ImageFormat
import android.os.Handler
import androidx.annotation.OptIn
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min

/**
 * Copies the Y plane off the analysis executor. The camera preview is a
 * separate CameraX use case and keeps running even when this analyzer skips.
 *
 * If a previous frame is still being published to Dart, this frame is skipped.
 */
class GrayscaleFrameAnalyzer(
    private val mainHandler: Handler,
    private val onFrame: (pixels: ByteArray, width: Int, height: Int, stride: Int) -> Unit
) : ImageAnalysis.Analyzer {
    private val inflight = AtomicBoolean(false)

    @OptIn(ExperimentalGetImage::class)
    override fun analyze(imageProxy: ImageProxy) {
        if (!inflight.compareAndSet(false, true)) {
            imageProxy.close()
            return
        }

        var published = false
        try {
            val image = imageProxy.image
            if (image == null || imageProxy.format != ImageFormat.YUV_420_888) {
                inflight.set(false)
                return
            }

            val yPlane = image.planes[0]
            val width = imageProxy.width
            val height = imageProxy.height
            val rowStride = yPlane.rowStride
            val pixelStride = yPlane.pixelStride
            val yBuffer = yPlane.buffer
            yBuffer.rewind()

            val gray: ByteArray
            val stride: Int

            if (pixelStride == 1) {
                stride = rowStride
                val n = height * rowStride
                gray = ByteArray(n)
                val toCopy = min(n, yBuffer.remaining())
                yBuffer.get(gray, 0, toCopy)
            } else {
                stride = width
                gray = ByteArray(height * width)
                val row = ByteArray(rowStride)
                var dst = 0
                for (y in 0 until height) {
                    yBuffer.position(y * rowStride)
                    val rowBytes = min(rowStride, yBuffer.remaining())
                    if (rowBytes <= 0) {
                        break
                    }
                    yBuffer.get(row, 0, rowBytes)
                    var src = 0
                    for (x in 0 until width) {
                        if (src >= rowBytes) {
                            break
                        }
                        gray[dst++] = row[src]
                        src += pixelStride
                    }
                }
            }

            published = true
            mainHandler.post {
                try {
                    onFrame(gray, width, height, stride)
                } finally {
                    inflight.set(false)
                }
            }
        } catch (_: Exception) {
            if (!published) {
                inflight.set(false)
            }
        } finally {
            imageProxy.close()
        }
    }
}

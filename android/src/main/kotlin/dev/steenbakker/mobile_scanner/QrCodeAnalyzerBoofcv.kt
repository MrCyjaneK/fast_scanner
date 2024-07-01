package dev.steenbakker.mobile_scanner

import android.media.Image
import android.graphics.ImageFormat
import android.util.Log
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy

import com.google.zxing.*
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.multi.qrcode.QRCodeMultiReader

import boofcv.android.ConvertBitmap
import boofcv.factory.fiducial.FactoryFiducial
import boofcv.struct.image.GrayU8

import java.nio.ByteBuffer
import java.util.*


class QrCodeAnalyzerBoofcv(
    private val onQrCodesDetected: (qrCode: Result) -> Unit
) : ImageAnalysis.Analyzer {


    private fun ByteBuffer.toByteArray(): ByteArray {
        rewind()
        val data = ByteArray(remaining())
        get(data)
        return data
    }

    private val yuvFormats = mutableListOf(ImageFormat.YUV_420_888)

    init {
        yuvFormats.addAll(listOf(ImageFormat.YUV_422_888, ImageFormat.YUV_444_888, ImageFormat.JPEG))
    }


    private val detector = FactoryFiducial.qrcode(null,GrayU8::class.java)

    fun imageToGrayU8(image: Image?): GrayU8 {
        // Get the image's planes
        val planes = image?.planes

        // Retrieve the data from the Y plane (the first plane in YUV format)
        val yBuffer = planes?.get(0)?.buffer

        // Create a ByteArray to hold the Y plane data
        val yData = ByteArray(yBuffer?.remaining() ?: 0)

        // Copy the Y plane data from the buffer into the ByteArray
        yBuffer?.get(yData)

        // Get the image's width and height
        val width = image?.width ?: 0
        val height = image?.height ?: 0

        // Create a GrayU8 image with the Y plane data, width, and height
        val grayU8 = GrayU8(width, height)
        grayU8.data = yData
        grayU8.stride = planes?.get(0)?.rowStride ?: 0

        // Close the ImageProxy to release resources
        // imageProxy.close()

        return grayU8
    }
    private var debugI = 0

    fun invertGrayU8Image(inputImage: GrayU8): GrayU8 {
        val width = inputImage.width
        val height = inputImage.height

        // Create a new GrayU8 image to store the inverted result
        val invertedImage = GrayU8(width, height)

        // Invert the colors of the grayscale image
        for (y in 0 until height) {
            for (x in 0 until width) {
                // Get the pixel intensity value at (x, y)
                val intensity = inputImage.get(x, y)

                // Invert the intensity value by subtracting it from 255
                val invertedIntensity = 255 - intensity

                // Set the inverted intensity value at (x, y) in the output image
                invertedImage.set(x, y, invertedIntensity)
            }
        }

        return invertedImage
    }

    @androidx.annotation.OptIn(androidx.camera.core.ExperimentalGetImage::class)
    override fun analyze(imageProxy: ImageProxy) {
        if (debugI % 100 == 10) {
            Log.d("QrCodeAnalyzerBoofcv", "$debugI analyze(image: ImageProxy)")
        }
        debugI++;
        // We are using YUV format because, ImageProxy internally uses ImageReader to get the image
        // by default ImageReader uses YUV format unless changed.
        if (imageProxy.format !in yuvFormats) {
            Log.d("QrCodeAnalyzerBoofcv", "imageProxy.format is not yuvFormat")
            return
        }
        // val data = image.planes[0].buffer.toByteArray()

        /*
        val source = PlanarYUVLuminanceSource(
            data,
            image.width,
            image.height,
            0,
            0,
            image.width,
            image.height,
            false
        )
        */
        if (imageProxy.image == null) {
            return
        }
        val image: Image? = imageProxy.image
        val imgGrayU8: GrayU8 = imageToGrayU8(image)

        try {
            detector.process(imgGrayU8)
        } catch (e: NotFoundException) {
//            e.printStackTrace()
        } catch (e: ChecksumException) {
//            e.printStackTrace()
        } catch (e: Exception) {
//            e.printStackTrace()
        }
        for (det in detector.detections) {
            Log.d("QrCodeAnalyzerBoofcv", det.message)
            onQrCodesDetected(Result(det.message, det.rawbits, null, BarcodeFormat.QR_CODE))
        }

        val invImgGrayU8: GrayU8 = invertGrayU8Image(imgGrayU8)

        try {
            detector.process(invImgGrayU8)
            // result = reader.decode(binaryBitmap)
        } catch (e: NotFoundException) {
//            e.printStackTrace()
        } catch (e: ChecksumException) {
//            e.printStackTrace()
        } catch (e: Exception) {
//            e.printStackTrace()
        }


        for (det in detector.detections) {
            Log.d("QrCodeAnalyzerBoofcv.kt", det.message)
            onQrCodesDetected(Result(det.message, det.rawbits, null, BarcodeFormat.QR_CODE))
        }
        imageProxy.close()
    }
}
//
//  MobileScanner.swift
//  fast_scanner
//
//  Created by Julian Steenbakker on 15/02/2022.
//

import Foundation
import Flutter
import AVFoundation

typealias MobileScannerFrameCallback = ((Data, Int, Int, Int) -> ())
typealias TorchModeChangeCallback = ((Int?) -> ())
typealias ZoomScaleChangeCallback = ((Double?) -> ())

public class MobileScanner: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, FlutterTexture {
    /// Capture session of the camera
    var captureSession: AVCaptureSession?

    /// The selected camera
    var device: AVCaptureDevice!

    /// Return image buffer with the Barcode event
    var returnImage: Bool = false

    /// Default position of camera
    var videoPosition: AVCaptureDevice.Position = AVCaptureDevice.Position.back

    /// When results are found, this callback will be called
    let mobileScannerCallback: MobileScannerFrameCallback

    /// When torch mode is changes, this callback will be called
    let torchModeChangeCallback: TorchModeChangeCallback

    /// When zoom scale is changes, this callback will be called
    let zoomScaleChangeCallback: ZoomScaleChangeCallback

    /// If provided, the Flutter registry will be used to send the output of the CaptureOutput to a Flutter texture.
    private let registry: FlutterTextureRegistry?

    /// Image to be sent to the texture
    var latestBuffer: CVImageBuffer!

    /// Texture id of the camera preview for Flutter
    private var textureId: Int64!

    var detectionSpeed: DetectionSpeed = DetectionSpeed.noDuplicates

    private let cameraQueue = DispatchQueue(label: "dev.steenbakker.fast_scanner.camera")
    private let convertQueue = DispatchQueue(label: "dev.steenbakker.fast_scanner.convert")
    private let processingLock = NSLock()
    private var isProcessing = false

    var standardZoomFactor: CGFloat = 1

    private var nextScanTime = 0.0
    
    public var timeoutSeconds: Double = 0

    init(registry: FlutterTextureRegistry?, mobileScannerCallback: @escaping MobileScannerFrameCallback, torchModeChangeCallback: @escaping TorchModeChangeCallback, zoomScaleChangeCallback: @escaping ZoomScaleChangeCallback) {
        self.registry = registry
        self.mobileScannerCallback = mobileScannerCallback
        self.torchModeChangeCallback = torchModeChangeCallback
        self.zoomScaleChangeCallback = zoomScaleChangeCallback
        super.init()
    }

    /// Get the default camera device for the given `position`.
    ///
    /// This function selects the most appropriate camera, when it is available.
    private func getDefaultCameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if #available(iOS 13.0, *) {
            // Find the built-in Triple Camera, if it exists.
            if let device = AVCaptureDevice.default(.builtInTripleCamera,
                                                    for: .video,
                                                    position: position) {
                return device
            }
            
            // Find the built-in Dual-Wide Camera, if it exists.
            if let device = AVCaptureDevice.default(.builtInDualWideCamera,
                                                    for: .video,
                                                    position: position) {
                return device
            }
        }
        
        // Find the built-in Dual Camera, if it exists.
        if let device = AVCaptureDevice.default(.builtInDualCamera,
                                                for: .video,
                                                position: position) {
            return device
        }
        
        // Find the built-in Wide-Angle Camera, if it exists.
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                for: .video,
                                                position: position) {
            return device
        }
        
        return nil
    }
    
    /// Check if we already have camera permission.
    func checkPermission() -> Int {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            return 0
        case .authorized:
            return 1
        default:
            return 2
        }
    }

    /// Request permissions for video
    func requestPermission(_ result: @escaping FlutterResult) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: { result($0) })
    }
    
    /// Gets called when a new image is added to the buffer
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        latestBuffer = imageBuffer
        registry?.textureFrameAvailable(textureId)

        processingLock.lock()
        let skip = isProcessing
        if !skip {
            isProcessing = true
        }
        processingLock.unlock()

        if skip {
            return
        }

        convertQueue.async { [weak self, imageBuffer] in
            let gray = MobileScanner.copyGray(from: imageBuffer)
            DispatchQueue.main.async {
                defer {
                    self?.processingLock.lock()
                    self?.isProcessing = false
                    self?.processingLock.unlock()
                }
                guard let self = self, let gray = gray else {
                    return
                }
                self.mobileScannerCallback(gray.data, gray.width, gray.height, gray.stride)
            }
        }
    }

    private struct GrayCopy {
        let data: Data
        let width: Int
        let height: Int
        let stride: Int
    }

    private static func copyGray(from buffer: CVPixelBuffer) -> GrayCopy? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer), width > 0, height > 0 else {
            return nil
        }

        var gray = Data(count: width * height)
        gray.withUnsafeMutableBytes { dest in
            guard let dst = dest.bindMemory(to: UInt8.self).baseAddress else {
                return
            }
            let src = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                let row = src.advanced(by: y * bytesPerRow)
                let dstRow = dst.advanced(by: y * width)
                for x in 0..<width {
                    let i = x * 4
                    let b = Int(row[i])
                    let g = Int(row[i + 1])
                    let r = Int(row[i + 2])
                    dstRow[x] = UInt8((77 * r + 150 * g + 29 * b) >> 8)
                }
            }
        }
        return GrayCopy(data: gray, width: width, height: height, stride: width)
    }

    /// Start scanning for barcodes
    func start(returnImage: Bool, cameraPosition: AVCaptureDevice.Position, torch: Bool, detectionSpeed: DetectionSpeed, completion: @escaping (MobileScannerStartParameters) -> ()) throws {
        self.detectionSpeed = detectionSpeed
        if (device != nil || captureSession != nil) {
            throw MobileScannerError.alreadyStarted
        }

        barcodesString = nil
        captureSession = AVCaptureSession()
        textureId = registry?.register(self)

        // Open the camera device
        device = getDefaultCameraDevice(position: cameraPosition)

        if (device == nil) {
            throw MobileScannerError.noCamera
        }

        device.addObserver(self, forKeyPath: #keyPath(AVCaptureDevice.torchMode), options: .new, context: nil)
        device.addObserver(self, forKeyPath: #keyPath(AVCaptureDevice.videoZoomFactor), options: .new, context: nil)

        // Check the zoom factor at switching from ultra wide camera to wide camera.
        standardZoomFactor = 1
        if #available(iOS 13.0, *) {
            for (index, actualDevice) in device.constituentDevices.enumerated() {
                if (actualDevice.deviceType != .builtInUltraWideCamera) {
                    if index > 0 && index <= device.virtualDeviceSwitchOverVideoZoomFactors.count {
                        standardZoomFactor = CGFloat(truncating: device.virtualDeviceSwitchOverVideoZoomFactors[index - 1])
                    }
                    break
                }
            }
        }

        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if #available(iOS 15.4, *) , device.isFocusModeSupported(.autoFocus){
                device.automaticallyAdjustsFaceDrivenAutoFocusEnabled = false
            }
            device.unlockForConfiguration()
        } catch {}

        captureSession!.beginConfiguration()

        // Add device input
        do {
            let input = try AVCaptureDeviceInput(device: device)
            captureSession!.addInput(input)
        } catch {
            throw MobileScannerError.cameraError(error)
        }

        captureSession!.sessionPreset = AVCaptureSession.Preset.photo
        // Add video output.
        let videoOutput = AVCaptureVideoDataOutput()

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true

        videoPosition = cameraPosition
        // calls captureOutput()
        videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)

        captureSession!.addOutput(videoOutput)
        for connection in videoOutput.connections {
            connection.videoOrientation = .portrait
            if cameraPosition == .front && connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        captureSession!.commitConfiguration()

        cameraQueue.async {
            guard let captureSession = self.captureSession else {
                return
            }

            captureSession.startRunning()

            // After the capture session started, turn on the torch (if requested)
            // and reset the zoom scale back to the default.
            // Ensure that these adjustments are done on the main DispatchQueue,
            // as they interact with the hardware camera.
            if (torch) {
                DispatchQueue.main.async {
                    self.turnTorchOn()
                }
            }
            
            DispatchQueue.main.async {
                do {
                    try self.resetScale()
                } catch {
                    // If the zoom scale could not be reset,
                    // continue with the capture session anyway.
                }
            }

            if let device = self.device {
                // When querying the dimensions of the camera,
                // stay on the background thread,
                // as this does not change the configuration of the hardware camera.
                let dimensions = CMVideoFormatDescriptionGetDimensions(
                    device.activeFormat.formatDescription)
                
                completion(
                    MobileScannerStartParameters(
                        width: Double(dimensions.height),
                        height: Double(dimensions.width),
                        currentTorchState: device.hasTorch ? device.torchMode.rawValue : -1,
                        textureId: self.textureId ?? 0
                    )
                )
                
                return
            }
            
            completion(MobileScannerStartParameters())
        }
    }

    /// Stop scanning for barcodes
    func stop() throws {
        if (device == nil || captureSession == nil) {
            throw MobileScannerError.alreadyStopped
        }
        
        captureSession!.stopRunning()
        for input in captureSession!.inputs {
            captureSession!.removeInput(input)
        }
        for output in captureSession!.outputs {
            captureSession!.removeOutput(output)
        }

        latestBuffer = nil
        device.removeObserver(self, forKeyPath: #keyPath(AVCaptureDevice.torchMode))
        device.removeObserver(self, forKeyPath: #keyPath(AVCaptureDevice.videoZoomFactor))
        registry?.unregisterTexture(textureId)
        textureId = nil
        captureSession = nil
        device = nil
    }

    /// Toggle the torch.
    ///
    /// This method should be called on the main DispatchQueue.
    func toggleTorch() {
        guard let device = self.device else {
            return
        }
        
        if (!device.hasTorch || !device.isTorchAvailable) {
            return
        }
        
        var newTorchMode: AVCaptureDevice.TorchMode = device.torchMode
        
        switch(device.torchMode) {
        case AVCaptureDevice.TorchMode.auto:
            newTorchMode = device.isTorchActive ? AVCaptureDevice.TorchMode.off : AVCaptureDevice.TorchMode.on
            break;
        case AVCaptureDevice.TorchMode.off:
            newTorchMode = AVCaptureDevice.TorchMode.on
            break;
        case AVCaptureDevice.TorchMode.on:
            newTorchMode = AVCaptureDevice.TorchMode.off
            break;
        default:
            return;
        }
        
        if (!device.isTorchModeSupported(newTorchMode) || device.torchMode == newTorchMode) {
            return;
        }

        do {
            try device.lockForConfiguration()
            device.torchMode = newTorchMode
            device.unlockForConfiguration()
        } catch(_) {}
    }
    
    /// Turn the torch on.
    private func turnTorchOn() {
        guard let device = self.device else {
            return
        }
        
        if (!device.hasTorch || !device.isTorchAvailable || !device.isTorchModeSupported(.on) || device.torchMode == .on) {
            return
        }
        
        do {
            try device.lockForConfiguration()
            device.torchMode = .on
            device.unlockForConfiguration()
        } catch(_) {}
    }

    // Observer for torch state
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        switch keyPath {
        case "torchMode":
            // Off = 0, On = 1, Auto = 2
            let state = change?[.newKey] as? Int
            torchModeChangeCallback(state)
        case "videoZoomFactor":
            let zoomFactor = change?[.newKey] as? CGFloat ?? 1
            let zoomScale = (zoomFactor - 1) / 4
            zoomScaleChangeCallback(Double(zoomScale))
        default:
            break
        }
    }
    
    /// Set the zoom factor of the camera
    func setScale(_ scale: CGFloat) throws {
        if (device == nil) {
            throw MobileScannerError.zoomWhenStopped
        }
        
        do {
            try device.lockForConfiguration()
            let maxZoomFactor = device.activeFormat.videoMaxZoomFactor
            
            var actualScale = (scale * 4) + 1
            
            // Set maximum zoomrate of 5x
            actualScale = min(5.0, actualScale)
            
            // Limit to max rate of camera
            actualScale = min(maxZoomFactor, actualScale)
            
            // Limit to 1.0 scale
            device.videoZoomFactor = actualScale
            device.unlockForConfiguration()
        } catch {
            throw MobileScannerError.zoomError(error)
        }
        
    }

    /// Reset the zoom factor of the camera
    func resetScale() throws {
        if (device == nil) {
            throw MobileScannerError.zoomWhenStopped
        }

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = standardZoomFactor
            device.unlockForConfiguration()
        } catch {
            throw MobileScannerError.zoomError(error)
        }
    }

    var barcodesString: Array<String?>?

    //    /// Convert image buffer to jpeg
    //    private func ciImageToJpeg(ciImage: CIImage) -> Data {
    //
    //        // let ciImage = CIImage(cvPixelBuffer: latestBuffer)
    //        let context:CIContext = CIContext.init(options: nil)
    //        let cgImage:CGImage = context.createCGImage(ciImage, from: ciImage.extent)!
    //        let uiImage:UIImage = UIImage(cgImage: cgImage, scale: 1, orientation: UIImage.Orientation.up)
    //
    //        return uiImage.jpegData(compressionQuality: 0.8)!
    //    }

    /// Rotates images accordingly
    func imageOrientation(
        deviceOrientation: UIDeviceOrientation,
        defaultOrientation: UIDeviceOrientation,
        position: AVCaptureDevice.Position
    ) -> UIImage.Orientation {
        switch deviceOrientation {
        case .portrait:
            return position == .front ? .leftMirrored : .right
        case .landscapeLeft:
            return position == .front ? .downMirrored : .up
        case .portraitUpsideDown:
            return position == .front ? .rightMirrored : .left
        case .landscapeRight:
            return position == .front ? .upMirrored : .down
        case .faceDown, .faceUp, .unknown:
            return .up
        @unknown default:
            return imageOrientation(deviceOrientation: defaultOrientation, defaultOrientation: .portrait, position: .back)
        }
    }

    /// Sends output of OutputBuffer to a Flutter texture
    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        if latestBuffer == nil {
            return nil
        }
        return Unmanaged<CVPixelBuffer>.passRetained(latestBuffer)
    }
    
    struct MobileScannerStartParameters {
        var width: Double = 0.0
        var height: Double = 0.0
        var currentTorchState: Int = -1
        var textureId: Int64 = 0
    }
}


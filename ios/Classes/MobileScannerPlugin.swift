import Flutter
import AVFoundation
import UIKit

public class MobileScannerPlugin: NSObject, FlutterPlugin {
    
    /// The mobile scanner object that handles all logic
    private let mobileScanner: MobileScanner
    
    /// The handler sends all information via an event channel back to Flutter
    private let barcodeHandler: BarcodeHandler

    /// The points for the scan window.
    static var scanWindow: [CGFloat]?
    
    init(barcodeHandler: BarcodeHandler, registry: FlutterTextureRegistry) {
        self.mobileScanner = MobileScanner(registry: registry, mobileScannerCallback: { barcodes, error, image in
            if barcodes != nil {
                let barcodesMap: [Any?] = barcodes!.compactMap { barcode in
                    return barcode
                }
                if (!barcodesMap.isEmpty) {
                    barcodeHandler.publishEvent(["name": "barcode", "data": barcodesMap, "image": FlutterStandardTypedData(bytes: image.jpegData(compressionQuality: 0.8)!), "width": image.size.width, "height": image.size.height])
                }
            } else if (error != nil){
                barcodeHandler.publishEvent(["name": "error", "data": error])
            }
        }, torchModeChangeCallback: { torchState in
            barcodeHandler.publishEvent(["name": "torchState", "data": torchState])
        }, zoomScaleChangeCallback: { zoomScale in
            barcodeHandler.publishEvent(["name": "zoomScaleState", "data": zoomScale])
        })
        self.barcodeHandler = barcodeHandler
        super.init()
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "dev.steenbakker.fast_scanner/scanner/method", binaryMessenger: registrar.messenger())
        let instance = MobileScannerPlugin(barcodeHandler: BarcodeHandler(registrar: registrar), registry: registrar.textures())
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "state":
            result(mobileScanner.checkPermission())
        case "request":
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { result($0) })
        case "start":
            start(call, result)
        case "stop":
            stop(result)
        case "toggleTorch":
            toggleTorch(result)
        case "setScale":
            setScale(call, result)
        case "resetScale":
            resetScale(call, result)
        case "updateScanWindow":
            updateScanWindow(call, result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Start the mobileScanner.
    private func start(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let torch: Bool = (call.arguments as! Dictionary<String, Any?>)["torch"] as? Bool ?? false
        let facing: Int = (call.arguments as! Dictionary<String, Any?>)["facing"] as? Int ?? 1
        let formats: Array<Int> = (call.arguments as! Dictionary<String, Any?>)["formats"] as? Array ?? []
        let returnImage: Bool = (call.arguments as! Dictionary<String, Any?>)["returnImage"] as? Bool ?? false
        let speed: Int = (call.arguments as! Dictionary<String, Any?>)["speed"] as? Int ?? 0
        let timeoutMs: Int = (call.arguments as! Dictionary<String, Any?>)["timeout"] as? Int ?? 0
        self.mobileScanner.timeoutSeconds = Double(timeoutMs) / Double(1000)

        let position = facing == 0 ? AVCaptureDevice.Position.front : .back
        let detectionSpeed: DetectionSpeed = DetectionSpeed(rawValue: speed)!

        do {
            try mobileScanner.start(returnImage: returnImage, cameraPosition: position, torch: torch, detectionSpeed: detectionSpeed) { parameters in
                DispatchQueue.main.async {
                    result([
                        "textureId": parameters.textureId,
                        "size": ["width": parameters.width, "height": parameters.height],
                        "currentTorchState": parameters.currentTorchState,
                    ])
                }
            }
        } catch MobileScannerError.alreadyStarted {
            result(FlutterError(code: "MobileScanner",
                                message: "Called start() while already started!",
                                details: nil))
        } catch MobileScannerError.noCamera {
            result(FlutterError(code: "MobileScanner",
                                message: "No camera found or failed to open camera!",
                                details: nil))
        } catch MobileScannerError.cameraError(let error) {
            result(FlutterError(code: "MobileScanner",
                                message: "Error occured when setting up camera!",
                                details: error))
        } catch {
            result(FlutterError(code: "MobileScanner",
                                message: "Unknown error occured.",
                                details: nil))
        }
    }

    /// Stops the mobileScanner and closes the texture.
    private func stop(_ result: @escaping FlutterResult) {
        do {
            try mobileScanner.stop()
        } catch {}
        result(nil)
    }

    /// Toggles the torch.
    private func toggleTorch(_ result: @escaping FlutterResult) {
        mobileScanner.toggleTorch()
        result(nil)
    }
    
    /// Sets the zoomScale.
    private func setScale(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let scale = call.arguments as? CGFloat
        if (scale == nil) {
            result(FlutterError(code: "MobileScanner",
                                message: "You must provide a scale when calling setScale!",
                                details: nil))
            return
        }
        do {
            try mobileScanner.setScale(scale!)
            result(nil)
        } catch MobileScannerError.zoomWhenStopped {
            result(FlutterError(code: "MobileScanner",
                                message: "Called setScale() while stopped!",
                                details: nil))
        } catch MobileScannerError.zoomError(let error) {
            result(FlutterError(code: "MobileScanner",
                                message: "Error while zooming.",
                                details: error))
        } catch {
            result(FlutterError(code: "MobileScanner",
                                message: "Error while zooming.",
                                details: nil))
        }
    }

    /// Reset the zoomScale.
    private func resetScale(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        do {
            try mobileScanner.resetScale()
            result(nil)
        } catch MobileScannerError.zoomWhenStopped {
            result(FlutterError(code: "MobileScanner",
                                message: "Called resetScale() while stopped!",
                                details: nil))
        } catch MobileScannerError.zoomError(let error) {
            result(FlutterError(code: "MobileScanner",
                                message: "Error while zooming.",
                                details: error))
        } catch {
            result(FlutterError(code: "MobileScanner",
                                message: "Error while zooming.",
                                details: nil))
        }
    }

    /// Updates the scan window rectangle.
    func updateScanWindow(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let scanWindowData: Array? = (call.arguments as? [String: Any])?["rect"] as? [CGFloat]
        MobileScannerPlugin.scanWindow = scanWindowData

        result(nil)
    }
    
    static func arrayToRect(scanWindowData: [CGFloat]?) -> CGRect? {
        if (scanWindowData == nil) {
            return nil
        }

        let minX = scanWindowData![0]
        let minY = scanWindowData![1]

        let width = scanWindowData![2]  - minX
        let height = scanWindowData![3] - minY

        return CGRect(x: minX, y: minY, width: width, height: height)
    }
    
}

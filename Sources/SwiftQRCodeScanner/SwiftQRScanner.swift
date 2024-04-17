//
//  SwiftQRScanner.swift
//  SwiftQRScanner
//
//  Created by Vinod Jagtap on 12/5/17.
//

#if os(iOS)
import UIKit
import CoreGraphics
import AVFoundation


/**
 QRCodeScannerController is a ViewController which calls up a method that presents a view with AVCaptureSession and previewLayer
 to scan QR and other codes.
 */
public class QRCodeScannerController: UIViewController,
                                      UIImagePickerControllerDelegate,
                                      UINavigationBarDelegate {
    
    // Weak reference to the delegate that will handle the scanned code
    public weak var delegate: QRScannerCodeDelegate?
    
    // Configuration for the QR scanner
    public var qrScannerConfiguration: QRScannerConfiguration
    
    // Button for toggling the flash
    private var flashButton: UIButton?
    
    // Default Properties
    private let spaceFactor: CGFloat = 16.0 // Spacing factor for layout
    private let devicePosition: AVCaptureDevice.Position = .back // Default camera position (back camera)
    private var _delayCount: Int = 0 // holds local delay count
    private let delayCount: Int = 15 // Maximum delay count
    private let roundButtonHeight: CGFloat = 50.0 // Height of the round button
    private let roundButtonWidth: CGFloat = 50.0 // Width of the round button
    
    var photoPicker: NSObject? // Object for presenting the photo picker (PHPhotoPicker or PhotoPicker)
    
    // Initialise CaptureDevice
    private lazy var defaultDevice: AVCaptureDevice? = {
        // Get the default video capture device
        if let device = AVCaptureDevice.default(for: .video) {
            return device
        }
        return nil
    }()
    
    // Initialise front CaptureDevice
    private lazy var frontDevice: AVCaptureDevice? = {
        if #available(iOS 10, *) {
            // Get the front-facing wide-angle camera (available from iOS 10)
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                return device
            }
        } else {
            // For older versions, iterate through available video devices and find the front-facing camera
            for device in AVCaptureDevice.devices(for: .video) {
                if device.position == .front { return device }
            }
        }
        return nil
    }()
    
    // Initialise AVCaptureInput with defaultDevice
    private lazy var defaultCaptureInput: AVCaptureInput? = {
        if let captureDevice = defaultDevice {
            do {
                // Create an AVCaptureDeviceInput with the default device
                return try AVCaptureDeviceInput(device: captureDevice)
            } catch let error as NSError {
                printLog(error.localizedDescription)
            }
        }
        return nil
    }()
    
    // Initialise AVCaptureInput with frontDevice
    private lazy var frontCaptureInput: AVCaptureInput? = {
        if let captureDevice = frontDevice {
            do {
                // Create an AVCaptureDeviceInput with the front device
                return try AVCaptureDeviceInput(device: captureDevice)
            } catch let error as NSError {
                printLog(error.localizedDescription)
            }
        }
        return nil
    }()
    
    private let dataOutput = AVCaptureMetadataOutput() // Output for capturing metadata (e.g., QR codes)
    private let captureSession = AVCaptureSession() // Capture session for video capture
    
    // Initialise videoPreviewLayer with capture session
    private lazy var videoPreviewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        layer.videoGravity = AVLayerVideoGravity.resizeAspectFill // Video gravity for preview layer
        layer.cornerRadius = 10.0 // Corner radius for preview layer
        return layer
    }()
    
    // Initializer with QRScannerConfiguration
    public init(qrScannerConfiguration: QRScannerConfiguration = .default) {
        self.qrScannerConfiguration = qrScannerConfiguration
        super.init(nibName: nil, bundle: nil)
        
        // Initialise photoPicker based on iOS version
        if #available(iOS 14, *) {
            photoPicker = PHPhotoPicker(presentationController: self, delegate: self) as PHPhotoPicker
        } else {
            photoPicker = PhotoPicker(presentationController: self, delegate: self) as PhotoPicker
        }
    }
    
    // Required convenience initializer for storyboard initialization
    required convenience init?(coder: NSCoder) {
        self.init()
    }
    
    deinit {
        printLog("SwiftQRScanner deallocated")
    }
    
    //MARK: Life cycle methods
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        self.presentationController?.delegate = self
        
        if !qrScannerConfiguration.hideNavigationBar {
            configureNavigationBar()
        } else {
            addCloseButton()
        }
    
        // Currently, only "Portrait" mode is supported
        setDeviceOrientation()
        _delayCount = 0
        prepareQRScannerView()
        startScanningQRCode()
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        addButtons()
    }
    
    private func configureNavigationBar() {
        let navigationBar = UINavigationBar(frame: CGRect(x: 0,
                                                          y: 0,
                                                          width: view.frame.size.width,
                                                          height: 44))
        navigationBar.shadowImage = UIImage()
        view.addSubview(navigationBar)
        
        // Create a navigation item with the title and a cancel button
        let title = UINavigationItem(title: qrScannerConfiguration.title)
        let cancelBarButton = UIBarButtonItem(title: qrScannerConfiguration.cancelButtonTitle,
                                              style: .plain,
                                              target: self,
                                              action: #selector(dismissViewController))
        if let tintColor = qrScannerConfiguration.cancelButtonTintColor {
            cancelBarButton.tintColor = tintColor
        }
        title.leftBarButtonItem = cancelBarButton
        navigationBar.setItems([title], animated: false)
    }
    
    private func addCloseButton() {
        let closeButton = CloseButton(frame: CGRect(x: 16, y: 16, width: 20, height: 20))
        closeButton.addTarget(self,
                              action: #selector(dismissViewController),
                              for: .touchUpInside)
        view.addSubview(closeButton)
    }
    
    private func setDeviceOrientation() {
        if #available(iOS 16.0, *) {
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue,
                                      forKey: "orientation")
        }
    }
    
    /**
     This method calls up other methods to prepare the view for scanning QR codes.
     - Parameter view: The UIView in which the scanner will be added.
     */
    private func prepareQRScannerView() {
        setupCaptureSession(devicePosition) // Default device capture position is rear
        addViedoPreviewLayer()
        addRoundCornerFrame()
    }
    
    // Creates a corner rectangle frame with a green color (default color)
    private func addRoundCornerFrame() {
        let width: CGFloat = self.view.frame.size.width / 1.5
        let height: CGFloat = self.view.frame.size.height / 2
        let roundViewFrame = CGRect(origin: CGPoint(x: self.view.frame.midX - width/2,
                                                    y: self.view.frame.midY - height/2),
                                    size: CGSize(width: width, height: width))
        self.view.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
        let qrFramedView = QRScannerFrame(frame: roundViewFrame)
        qrFramedView.thickness = qrScannerConfiguration.thickness
        qrFramedView.length = qrScannerConfiguration.length
        qrFramedView.radius = qrScannerConfiguration.radius
        qrFramedView.color = qrScannerConfiguration.color
        qrFramedView.autoresizingMask = UIView.AutoresizingMask(rawValue: UInt(0.0))
        self.view.addSubview(qrFramedView)
        if qrScannerConfiguration.readQRFromPhotos {
            addPhotoPickerButton(frame: CGRect(origin: CGPoint(x: self.view.frame.midX - width/2,
                                                               y: roundViewFrame.origin.y + width + 30),
                                               size: CGSize(width: self.view.frame.size.width/2.2, height: 36)))
        }
    }
    
    /**
     Adds a button to the view that allows the user to select photos from the gallery to scan for QR codes.
     - Parameter frame: The CGRect that specifies the frame of the button.
     */
    private func addPhotoPickerButton(frame: CGRect) {
        let photoPickerButton = UIButton(frame: frame)
        let buttonAttributes = [
            NSAttributedString.Key.font: UIFont.systemFont(ofSize: 14),
            NSAttributedString.Key.foregroundColor: UIColor.black
        ]
        let attributedTitle = NSMutableAttributedString(string: qrScannerConfiguration.uploadFromPhotosTitle,
                                                        attributes: buttonAttributes)
        photoPickerButton.setAttributedTitle(attributedTitle, for: .normal)
        photoPickerButton.center.x = self.view.center.x
        photoPickerButton.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        photoPickerButton.layer.cornerRadius = 18
        if let galleryImage = qrScannerConfiguration.galleryImage {
            photoPickerButton.setImage(galleryImage, for: .normal)
            photoPickerButton.imageEdgeInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
            photoPickerButton.titleEdgeInsets.left = 10
        }
        photoPickerButton.addTarget(self, action: #selector(showImagePicker), for: .touchUpInside)
        self.view.addSubview(photoPickerButton)
    }
    
    /**
     Presents the appropriate image picker (PHPhotoPicker or PhotoPicker) based on the iOS version to allow the user to select photos from the gallery.
     */
    @objc private func showImagePicker() {
        if #available(iOS 14, *) {
            if let picker = photoPicker as? PHPhotoPicker {
                picker.present()
            }
        } else {
            if let picker = photoPicker as? PhotoPicker {
                picker.present(from: self.view)
            }
        }
    }
    
    // MARK: - QR Scanner Extra Features
    
    /**
     Adds a torch button and a camera switch button to the view.
     
     - Requires: The `qrScannerConfiguration` property to have valid images for the buttons.
     */
    private func addButtons() {
        // Torch Button
        if let flashOffImage = qrScannerConfiguration.flashOnImage {
            let flashButton = RoundButton(frame: CGRect(x: 32,
                                                        y: view.frame.height - 100,
                                                        width: roundButtonWidth,
                                                        height: roundButtonHeight))
            flashButton.addTarget(self, action: #selector(toggleTorch), for: .touchUpInside)
            flashButton.setImage(flashOffImage, for: .normal)
            view.addSubview(flashButton)
            self.flashButton = flashButton
        }
        
        // Camera Switch Button
        if let cameraImage = qrScannerConfiguration.cameraImage {
            let cameraSwitchButton = RoundButton(frame: CGRect(x: view.bounds.width - (roundButtonWidth + 32),
                                                               y: view.frame.height - 100,
                                                               width: roundButtonWidth,
                                                               height: roundButtonHeight))
            cameraSwitchButton.setImage(cameraImage, for: .normal)
            cameraSwitchButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
            view.addSubview(cameraSwitchButton)
        }
    }
    
    /**
     Toggles the torch on the camera.
     
     - Important: This function does not work if the device is using the front camera.
     */
    @objc private func toggleTorch() {
        guard let currentInput = getCurrentInput() else { return }
        if currentInput.device.position == .front { return } // Front camera: torch not needed
        
        guard let defaultDevice = defaultDevice else { return }
        if defaultDevice.isTorchAvailable {
            do {
                try defaultDevice.lockForConfiguration()
                defaultDevice.torchMode = defaultDevice.torchMode == .on ? .off : .on
                flashButton?.backgroundColor = defaultDevice.torchMode == .on ?
                UIColor.white.withAlphaComponent(0.3) : UIColor.black.withAlphaComponent(0.5)
                defaultDevice.unlockForConfiguration()
            } catch let error as NSError {
                printLog("Torch Error: \(error)")
            }
        }
    }
    
    /**
     Switches between the front and rear cameras.
     */
    @objc private func switchCamera() {
        if let frontDeviceInput = frontCaptureInput {
            captureSession.beginConfiguration()
            if let currentInput = getCurrentInput() {
                captureSession.removeInput(currentInput)
                let newDeviceInput = (currentInput.device.position == .front) ? defaultCaptureInput : frontDeviceInput
                captureSession.addInput(newDeviceInput!)
            }
            captureSession.commitConfiguration()
        }
    }
    
    /// Gets the current camera input from the capture session.
    private func getCurrentInput() -> AVCaptureDeviceInput? {
        if let currentInput = captureSession.inputs.first as? AVCaptureDeviceInput {
            return currentInput
        }
        return nil
    }
    
    // MARK: - Dismissal
    
    @objc private func dismissViewController() {
        self.dismiss(animated: true, completion: nil)
        delegate?.qrScannerDidCancel(self)
    }
    
    // MARK: - Capture Session Setup and Management
    
    /**
     Starts running the capture session to begin scanning QR codes.
     
     - Important: This function does nothing if the capture session is already running.
     */
    private func startScanningQRCode() {
        if captureSession.isRunning { return }
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
    }
    
    /**
     Sets up the capture session with a specified camera position (front or back).
     
     - parameter devicePostion: The desired position of the camera to use (.front or .back).
     
     - Important: This function does nothing if the capture session is already running.
     */
    private func setupCaptureSession(_ devicePosition: AVCaptureDevice.Position) {
        if captureSession.isRunning { return }
        
        switch devicePosition {
        case .front:
            if let frontDeviceInput = frontCaptureInput {
                if !captureSession.canAddInput(frontDeviceInput) {
                    delegate?.qrScanner(self, didFailWithError: .inputFailed)
                    self.dismiss(animated: true, completion: nil)
                    return
                }
                captureSession.addInput(frontDeviceInput)
            }
        case .back, .unspecified:
            if let defaultDeviceInput = defaultCaptureInput {
                if !captureSession.canAddInput(defaultDeviceInput) {
                    delegate?.qrScanner(self, didFailWithError: .inputFailed)
                    self.dismiss(animated: true, completion: nil)
                    return
                }
                captureSession.addInput(defaultDeviceInput)
            }
        default:
            printLog("Do nothing for unsupported camera position")
        }
        
        if !captureSession.canAddOutput(dataOutput) {
            delegate?.qrScanner(self, didFailWithError: .outputFailed)
            self.dismiss(animated: true, completion: nil)
            return
        }
        captureSession.addOutput(dataOutput)
        dataOutput.metadataObjectTypes = dataOutput.availableMetadataObjectTypes
        dataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
    }
    
    /**
     Adds the video preview layer to the view with a mask to restrict the scanning area (optional).
     */
    private func addViedoPreviewLayer() {
        videoPreviewLayer.frame = view.bounds
        view.layer.insertSublayer(videoPreviewLayer, at: 0)
        addMaskToVideoPreviewLayer()
    }
}

// MARK: - QR Code Scanning Delegate

extension QRCodeScannerController: AVCaptureMetadataOutputObjectsDelegate {
    
    /**
     This delegate method is called when a QR code is detected in the camera view.
     
     - parameter output: The AVCaptureMetadataOutput instance that received the metadata objects.
     - parameter metadataObjects: An array of AVMetadataObject instances representing the detected objects.
     - parameter connection: The AVCaptureConnection that received the metadata objects.
     
     This function iterates through the detected objects, checks for QR code type, validates its position within the view, and triggers a delay before notifying the delegate about the scan result.
     */
    public func metadataOutput(_ output: AVCaptureMetadataOutput,
                               didOutput metadataObjects: [AVMetadataObject],
                               from connection: AVCaptureConnection) {
        for data in metadataObjects {
            guard let transformed = videoPreviewLayer.transformedMetadataObject(for: data) as? AVMetadataMachineReadableCodeObject else { continue }
            if view.bounds.contains(transformed.bounds) {
                _delayCount += 1
                if _delayCount > delayCount {
                    if let unwrappedStringValue = transformed.stringValue {
                        delegate?.qrScanner(self, didScanQRCodeWithResult: unwrappedStringValue)
                    } else {
                        delegate?.qrScanner(self, didFailWithError: .emptyResult)
                    }
                    captureSession.stopRunning()
                    self.dismiss(animated: true, completion: nil)
                }
            }
        }
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate

extension QRCodeScannerController: UIAdaptivePresentationControllerDelegate {
    /// Notifies the delegate that the presentation controller was dismissed.
    ///
    /// - Parameter presentationController: The presentation controller that was dismissed.
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        self.delegate?.qrScannerDidCancel(self)
    }
}

// MARK: - ImagePickerDelegate

extension QRCodeScannerController: ImagePickerDelegate {
    /// Called when an image is selected from the image picker.
    ///
    /// - Parameter image: The selected image.
    public func didSelect(image: UIImage?) {
        if let selectedImage = image, let qrCodeData = selectedImage.parseQRCode() {
            if qrCodeData.isEmpty {
                showInvalidQRCodeAlert()
                return
            }
            self.delegate?.qrScanner(self, didScanQRCodeWithResult: qrCodeData)
            self.dismiss(animated: true)
        } else {
            showInvalidQRCodeAlert()
        }
    }
    
    /// Shows an alert for an invalid QR code.
    private func showInvalidQRCodeAlert() {
        let alert = UIAlertController(title: qrScannerConfiguration.invalidQRCodeAlertTitle,
                                      message: "",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: qrScannerConfiguration.invalidQRCodeAlertActionTitle,
                                      style: .cancel))
        self.present(alert, animated: true)
    }
}


// MARK: - Orientation Handling

extension QRCodeScannerController {
    /// Ensures that the orientation is always portrait.
    
    override public var shouldAutorotate: Bool {
        return false
    }
    
    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override public var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
}

// MARK: - Masking and Hint Text

extension QRCodeScannerController {
    /// Adds a mask layer to the video preview layer.
    private func addMaskToVideoPreviewLayer() {
        let qrFrameWidth: CGFloat = self.view.frame.size.width / 1.5
        let scanFrameWidth: CGFloat = self.view.frame.size.width / 1.8
        let scanFrameHeight: CGFloat = self.view.frame.size.width / 1.8
        let screenHeight: CGFloat = self.view.frame.size.height / 2
        let roundViewFrame = CGRect(origin: CGPoint(x: self.view.frame.midX - scanFrameWidth/2,
                                                    y: self.view.frame.midY - screenHeight/2 + (qrFrameWidth-scanFrameWidth)/2),
                                    size: CGSize(width: scanFrameWidth, height: scanFrameHeight))
        let maskLayer = CAShapeLayer()
        maskLayer.frame = view.bounds
        maskLayer.fillColor = UIColor(white: 0.0, alpha: 0.5).cgColor
        let path = UIBezierPath(roundedRect: roundViewFrame, byRoundingCorners: [.allCorners], cornerRadii: CGSize(width: 10, height: 10))
        path.append(UIBezierPath(rect: view.bounds))
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        view.layer.insertSublayer(maskLayer, above: videoPreviewLayer)
        addHintTextLayer(maskLayer: maskLayer)
    }
    
    /// Adds hint text layer above the mask layer.
    ///
    /// - Parameter maskLayer: The mask layer to which the hint text layer will be added.
    private func addHintTextLayer(maskLayer: CAShapeLayer) {
        guard let hint = qrScannerConfiguration.hint else { return }
        let hintTextLayer = CATextLayer()
        hintTextLayer.fontSize = 18.0
        hintTextLayer.string = hint
        hintTextLayer.alignmentMode = .center
        hintTextLayer.contentsScale = UIScreen.main.scale
        hintTextLayer.frame = CGRect(x: spaceFactor,
                                     y: self.view.frame.midY - self.view.frame.size.height/4 - 62,
                                     width: view.frame.size.width - (2.0 * spaceFactor),
                                     height: 22)
        hintTextLayer.foregroundColor = UIColor.white.withAlphaComponent(0.7).cgColor
        view.layer.insertSublayer(hintTextLayer, above: maskLayer)
    }
}

// MARK: - DebugLog
extension QRCodeScannerController {
    func printLog(_ message: String,
                  file: String = #file,
                  function: String = #function,
                  line: Int = #line) {
#if DEBUG
        let fileName = (file as NSString).lastPathComponent
        print("[\(fileName)::\(function)::\(line)] \(message)")
#endif
    }
}

#endif

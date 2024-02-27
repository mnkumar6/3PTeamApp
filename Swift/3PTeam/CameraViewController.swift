/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's primary view controller that presents the camera interface.
*/

import UIKit
import AVFoundation
import CoreLocation
import Photos

class CameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate, AVCapturePhotoOutputReadinessCoordinatorDelegate, UIGestureRecognizerDelegate {
    
    let locationManager = CLLocationManager()
    
    // MARK: View Controller Life Cycle
    
    @IBOutlet weak var zoomLabel: UILabel!
    
    
    private var maximumZoom = CGFloat.greatestFiniteMagnitude
    private var minimumZoom = CGFloat(1.0)
    private var lastZoomFactor: CGFloat = 1.0
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Disable the UI. Enable the UI later, if and only if the session
        // starts running.
        cameraButton.isEnabled = false
        recordButton.isEnabled = false
        photoButton.isEnabled = false
        captureModeControl.isEnabled = false
        HDRVideoModeButton.isHidden = true
        recordButton.isHidden = true
        zoomLabel.isHidden = true
        
        
        //Add Pinch Gesture to previewView.VideoPreviewLayer
        let pinchRecognizer = UIPinchGestureRecognizer(target: self, action:#selector(pinch(_:)))
        pinchRecognizer.delegate = self
        self.previewView.addGestureRecognizer(pinchRecognizer)
        
        // Set up the video preview view.
        previewView.session = session
        
        // Request location authorization so photos and videos can be tagged
        // with their location.
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        
        // Check the video authorization status. Video access is required and
        // audio access is optional. If the user denies audio access,
        // won't record audio during movie recording.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. Suspend the session queue to delay session
             setup until the access request has completed.
             
             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
        
        /*
         Setup the capture session.
         In general, it's not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Don't perform these tasks on the main queue because
         AVCaptureSession.startRunning() is a blocking call, which can
         take a long time. Dispatch session setup to the sessionQueue, so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()
        }
    }
    
    @objc func pinch(_ pinch: UIPinchGestureRecognizer) {

        let device = videoDeviceInput.device
        
        self.zoomLabel.isHidden = false
        

        // Return zoom value between the minimum and maximum zoom values
        func minMaxZoom(_ factor: CGFloat) -> CGFloat {
            return min(min(max(factor, minimumZoom), maximumZoom), device.activeFormat.videoMaxZoomFactor)
        }

        func update(scale factor: CGFloat) {
            //self.zoomLabel.text = ""
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.videoZoomFactor = factor
                
                print("zoomScale: \(round(factor))")
                DispatchQueue.main.async {
                    self.zoomLabel.text = ""
                    self.zoomLabel.text = "zoomLevel: \((round(factor)))"
                }
                
            } catch {
                print("\(error.localizedDescription)")
            }
        }

        let newScaleFactor = minMaxZoom(pinch.scale * lastZoomFactor)

        switch pinch.state {
        case .began: fallthrough
        case .changed: update(scale: newScaleFactor)
        case .ended:
            lastZoomFactor = minMaxZoom(newScaleFactor)
            update(scale: lastZoomFactor)
            self.zoomLabel.isHidden = true
        default: break
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session if setup
                // succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "3PTeam app doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "3PTeam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                  options: [:],
                                                  completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "3PTeam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    override var shouldAutorotate: Bool {
        // Disable autorotation of the interface when recording is in progress.
        if let movieFileOutput = movieFileOutput {
            return !movieFileOutput.isRecording
        }
        return true
    }
    
    // MARK: Session Management
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private let session = AVCaptureSession()
    private var isSessionRunning = false
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue")
    
    private var setupResult: SessionSetupResult = .success
    
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    
    @IBOutlet private weak var previewView: PreviewView!
    
    // Call this on the session queue.
    /// - Tag: ConfigureSession
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        // Do not create an AVCaptureMovieFileOutput when setting up the session
        // because Live Photo is not supported when AVCaptureMovieFileOutput is
        // added to the session.
        session.sessionPreset = .high
        
        // Add video input.
        do {
            // Handle the situation when the system-preferred camera is nil.
            var defaultVideoDevice: AVCaptureDevice? = AVCaptureDevice.systemPreferredCamera
            
            let userDefaults = UserDefaults.standard
            if !userDefaults.bool(forKey: "setInitialUserPreferredCamera") || defaultVideoDevice == nil {
                let backVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInWideAngleCamera, .builtInUltraWideCamera], mediaType: .video, position: .back)
                
                defaultVideoDevice = backVideoDeviceDiscoverySession.devices.first
                
                AVCaptureDevice.userPreferredCamera = defaultVideoDevice
                
                userDefaults.set(true, forKey: "setInitialUserPreferredCamera")
            }
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            AVCaptureDevice.self.addObserver(self, forKeyPath: "systemPreferredCamera", options: [.new], context: &systemPreferredCameraContext)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    // Dispatch video streaming to the main queue because
                    // AVCaptureVideoPreviewLayer is the backing layer for
                    // PreviewView. You can manipulate UIView only on the main
                    // thread. Note: As an exception to the above rule, it's not
                    // necessary to serialize video orientation changes on the
                    // AVCaptureVideoPreviewLayer’s connection with other
                    // session manipulation.
                    self.createDeviceRotationCoordinator()
                }
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add an audio input device.
        do {
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
            
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            } else {
                print("Could not add audio device input to the session")
            }
        } catch {
            print("Could not create audio device input: \(error)")
        }
        
        // Add the photo output.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            photoQualityPrioritizationMode = .balanced
            
            self.configurePhotoOutput()
            
            let readinessCoordinator = AVCapturePhotoOutputReadinessCoordinator(photoOutput: photoOutput)
            DispatchQueue.main.async {
                self.photoOutputReadinessCoordinator = readinessCoordinator
                readinessCoordinator.delegate = self
            }
            
        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    @IBAction private func resumeInterruptedSession(_ resumeButton: UIButton) {
        sessionQueue.async {
            // The session might fail to start running, for example, if a phone
            // or FaceTime call is still using audio or video. This failure is
            // communicated by the session posting a runtime error notification.
            // To avoid repeatedly failing to start the session, only try to
            // restart the session in the error handler if you aren't trying to
            // resume the session.
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "3PTeam", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            } else {
                DispatchQueue.main.async {
                    self.resumeButton.isHidden = true
                }
            }
        }
    }
    
    private enum CaptureMode: Int {
        case photo = 0
        case movie = 1
    }
    
    @IBOutlet private weak var captureModeControl: UISegmentedControl!
    
    /// - Tag: EnableDisableModes
    @IBAction private func toggleCaptureMode(_ captureModeControl: UISegmentedControl) {
        captureModeControl.isEnabled = false
        
        if captureModeControl.selectedSegmentIndex == CaptureMode.photo.rawValue {
            recordButton.isEnabled = false
            recordButton.isHidden = true
            photoButton.isHidden = false
            HDRVideoModeButton.isHidden = true
            ExposureButton.isHidden = false
            
            selectedMovieMode10BitDeviceFormat = nil
            
            sessionQueue.async {
                // Remove the AVCaptureMovieFileOutput from the session because
                self.session.beginConfiguration()
                self.session.removeOutput(self.movieFileOutput!)
                if self.ExposureMode == .on {
                    self.session.sessionPreset = .photo
                }
                DispatchQueue.main.async {
                    captureModeControl.isEnabled = true
                }
                
                self.movieFileOutput = nil
                
                self.configurePhotoOutput()
                
                if let connection = self.photoOutput.connection(with: .video) {
                    if connection.isVideoStabilizationSupported {
                        if self.VDISMode == .on {
                            print("stabilization On")
                            connection.preferredVideoStabilizationMode = .auto  //.auto .standard, .cinematic, .cinematicExtended, .previewOptimized
                        } else {
                            print("stabilization Off")
                            connection.preferredVideoStabilizationMode = .off
                        }
                    } else {
                        print("stabilization not supported")
                        self.showAlert(message: "Stabilization is not supported")
                    }
                }
                
                self.session.commitConfiguration()
                
            }
        } else if captureModeControl.selectedSegmentIndex == CaptureMode.movie.rawValue {
            recordButton.isHidden = false
            photoButton.isHidden = true
            ExposureButton.isHidden = true
            
            
            sessionQueue.async {
                let movieFileOutput = AVCaptureMovieFileOutput()
                
                if self.session.canAddOutput(movieFileOutput) {
                    self.session.beginConfiguration()
                    self.session.addOutput(movieFileOutput)
                    self.session.sessionPreset = .high
                    
                    self.selectedMovieMode10BitDeviceFormat = self.tenBitVariantOfFormat(activeFormat: self.videoDeviceInput.device.activeFormat)
                    
                    if self.selectedMovieMode10BitDeviceFormat != nil {
                        DispatchQueue.main.async {
                            self.HDRVideoModeButton.isHidden = false
                            self.HDRVideoModeButton.isEnabled = true
                        }
                        
                        if self.HDRVideoMode == .on {
                            do {
                                try self.videoDeviceInput.device.lockForConfiguration()
                                self.videoDeviceInput.device.activeFormat = self.selectedMovieMode10BitDeviceFormat!
                                print("Setting 'x420' format \(String(describing: self.selectedMovieMode10BitDeviceFormat)) for video recording")
                                self.videoDeviceInput.device.unlockForConfiguration()
                            } catch {
                                print("Could not lock device for configuration: \(error)")
                            }
                        }
                    }
                    
                        if let connection = movieFileOutput.connection(with: .video) {
                            if connection.isVideoStabilizationSupported {
                                if self.VDISMode == .on {
                                    print("stabilization On")
                                    connection.preferredVideoStabilizationMode = .auto  //.auto .standard, .cinematic, .cinematicExtended, .previewOptimized
                                } else {
                                    print("stabilization Off")
                                    connection.preferredVideoStabilizationMode = .off
                                }
                            } else {
                                print("stabilization not supported")
                            }
                        }
                    
                    self.session.commitConfiguration()
                    
                    DispatchQueue.main.async {
                        captureModeControl.isEnabled = true
                    }
                    
                    self.movieFileOutput = movieFileOutput
                    
                    DispatchQueue.main.async {
                        self.recordButton.isEnabled = true
                    }
                }
            }
        }
    }
    
    private func configurePhotoOutput() {
        let supportedMaxPhotoDimensions = self.videoDeviceInput.device.activeFormat.supportedMaxPhotoDimensions
        let largestDimesnion = supportedMaxPhotoDimensions.last
        self.photoOutput.maxPhotoDimensions = largestDimesnion!
        self.photoOutput.maxPhotoQualityPrioritization = .quality
        
        self.photoOutput.isResponsiveCaptureEnabled = self.photoOutput.isResponsiveCaptureSupported
        self.photoOutput.isFastCapturePrioritizationEnabled = self.photoOutput.isFastCapturePrioritizationSupported
        self.photoOutput.isAutoDeferredPhotoDeliveryEnabled = self.photoOutput.isAutoDeferredPhotoDeliverySupported
        
        let photoSettings = self.setUpPhotoSettings()
        DispatchQueue.main.async {
            self.photoSettings = photoSettings
        }
    }
    
    // MARK: Device Configuration
    
    @IBOutlet private weak var cameraButton: UIButton!
    
    @IBOutlet private weak var cameraUnavailableLabel: UILabel!
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera, .builtInUltraWideCamera], mediaType: .video, position: .unspecified)
    
    private var videoDeviceRotationCoordinator: AVCaptureDevice.RotationCoordinator!
    
    private var videoDeviceIsConnectedObservation: NSKeyValueObservation?
    
    /// - Tag: ChangeCamera
    @IBAction private func changeCameraButtonPressed(_ cameraButton: UIButton) {
        cameraButton.isEnabled = false
        recordButton.isEnabled = false
        photoButton.isEnabled = false
        captureModeControl.isEnabled = false
        HDRVideoModeButton.isEnabled = false
        self.selectedMovieMode10BitDeviceFormat = nil
        
        self.changeCamera(nil, isUserSelection: true, completion: {
            
            DispatchQueue.main.async {
                self.cameraButton.isEnabled = true
                self.recordButton.isEnabled = self.movieFileOutput != nil
                self.photoButton.isEnabled = true
                self.captureModeControl.isEnabled = true
            }
        })
    }
    
    private func changeCamera(_ videoDevice: AVCaptureDevice?, isUserSelection: Bool, completion: (() -> Void)? = nil) {
        sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let newVideoDevice: AVCaptureDevice?
            
            if let videoDevice = videoDevice {
                newVideoDevice = videoDevice
            } else {
                let currentPosition = currentVideoDevice.position
                
                let backVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInWideAngleCamera, .builtInUltraWideCamera],mediaType: .video, position: .back)
//                let backVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera], mediaType: .video, position: .back)
                
                let frontVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera], mediaType: .video, position: .front)
                let externalVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.external],
                                                                                           mediaType: .video, position: .unspecified)
                
                switch currentPosition {
                case .unspecified, .front:
                    newVideoDevice = backVideoDeviceDiscoverySession.devices.first
                    
                case .back:
                    if let externalCamera = externalVideoDeviceDiscoverySession.devices.first {
                        newVideoDevice = externalCamera
                    } else {
                        newVideoDevice = frontVideoDeviceDiscoverySession.devices.first
                    }
                    
                @unknown default:
                    print("Unknown capture position. Defaulting to back, dual-camera.")
                    newVideoDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
                }
            }
            
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    
                    // Remove the existing device input first, because
                    // AVCaptureSession doesn't support simultaneous use of the
                    // rear and front cameras.
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                        NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
                        
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                        
                        if isUserSelection {
                            AVCaptureDevice.userPreferredCamera = videoDevice
                        }
                        
                        DispatchQueue.main.async {
                            self.createDeviceRotationCoordinator()
                        }
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }
                    if let connection = self.movieFileOutput?.connection(with: .video) {
                        self.session.sessionPreset = .high
                        
                        self.selectedMovieMode10BitDeviceFormat = self.tenBitVariantOfFormat(activeFormat: self.videoDeviceInput.device.activeFormat)
                        
                        if self.selectedMovieMode10BitDeviceFormat != nil {
                            DispatchQueue.main.async {
                                self.HDRVideoModeButton.isEnabled = true
                            }
                            
                            if self.HDRVideoMode == .on {
                                do {
                                    try self.videoDeviceInput.device.lockForConfiguration()
                                    self.videoDeviceInput.device.activeFormat = self.selectedMovieMode10BitDeviceFormat!
                                    print("Setting 'x420' format \(String(describing: self.selectedMovieMode10BitDeviceFormat)) for video recording")
                                    self.videoDeviceInput.device.unlockForConfiguration()
                                } catch {
                                    print("Could not lock device for configuration: \(error)")
                                }
                            }
                        }
                        
                            if connection.isVideoStabilizationSupported {
                                if self.VDISMode == .on {
                                    print("stabilization ON")
                                    connection.preferredVideoStabilizationMode = .auto   // .standard, .cinematic, cinematicExtended, previewOptimized
                                } else {
                                    print("stabilization Off")
                                    connection.preferredVideoStabilizationMode = .off
                                }
                            } else {
                                print("stabilization not supported")
                            }
                        
                    }
                    
                    // other properties of
                    // the`AVCapturePhotoOutput` are `NO` when a video device
                    // disconnects from the session. After the session acquires
                    // a new video device, you need to reconfigure the photo
                    // output to enable those properties, if applicable.
                    self.configurePhotoOutput()
                    
                    self.session.commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }
            
            completion?()
        }
    }
    
    // MARK: Readiness Coordinator
    
    func readinessCoordinator(_ coordinator: AVCapturePhotoOutputReadinessCoordinator, captureReadinessDidChange captureReadiness: AVCapturePhotoOutput.CaptureReadiness) {
        // Enable user interaction for the shutter button only when the output
        // is ready to capture.
        self.photoButton.isUserInteractionEnabled = (captureReadiness == .ready) ? true : false
        
        // Note: You can customize the shutter button's appearance based on
        // `captureReadiness`.
    }
    
    private var videoRotationAngleForHorizonLevelPreviewObservation: NSKeyValueObservation?
    
    private func createDeviceRotationCoordinator() {
        videoDeviceRotationCoordinator = AVCaptureDevice.RotationCoordinator(device: videoDeviceInput.device, previewLayer: previewView.videoPreviewLayer)
        previewView.videoPreviewLayer.connection?.videoRotationAngle = videoDeviceRotationCoordinator.videoRotationAngleForHorizonLevelPreview
        
        videoRotationAngleForHorizonLevelPreviewObservation = videoDeviceRotationCoordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { _, change in
            guard let videoRotationAngleForHorizonLevelPreview = change.newValue else { return }
            
            self.previewView.videoPreviewLayer.connection?.videoRotationAngle = videoRotationAngleForHorizonLevelPreview
        }
    }
    
    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        focus(with: .continuousAutoFocus, at: devicePoint, monitorSubjectAreaChange: true)
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode,
                       at devicePoint: CGPoint,
                       monitorSubjectAreaChange: Bool) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                // Setting (focus/exposure)PointOfInterest alone does not
                // initiate a (focus/exposure) operation. Call
                // set(Focus/Exposure)Mode() to apply the new point of interest.
                
                if self.ExposureMode == .off {
                    if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                        device.focusPointOfInterest = devicePoint
                        device.focusMode = focusMode
                        if device.isSmoothAutoFocusSupported {
                            device.isSmoothAutoFocusEnabled = true
                        }
                    }
                } else {
                    if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                        device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                        device.focusMode = focusMode
                        if device.isSmoothAutoFocusSupported {
                            device.isSmoothAutoFocusEnabled = false
                        }
                    }
                }
                let exposureMode: AVCaptureDevice.ExposureMode = self.ExposureMode == .on ? .continuousAutoExposure : .locked
                if self.ExposureMode == .on {
                    if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                        device.exposurePointOfInterest = devicePoint
                        device.exposureMode = exposureMode
                        print("Exposure Set \(exposureMode) \(devicePoint)")
                        
                        
                    }
                }
                if self.LowLightMode == .on {
                    if device.isLowLightBoostSupported {
                        device.automaticallyEnablesLowLightBoostWhenAvailable = true
                    } else {
                        print("Low light is not supported")
                        //self.showAlert(message: "Low light is not supported")
                    }
                } else {
                    if device.isLowLightBoostSupported {
                        device.automaticallyEnablesLowLightBoostWhenAvailable = false
                    } else {
                        print("Low light is not supported")
                        //self.showAlert(message: "Low light is not supported")
                    }
                }
                
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    // MARK: Capturing Photos
    
    private let photoOutput = AVCapturePhotoOutput()
    
    var photoOutputReadinessCoordinator: AVCapturePhotoOutputReadinessCoordinator!
    
    var photoSettings: AVCapturePhotoSettings!
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    @IBOutlet private weak var photoButton: UIButton!
    
    /// - Tag: CapturePhoto
    @IBAction private func capturePhoto(_ photoButton: UIButton) {
        
        if self.photoSettings == nil {
            print("No photo settings to capture")
            return
        }
        
        // Create a unique settings object for the request.
        let photoSettings = AVCapturePhotoSettings(from: self.photoSettings)
        
        
        // Start tracking capture readiness on the main thread to synchronously
        // update the shutter button's availability.
        self.photoOutputReadinessCoordinator.startTrackingCaptureRequest(using: photoSettings)
        
        let videoRotationAngle = self.videoDeviceRotationCoordinator.videoRotationAngleForHorizonLevelCapture
        
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoRotationAngle = videoRotationAngle
            }
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
                // Flash the screen to signal that app took a photo.
                DispatchQueue.main.async {
                    self.previewView.videoPreviewLayer.opacity = 0
                    UIView.animate(withDuration: 0.25) {
                        self.previewView.videoPreviewLayer.opacity = 1
                    }
                }
            }, completionHandler: { photoCaptureProcessor in
                // When the capture is complete, remove a reference to the
                // photo capture delegate so it can be deallocated.
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }
            })
            
            // Specify the location the photo was taken
            photoCaptureProcessor.location = self.locationManager.location
            
            // The photo output holds a weak reference to the photo capture
            // delegate and stores it in an array to maintain a strong
            // reference.
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
            
            // Stop tracking the capture request because it's now destined for
            // the photo output.
            self.photoOutputReadinessCoordinator.stopTrackingCaptureRequest(using: photoSettings.uniqueID)
        }
    }
    
    private func setUpPhotoSettings() -> AVCapturePhotoSettings {
        var photoSettings = AVCapturePhotoSettings()
        
//        if self.HDRVideoMode == .on {
//            // Check for available photo pixel format types
//            
//            let availableFormats = photoOutput.availablePhotoPixelFormatTypes
//
//                print("Available photo pixel format types:")
//                for format in availableFormats {
//                    switch format {
//                    case kCVPixelFormatType_32BGRA:
//                        print("kCVPixelFormatType_32BGRA")
//                    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
//                        print("kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange")
//                    case kCVPixelFormatType_422YpCbCr8BiPlanarFullRange:
//                        print("kCVPixelFormatType_422YpCbCr8BiPlanarFullRange")
//                    case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
//                        print("kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange")
//                    case kCVPixelFormatType_422YpCbCr10BiPlanarFullRange:
//                        print("kCVPixelFormatType_422YpCbCr10BiPlanarFullRange")
//                    case kCVPixelFormatType_64ARGB:
//                        print("kCVPixelFormatType_64ARGB")
//                    default:
//                        print("Unknown format: \(format)")
//                    }
//                }
//            
//            let desiredFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
//
//            if availableFormats.contains(desiredFormat) {
//                photoSettings = AVCapturePhotoSettings(format: [kCVPixelBufferPixelFormatTypeKey as String: desiredFormat])
//            } else {
//                print("Desired format not available. Using default format.")
//            }
//        } else 
        if self.photoOutput.availablePhotoCodecTypes.contains(AVVideoCodecType.hevc) {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            photoSettings = AVCapturePhotoSettings()
        }
        
        
        // Set the flash to auto mode.
//        if self.videoDeviceInput.device.isFlashAvailable {
//            photoSettings.flashMode = .auto
//        }
        
        // Enable high-resolution photos.
        photoSettings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
        if !photoSettings.availablePreviewPhotoPixelFormatTypes.isEmpty {
            photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
        }
        
        photoSettings.photoQualityPrioritization = self.photoQualityPrioritizationMode
        
        return photoSettings
    }
    
    private func livePhotoMovieUniqueTemporaryDirectoryFileURL() -> URL {
        let livePhotoMovieFileName = UUID().uuidString
        let livePhotoMovieFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((livePhotoMovieFileName as NSString).appendingPathExtension("mov")!)
        let livePhotoMovieURL = NSURL.fileURL(withPath: livePhotoMovieFilePath)
        return livePhotoMovieURL
    }
    
    private enum LivePhotoMode {
        case on
        case off
    }

    
    private var photoQualityPrioritizationMode: AVCapturePhotoOutput.QualityPrioritization = .balanced
    
    
    func tenBitVariantOfFormat(activeFormat: AVCaptureDevice.Format) -> AVCaptureDevice.Format? {
        let formats = self.videoDeviceInput.device.formats
        let formatIndex = formats.firstIndex(of: activeFormat)!
        
        let activeDimensions = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)
        let activeMaxFrameRate = activeFormat.videoSupportedFrameRateRanges.last?.maxFrameRate
        let activePixelFormat = CMFormatDescriptionGetMediaSubType(activeFormat.formatDescription)
        
        // AVCaptureDeviceFormats are sorted from smallest to largest in
        // resolution and frame rate. For each resolution and max frame rate
        // there's a cluster of formats that only differ in pixelFormatType.
        // Here, we look for an 'x420' variant of the current activeFormat.
        if activePixelFormat != kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
            // Current activeFormat is not a 10-bit HDR format, find its 10-bit
            // HDR variant.
            for index in formatIndex + 1..<formats.count {
                let format = formats[index]
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let maxFrameRate = format.videoSupportedFrameRateRanges.last?.maxFrameRate
                let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
                
                // Don't advance beyond the current format cluster
                if activeMaxFrameRate != maxFrameRate || activeDimensions.width != dimensions.width || activeDimensions.height != dimensions.height {
                    break
                }
                
                if pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
                    return format
                }
            }
        } else {
            return activeFormat
        }
        
        return nil
    }
    
    private var selectedMovieMode10BitDeviceFormat: AVCaptureDevice.Format?
    
    private enum ToggleMode {
        case on
        case off
    }
    
    
    private var HDRVideoMode: ToggleMode = .off
    private var ExposureMode: ToggleMode = .off
    private var VDISMode: ToggleMode = .off
    private var LowLightMode: ToggleMode = .off
    
    
    @IBOutlet private weak var HDRVideoModeButton: UIButton!
    
    @IBOutlet weak var ExposureButton: UIButton!
    
    @IBOutlet weak var VDISButton: UIButton!
    
    @IBOutlet weak var LowLightButton: UIButton!
    
    @IBAction private func toggleExposureMode(_ ExposureButton: UIButton) {
        sessionQueue.async {
            self.ExposureMode = (self.ExposureMode == .on) ? .off : .on
            let ExposureMode = self.ExposureMode
            let device = self.videoDeviceInput.device
            let devicePoint = CGPoint(x: 0.5, y: 0.5)
            DispatchQueue.main.async {
                if device.isExposurePointOfInterestSupported {
                    print("exposure supported")
                    if ExposureMode == .on {
                        self.ExposureButton.setTitle("Exposure On", for: .normal)
                        print("exposure ON")
                    } else {
                        self.ExposureButton.setTitle("Exposure Off", for: .normal)
                        print("exposure OFF")
                    }      
                    self.focus(with: .continuousAutoFocus, at: devicePoint, monitorSubjectAreaChange: false)
                } else {
                    print("exposure not supported")
                    self.showAlert(message: "Exposure is not supported")
                }
            }
        }
    }
    
    @IBAction private func toggleLowLightMode(_ LowLightButton: UIButton) {
        sessionQueue.async {
            self.LowLightMode = (self.LowLightMode == .on) ? .off : .on
            let LowLightMode = self.LowLightMode
            let device = self.videoDeviceInput.device
            let devicePoint = CGPoint(x: 0.5, y: 0.5)
            DispatchQueue.main.async {
                if device.isLowLightBoostSupported {
                    print("LowLight supported")
                    if LowLightMode == .on {
                        self.ExposureButton.setTitle(" On", for: .normal)
                        print("LowLight ON")
                    } else {
                        self.ExposureButton.setTitle(" Off", for: .normal)
                        print("LowLight OFF")
                    }
                    self.focus(with: .continuousAutoFocus, at: devicePoint, monitorSubjectAreaChange: false)
                } else {
                    print("LowLight not supported")
                    self.showAlert(message: "Low light is not supported")
                }
            }
        }
    }
    
    @IBAction private func toggleVDISMode(_ VDISButton: UIButton) {
        sessionQueue.async {
            self.VDISMode = (self.VDISMode == .on) ? .off : .on
            let VDISMode = self.VDISMode
            DispatchQueue.main.async {
                    //print("vdis supported")
                    if VDISMode == .on {
                        self.VDISButton.setTitle("VDIS On", for: .normal)
                        print("vdis ON")
                    } else {
                        self.VDISButton.setTitle("VDIS Off", for: .normal)
                        print("vdis OFF")
                    }
            }
        }
    }
    
    
    @IBAction private func toggleHDRVideoMode(_ HDRVideoModeButton: UIButton) {
        sessionQueue.async {
            self.HDRVideoMode = (self.HDRVideoMode == .on) ? .off : .on
            let HDRVideoMode = self.HDRVideoMode
            
            DispatchQueue.main.async {
                if HDRVideoMode == .on {
                    do {
                        try self.videoDeviceInput.device.lockForConfiguration()
                        self.videoDeviceInput.device.activeFormat = self.selectedMovieMode10BitDeviceFormat!
                        self.videoDeviceInput.device.unlockForConfiguration()
                    } catch {
                        print("Could not lock device for configuration: \(error)")
                    }
                    self.HDRVideoModeButton.setTitle("HDR On", for: .normal)
                } else {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .high
                    self.session.commitConfiguration()
                    self.HDRVideoModeButton.setTitle("HDR Off", for: .normal)
                }
            }
        }
    }
    
    private var inProgressLivePhotoCapturesCount = 0
    
    @IBOutlet var capturingLivePhotoLabel: UILabel!
    
    // MARK: Recording Movies
    
    private var movieFileOutput: AVCaptureMovieFileOutput?
    
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    
    @IBOutlet private weak var recordButton: UIButton!
    
    @IBOutlet private weak var resumeButton: UIButton!
    
    @IBAction private func toggleMovieRecording(_ recordButton: UIButton) {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        
        /*
         Disable the Camera button until recording finishes, and disable
         the Record button until recording starts or finishes.
         
         See the AVCaptureFileOutputRecordingDelegate methods.
         */
        cameraButton.isEnabled = false
        recordButton.isEnabled = false
        captureModeControl.isEnabled = false
        
        let videoRotationAngle = self.videoDeviceRotationCoordinator.videoRotationAngleForHorizonLevelCapture
        
        if let window = self.view.window, let windowScene = window.windowScene {
            switch windowScene.interfaceOrientation {
            case .portrait: self.supportedInterfaceOrientations = .portrait
            case .landscapeLeft: self.supportedInterfaceOrientations = .landscapeLeft
            case .landscapeRight: self.supportedInterfaceOrientations = .landscapeRight
            case .portraitUpsideDown: self.supportedInterfaceOrientations = .portraitUpsideDown
            case .unknown: self.supportedInterfaceOrientations = .portrait
            default: self.supportedInterfaceOrientations = .portrait
            }
        }
        self.setNeedsUpdateOfSupportedInterfaceOrientations()
        
        sessionQueue.async {
            if !movieFileOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                // Update the orientation on the movie file output video
                // connection before recording.
                let movieFileOutputConnection = movieFileOutput.connection(with: .video)
                movieFileOutputConnection?.videoRotationAngle = videoRotationAngle
                
                let availableVideoCodecTypes = movieFileOutput.availableVideoCodecTypes
                
                if availableVideoCodecTypes.contains(.hevc) {
                    movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
                }
                
                // Start recording video to a temporary file.
                let outputFileName = NSUUID().uuidString
                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
            } else {
                movieFileOutput.stopRecording()
            }
        }
    }
    
    var _supportedInterfaceOrientations: UIInterfaceOrientationMask = .all
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        get { return _supportedInterfaceOrientations }
        set { _supportedInterfaceOrientations = newValue }
    }
    
    /// - Tag: DidStartRecording
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Enable the Record button to let the user stop recording.
        DispatchQueue.main.async {
            self.recordButton.isEnabled = true
            self.recordButton.setImage(#imageLiteral(resourceName: "CaptureStop"), for: [])
        }
    }
    
    /// - Tag: DidFinishRecording
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        // Note: Because we use a unique file path for each recording, a new
        // recording won't overwrite a recording mid-save.
        func cleanup() {
            let path = outputFileURL.path
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    print("Could not remove file at url: \(outputFileURL)")
                }
            }
            
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
                
                if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
        }
        
        var success = true
        
        if error != nil {
            print("Movie file finishing error: \(String(describing: error))")
            success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }
        
        if success {
            // Check the authorization status.
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    // Save the movie file to the photo library and cleanup.
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
						
						// Specify the movie's location.
						creationRequest.location = self.locationManager.location
                    }, completionHandler: { success, error in
                        if !success {
                            print("3PTeam app couldn't save the movie to your photo library: \(String(describing: error))")
                        }
                        cleanup()
                    })
                } else {
                    cleanup()
                }
            }
        } else {
            cleanup()
        }
        
        // When recording finishes, check if the system-preferred camera
        // changed during the recording.
        sessionQueue.async {
            let systemPreferredCamera = AVCaptureDevice.systemPreferredCamera
            if self.videoDeviceInput.device != systemPreferredCamera {
                self.changeCamera(systemPreferredCamera, isUserSelection: false)
            }
        }
        
        // Enable the Camera and Record buttons to let the user switch camera
        // and start another recording.
        DispatchQueue.main.async {
            // Only enable the ability to change camera if the device has more
            // than one camera.
            self.cameraButton.isEnabled = self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
            self.recordButton.isEnabled = true
            self.captureModeControl.isEnabled = true
            self.recordButton.setImage(#imageLiteral(resourceName: "CaptureVideo"), for: [])
            self.supportedInterfaceOrientations = UIInterfaceOrientationMask.all
            // After the recording finishes, allow rotation to continue.
            self.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
    
    // MARK: KVO and Notifications
    
    private var keyValueObservations = [NSKeyValueObservation]()
    /// - Tag: ObserveInterruption
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
            
            DispatchQueue.main.async {
                // Only enable the ability to change camera if the device has
                // more than one camera.
                self.cameraButton.isEnabled = isSessionRunning && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
                self.recordButton.isEnabled = isSessionRunning && self.movieFileOutput != nil
                self.photoButton.isEnabled = isSessionRunning
                self.captureModeControl.isEnabled = isSessionRunning
            }
        }
        keyValueObservations.append(keyValueObservation)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(subjectAreaDidChange),
                                               name: .AVCaptureDeviceSubjectAreaDidChange,
                                               object: videoDeviceInput.device)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionRuntimeError),
                                               name: .AVCaptureSessionRuntimeError,
                                               object: session)
        
        // A session can only run when the app is full screen. It will be
        // interrupted in a multi-app layout, introduced in iOS 9, see also the
        // documentation of AVCaptureSessionInterruptionReason. Add observers to
        // handle these session interruptions and show a preview is paused
        // message. See `AVCaptureSessionWasInterruptedNotification` for other
        // interruption reasons.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWasInterrupted),
                                               name: .AVCaptureSessionWasInterrupted,
                                               object: session)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionInterruptionEnded),
                                               name: .AVCaptureSessionInterruptionEnded,
                                               object: session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }
    
    private var systemPreferredCameraContext = 0
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if context == &systemPreferredCameraContext {
            guard let systemPreferredCamera = change?[.newKey] as? AVCaptureDevice else { return }
            
            // Don't switch cameras if movie recording is in progress.
            if let movieFileOutput = self.movieFileOutput, movieFileOutput.isRecording {
                return
            }
            if self.videoDeviceInput.device == systemPreferredCamera {
                return
            }
            
            self.changeCamera(systemPreferredCamera, isUserSelection: false)
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    /// - Tag: HandleRuntimeError
    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        
        print("Capture session runtime error: \(error)")
        // If media services were reset, and the last start succeeded, restart
        // the session.
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
            resumeButton.isHidden = false
        }
    }
    
    /// - Tag: HandleInterruption
    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        // In some scenarios you want to enable the user to resume the session.
        // For example, if music playback is initiated from Control Center while
        // using this app, then the user can let app resume the session running,
        // which will stop music playback. Note that stopping music playback in
        // Control Center will not automatically resume the session. Also note
        // that it's not always possible to resume, see
        // `resumeInterruptedSession(_:)`.
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
            
            var showResumeButton = false
            if reason == .audioDeviceInUseByAnotherClient || reason == .videoDeviceInUseByAnotherClient {
                showResumeButton = true
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                // Fade-in a label to inform the user that the camera is
                // unavailable.
                cameraUnavailableLabel.alpha = 0
                cameraUnavailableLabel.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    self.cameraUnavailableLabel.alpha = 1
                }
            } else if reason == .videoDeviceNotAvailableDueToSystemPressure {
                print("Session stopped running due to shutdown system pressure level.")
            }
            if showResumeButton {
                // Fade-in a button to enable the user to try to resume the
                // session running.
                resumeButton.alpha = 0
                resumeButton.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    self.resumeButton.alpha = 1
                }
            }
        }
    }
    
    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
        
        if !resumeButton.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.resumeButton.alpha = 0
            }, completion: { _ in
                self.resumeButton.isHidden = true
            })
        }
        if !cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.cameraUnavailableLabel.alpha = 0
            }, completion: { _ in
                self.cameraUnavailableLabel.isHidden = true
            }
            )
        }
    }
    
    func showAlert(message: String) {
        DispatchQueue.main.async {
            //let message = NSLocalizedString(title, comment: message)
            let alertController = UIAlertController(title: "3PTeam", message: message, preferredStyle: .alert)
            
            alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                    style: .cancel,
                                                    handler: nil))
            
            self.present(alertController, animated: true, completion: nil)
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        
        var uniqueDevicePositions = [AVCaptureDevice.Position]()
        
        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }
        
        return uniqueDevicePositions.count
    }
}

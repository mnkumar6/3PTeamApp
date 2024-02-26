/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's photo capture delegate object.
*/

import AVFoundation
import Photos

class PhotoCaptureProcessor: NSObject {
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    
    private let willCapturePhotoAnimation: () -> Void
    
    lazy var context = CIContext()
    
    private let completionHandler: (PhotoCaptureProcessor) -> Void
    
    private var photoData: Data?

    // Save the location of captured photos.
    var location: CLLocation?

    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         willCapturePhotoAnimation: @escaping () -> Void,
         completionHandler: @escaping (PhotoCaptureProcessor) -> Void) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.completionHandler = completionHandler
    }
    
    private func didFinish() {
        completionHandler(self)
    }
}

/// This extension adopts all of the AVCapturePhotoCaptureDelegate protocol
/// methods.
extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
    
    /// - Tag: WillBeginCapture
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
//        if resolvedSettings.livePhotoMovieDimensions.width > 0 && resolvedSettings.livePhotoMovieDimensions.height > 0 {
//            livePhotoCaptureHandler(true)
//        }
    }
    
    /// - Tag: WillCapturePhoto
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
    }
    
    /// - Tag: DidFinishProcessingPhoto
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {

        if let error = error {
            print("Error capturing photo: \(error)")
            return
        }
        
        self.photoData = photo.fileDataRepresentation()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCapturingDeferredPhotoProxy deferredPhotoProxy: AVCaptureDeferredPhotoProxy?, error: Error?) {
        if let error = error {
            print("Error capturing deferred photo: \(error)")
            return
        }
        
        self.photoData = deferredPhotoProxy?.fileDataRepresentation()
    }
    
    /// - Tag: DidFinishCapture
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            didFinish()
            return
        }

        guard photoData != nil else {
            print("No photo data resource")
            didFinish()
            return
        }

        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    options.uniformTypeIdentifier = self.requestedPhotoSettings.processedFileType.map { $0.rawValue }
                    
                    var resourceType = PHAssetResourceType.photo
                    if  ( resolvedSettings.deferredPhotoProxyDimensions.width > 0 ) && ( resolvedSettings.deferredPhotoProxyDimensions.height > 0 ) {
                        resourceType = PHAssetResourceType.photoProxy
                    }
                    creationRequest.addResource(with: resourceType, data: self.photoData!, options: options)
                    
                    // Specify the location in which the photo was taken.
                    creationRequest.location = self.location
                    
                }, completionHandler: { _, error in
                    if let error = error {
                        print("Error occurred while saving photo to photo library: \(error)")
                    }
                    
                    self.didFinish()
                }
                )
            } else {
                self.didFinish()
            }
        }
    }
}

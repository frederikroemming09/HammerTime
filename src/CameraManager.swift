import AVFoundation
import AppKit

class CameraManager: NSObject {
    static let shared = CameraManager()
    
    var isCameraAvailable: Bool {
        return AVCaptureDevice.default(for: .video) != nil
    }
    
    private let sessionQueue = DispatchQueue(label: "com.antigravity.HammerTime.cameraSessionQueue")
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var activeCompletion: ((NSImage?) -> Void)?
    
    func checkPermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    private func setupSession(completion: @escaping (Bool) -> Void) {
        sessionQueue.async {
            if self.captureSession != nil {
                completion(true)
                return
            }
            
            let session = AVCaptureSession()
            session.sessionPreset = .photo
            
            guard let device = AVCaptureDevice.default(for: .video) else {
                print("[Camera] No default video device found")
                completion(false)
                return
            }
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    print("[Camera] Cannot add video input to session")
                    completion(false)
                    return
                }
                
                let output = AVCapturePhotoOutput()
                if session.canAddOutput(output) {
                    session.addOutput(output)
                } else {
                    print("[Camera] Cannot add photo output to session")
                    completion(false)
                    return
                }
                
                self.captureSession = session
                self.photoOutput = output
                completion(true)
            } catch {
                print("[Camera] Error setting up camera device input: \(error)")
                completion(false)
            }
        }
    }
    
    func capturePhoto(completion: @escaping (NSImage?) -> Void) {
        setupSession { success in
            guard success, let session = self.captureSession, let output = self.photoOutput else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            self.sessionQueue.async {
                self.activeCompletion = completion
                
                let sessionWasRunning = session.isRunning
                if !sessionWasRunning {
                    session.startRunning()
                    print("[Camera] Session started. Waiting 1.0s for auto-exposure warm-up...")
                }
                
                let captureBlock = {
                    let settings = AVCapturePhotoSettings()
                    output.capturePhoto(with: settings, delegate: self)
                }
                
                if !sessionWasRunning {
                    // Wait 1.0 second for camera auto-exposure and white balance to calibrate
                    self.sessionQueue.asyncAfter(deadline: .now() + 1.0, execute: captureBlock)
                } else {
                    captureBlock()
                }
            }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        sessionQueue.async {
            // Stop the capture session immediately after capture to turn off the camera LED light
            if let session = self.captureSession, session.isRunning {
                session.stopRunning()
            }
            
            DispatchQueue.main.async {
                guard error == nil,
                      let data = photo.fileDataRepresentation(),
                      let image = NSImage(data: data) else {
                    print("[Camera] Failed to convert captured photo to NSImage: \(String(describing: error))")
                    self.activeCompletion?(nil)
                    self.activeCompletion = nil
                    return
                }
                
                print("[Camera] Photo captured successfully!")
                self.activeCompletion?(image)
                self.activeCompletion = nil
            }
        }
    }
}

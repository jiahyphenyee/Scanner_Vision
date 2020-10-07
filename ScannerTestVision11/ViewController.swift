//
//  ViewController.swift
//  ScannerTestVision11
//
//  Created by Koe Jia-Yee on 7/10/20.
//  Copyright © 2020 Koe Jia-Yee. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // MARK:- Private Vars
    
    private let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    // preview the camera feed
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
    
    private var bBoxLayer = CAShapeLayer()
    
    // MARK:- Private Functions
    
    private func setCameraInput() {
        guard let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInDualCamera, .builtInWideAngleCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .back).devices.first else {
                fatalError("No back camera device found.")
        }
        
        let cameraInput = try! AVCaptureDeviceInput(device: device)
        self.captureSession.addInput(cameraInput)
    }
    
    private func showCameraFeed(){
        self.previewLayer.videoGravity = .resizeAspectFill
        self.view.layer.addSublayer(self.previewLayer)
        self.previewLayer.frame = self.view.frame
    }
    
    private func setCameraOutput() {
        self.videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA)] as [String : Any]
        self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
        self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_frame_processing_queue"))
        
        self.captureSession.addOutput(self.videoDataOutput)
        
        guard let connection = self.videoDataOutput.connections.first ,
            connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = .portrait
        
    }
    
    private func detectRectangle(in image: CVPixelBuffer) {
        let request = VNDetectRectanglesRequest(completionHandler: {
            (request: VNRequest, error: Error?) in
            
            DispatchQueue.main.async {
                guard let results = request.results as? [VNRectangleObservation] else { return }
                self.removeBoundingBoxLayer()
                
                // get first observed rectangle
                guard let rect = results.first else { return }
                
                // draw bounding box of detected rect
                self.drawBoundingBox(rect: rect)
            }
        })
        
        // set value for detected rect
        request.minimumAspectRatio = VNAspectRatio(0.3)
        request.maximumAspectRatio = VNAspectRatio(0.9)
        request.minimumSize = Float(0.3)
        request.maximumObservations = 1
        
        // create Vision detection request
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
        try? imageRequestHandler.perform([request])
    }
    
    private func createLayer(in rect: CGRect) {
        bBoxLayer = CAShapeLayer()
        bBoxLayer.frame = rect
        bBoxLayer.cornerRadius = 10
        bBoxLayer.opacity = 1
        bBoxLayer.borderColor = UIColor.systemGreen.cgColor
        bBoxLayer.borderWidth = 6.0
        previewLayer.insertSublayer(bBoxLayer, at: 1)
    }

    // MARK:- Override Functions
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setCameraInput()
        self.showCameraFeed()
        self.setCameraOutput()
    }
    
    // resize frame of the previewLayer to the real bounds of our view
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.previewLayer.frame = self.view.bounds
    }
    
    override func viewDidAppear(_ animated: Bool) {
        // start session
        self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_frame_processing_queue"))
        self.captureSession.startRunning()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        // session stopped
        self.videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
        self.captureSession.stopRunning()
    }
    
    // MARK:- Functions
    
    func captureOutput(_ output: AVCaptureOutput,didOutput sampleBuffer: CMSampleBuffer,from connection: AVCaptureConnection) {
        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            debugPrint("unable to get image from sample buffer")
            return
        }
        self.detectRectangle(in: frame)
    }
    
    func drawBoundingBox(rect: VNRectangleObservation) {
        let transform = CGAffineTransform(scaleX: 1, y: -1)
            .translatedBy(x: 0, y: -self.previewLayer.bounds.height)
        let scale = CGAffineTransform.identity.scaledBy(
            x: self.previewLayer.bounds.width, y: self.previewLayer.bounds.height)
        let bounds = rect.boundingBox.applying(scale).applying(transform)
        
        createLayer(in: bounds)
    }
    
    func removeBoundingBoxLayer() {
      bBoxLayer.removeFromSuperlayer()
    }
    
    // extract image within rectangle
    func extractImage(_ observation: VNRectangleObservation, from buffer: CVImageBuffer) -> UIImage {
        var ciImage = CIImage(cvImageBuffer: buffer)

        // scale the CGPoints of the observed rectangle in order to center them in the ciImage
        let topLeft = observation.topLeft.scaled(to: ciImage.extent.size)
        let topRight = observation.topRight.scaled(to: ciImage.extent.size)
        let bottomLeft = observation.bottomLeft.scaled(to: ciImage.extent.size)
        let bottomRight = observation.bottomRight.scaled(to: ciImage.extent.size)
        
        // pass filters to rectify image
        ciImage = ciImage.applyingFilter("CIPerspectiveCorrection",
            parameters: [
                "inputTopLeft": CIVector(cgPoint: topLeft),
                "inputTopRight": CIVector(cgPoint: topRight),
                "inputBottomLeft": CIVector(cgPoint: bottomLeft),
                "inputBottomRight": CIVector(cgPoint: bottomRight),
        ])
        
        let context = CIContext()
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        let output = UIImage(cgImage: cgImage!)
        
        return output
    }
}

extension CGPoint {
    func scaled(to size: CGSize) -> CGPoint {
        return CGPoint(x: self.x * size.width, y: self.y * size.height)
    }
}

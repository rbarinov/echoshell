//
//  QRCodeScanner.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  Handles QR code scanning using AVFoundation and Vision
//

import AVFoundation
import Vision
import UIKit

class QRCodeScanner: NSObject, ObservableObject {
    @Published var scannedConfig: TunnelConfig?
    @Published var error: String?
    
    var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var hasScanned = false // Prevent multiple scans
    
    override init() {
        super.init()
        setupCaptureSession()
    }
    
    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        
        guard let captureSession = captureSession,
              let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            error = "Camera not available"
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "qr.scanner"))
        
        if let videoOutput = videoOutput, captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
    }
    
    func startScanning() {
        guard captureSession != nil else {
            error = "Camera session not available"
            return
        }
        
        // Reset scan state completely for new scan
        hasScanned = false
        scannedConfig = nil
        error = nil
        
        print("📱 QR Scanner: Starting scan, state reset")
        
        // Request camera permission if needed
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.global(qos: .userInitiated).async {
                        self?.captureSession?.startRunning()
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.error = "Camera permission denied"
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.error = "Camera access denied. Please enable it in Settings."
            }
        @unknown default:
            DispatchQueue.main.async {
                self.error = "Camera access unknown"
            }
        }
    }
    
    func stopScanning() {
        guard let captureSession = captureSession else { return }
        
        // Stop on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }
}

extension QRCodeScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Stop processing if we've already scanned successfully
        guard !hasScanned else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            // Stop processing if we've already scanned successfully
            guard let self = self, !self.hasScanned else { return }
            
            guard let results = request.results as? [VNBarcodeObservation],
                  let firstCode = results.first,
                  let payload = firstCode.payloadStringValue else {
                return
            }
            
            // Parse JSON from QR code
            if let data = payload.data(using: .utf8),
               let config = try? JSONDecoder().decode(TunnelConfig.self, from: data) {
                // Mark as scanned immediately to prevent duplicate processing
                self.hasScanned = true
                
                DispatchQueue.main.async {
                    // Stop scanning immediately
                    self.stopScanning()
                    
                    // Provide haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    
                    // Set the config (this will trigger the onChange in QRScannerView)
                    self.scannedConfig = config
                }
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}

//
//  QRScannerView.swift
//  EchoShell
//
//  Created for Voice-Controlled Terminal Management System
//  UI for scanning QR codes from laptop app
//

import SwiftUI
import AVFoundation

struct QRScannerView: View {
    @StateObject private var scanner = QRCodeScanner()
    @Environment(\.dismiss) var dismiss
    @Binding var scannedConfig: TunnelConfig?
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(scanner: scanner)
                .edgesIgnoringSafeArea(.all)
            
            // Overlay with scanning frame
            VStack {
                Text("Scan QR Code from Laptop")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding(.top, 50)
                
                Spacer()
                
                // Scanning frame
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: 250, height: 250)
                
                Spacer()
                
                // Cancel button
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            scanner.startScanning()
        }
        .onDisappear {
            // Stop scanning when view disappears
            scanner.stopScanning()
        }
        .onChange(of: scanner.scannedConfig) { oldValue, newValue in
            if let config = newValue {
                // Update binding
                scannedConfig = config
                
                // Dismiss immediately after a brief delay to show success feedback
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    dismiss()
                }
            }
        }
        .alert("QR Scan Error", isPresented: .constant(scanner.error != nil)) {
            Button("OK") {
                scanner.error = nil
            }
        } message: {
            Text(scanner.error ?? "Unknown error")
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let scanner: QRCodeScanner
    
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.setupPreviewLayer(scanner: scanner)
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.updatePreviewFrame()
    }
}

class CameraPreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private weak var scanner: QRCodeScanner?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupPreviewLayer(scanner: QRCodeScanner) {
        self.scanner = scanner
        
        guard let captureSession = scanner.captureSession else {
            return
        }
        
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        self.previewLayer = layer
        
        // Set initial frame
        updatePreviewFrame()
    }
    
    func updatePreviewFrame() {
        guard let previewLayer = previewLayer else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updatePreviewFrame()
    }
}

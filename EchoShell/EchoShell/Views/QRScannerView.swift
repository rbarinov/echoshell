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
            scanner.stopScanning()
        }
        .onChange(of: scanner.scannedConfig) { oldValue, newValue in
            if let config = newValue {
                scannedConfig = config
                dismiss()
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
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        
        guard let captureSession = scanner.captureSession else {
            return view
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}

//
//  ViewController.swift
//  ExampleOfiOSLiDAR
//
//  Created by TokyoYoshida on 2021/01/07.
//  Modified by Sergei Kazakov on 2024/08/21
//

import RealityKit
import ARKit
import ARCapture
import os

class DepthMapViewController: UIViewController, ARSessionDelegate {
    
    @IBOutlet var arView: ARSCNView!
    @IBOutlet weak var imageView: UIImageView!
    
    private var tapLocation: CGPoint = CGPoint(x: 0, y: 0)
    
    private var recordStarted: Bool = false;
    private var showDepth: Bool = false;
    
    private var capture: ARCapture?
    private var renderer: SCNRenderer?
    
    @IBOutlet var backButton: UIButton!
    @IBOutlet var recordButton: UIButton!
    @IBOutlet var showDepthButton: UIButton!
    
    var orientation: UIInterfaceOrientation {
        guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else {
            fatalError()
        }
        return orientation
    }
    @IBOutlet weak var imageViewHeight: NSLayoutConstraint!
    lazy var imageViewSize: CGSize = {
        CGSize(width: view.bounds.size.width, height: imageViewHeight.constant)
    }()
    
    lazy var infoLabel: UILabel = {
        let label = UILabel(frame: CGRect.zero);
        label.textAlignment = .center;
        label.backgroundColor = .clear;
        return label;
    }()

    override func viewDidLoad() {
        navigationController?.setNavigationBarHidden(true, animated: true)
        
        func buildConfigure() -> ARWorldTrackingConfiguration {
            let configuration = ARWorldTrackingConfiguration()

            configuration.environmentTexturing = .automatic
            if type(of: configuration).supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics = .sceneDepth
                //configuration.frameSemantics = .smoothedSceneDepth
            }

            return configuration
        }
        super.viewDidLoad()
        
        arView.session.delegate = self
        let configuration = buildConfigure()
        arView.session.run(configuration)
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapRecognizer.numberOfTapsRequired = 1
        arView.addGestureRecognizer(tapRecognizer)
        
        view.addSubview(infoLabel)
        
        capture = ARCapture(view: arView)
        capture?.recordAudio(enable: false)
        
        recordStarted = false
        
        view.backgroundColor = .black
        
        imageView.isHidden = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.capture?.prepare({ (status) in
                os_log("Capture prepared: %@", log: .default, type: .default, String(status))
            })
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        infoLabel.frame = CGRect(x: 0, y: 150, width: view.bounds.width, height: 64)
        if (orientation.isLandscape) {
            let width = CGFloat(Int(view.bounds.height * (256 / 192)))
            arView.frame = CGRect(x: (view.bounds.width - width) / 2, y: 0, width: width, height: view.bounds.height)
            imageView.frame = CGRect(x: (view.bounds.width - width) / 2, y: 0, width: width, height: view.bounds.height)
        } else {
            let height = CGFloat(Int(view.bounds.width / (192 / 256)))
            arView.frame = CGRect(x: 0, y: (view.bounds.height - height) / 2, width: view.bounds.width, height: height)
            imageView.frame = CGRect(x: 0, y: (view.bounds.height - height) / 2, width: view.bounds.width, height: height)
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if (showDepth) {
            imageView.image = (session.currentFrame?.depthMapTransformedImage(orientation: orientation, viewPort: self.imageView.bounds))?.alpha(0.7)
        }
        
        if (tapLocation.x > 0 && tapLocation.y > 0) {
            let sceneDepth = session.currentFrame?.sceneDepth;
            let tapPositionX: Float = Float(tapLocation.x / arView.bounds.width)
            let tapPositionY: Float = Float(tapLocation.y / arView.bounds.height)
            let sample = sceneDepth?.depthMap.sample(location: [tapPositionX, tapPositionY])
            if (sample != nil) {
                infoLabel.text = String(sample![0])
            } else {
                infoLabel.text = "NOT FOUND"
            }
            
            tapLocation = CGPoint(x: 0, y: 0)
        }
    }
    
    @objc func handleTap(sender: UITapGestureRecognizer) {
        tapLocation = sender.location(in: arView)
    }
    
    private func finishRecording(status: Bool, depthUrl: URL?) {
        os_log("Video exported: %@", log: .default, type: .default, String(status))
        DispatchQueue.main.async {
            if let depthUrl = depthUrl {
                let vc = UIActivityViewController(activityItems: [depthUrl], applicationActivities: nil)
                vc.popoverPresentationController?.sourceView = self.recordButton
                self.present(vc, animated: true, completion: nil)
            }
        }
    }
    
    @IBAction func tappedShowDepthButton(_ sender: UIButton) {
        if (showDepth) {
            showDepthButton.setTitle("Show Depth", for: .normal)
            imageView.isHidden = true
        } else {
            showDepthButton.setTitle("Hide Depth", for: .normal)
            imageView.isHidden = false
        }
        showDepth = !showDepth
    }
    
    @IBAction func tappedBackButton(_ sender: UIButton) {
        if (recordStarted) {
            capture?.stop(finishRecording)
            backButton.setTitle("RECORD", for: .normal)
            sender.setTitleColor(.blue, for: .normal)
        }
        navigationController?.popViewController(animated: true)
    }
    
    @IBAction func startRecord(_ sender: UIButton) {
        if (recordStarted) {
            capture?.stop(finishRecording)
            sender.setTitle("RECORD", for: .normal)
            sender.setTitleColor(.blue, for: .normal)
            recordStarted = false
        } else {
            capture?.start(captureType: ARFrameGenerator.CaptureType.renderOriginal, captureDepth: ARFrameGenerator.CaptureDepth.yes)
            sender.setTitle("STOP", for: .normal)
            sender.setTitleColor(.red, for: .normal)
            recordStarted = true
        }
    }
}

extension UIImage {
    func alpha(_ value:CGFloat) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(at: CGPoint.zero, blendMode: .normal, alpha: value)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage!
    }
}

extension CVPixelBuffer {
    // Requires CVPixelBufferLockBaseAddress(_:_:) first
    var data: UnsafeRawBufferPointer? {
        let size = CVPixelBufferGetDataSize(self)
        return .init(start: CVPixelBufferGetBaseAddress(self), count: size) }
    var pixelSize: simd_int2 { simd_int2(Int32(width), Int32(height)) }
    var width: Int { CVPixelBufferGetWidth(self) }
    var height: Int { CVPixelBufferGetHeight(self) }
    func sample(location: simd_float2) -> simd_float4? {
        let pixelSize = self.pixelSize
        guard pixelSize.x > 0 && pixelSize.y > 0 else { return nil }
        guard CVPixelBufferLockBaseAddress(self, .readOnly) == noErr else { return nil }
        guard let data = data else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }
        let pix = location * simd_float2(pixelSize)
        let clamped = clamp(simd_int2(pix), min: .zero, max: pixelSize &- simd_int2(1,1))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(self)
        let row = Int(clamped.y)
        let column = Int(clamped.x)
        let rowPtr = data.baseAddress! + row * bytesPerRow
        switch CVPixelBufferGetPixelFormatType(self) {
        case kCVPixelFormatType_DepthFloat32:
            // Bind the row to the right type
            let typed = rowPtr.assumingMemoryBound(to: Float.self)
            return .init(typed[column], 0, 0, 0)
        case kCVPixelFormatType_32BGRA:
            // Bind the row to the right type
            let typed = rowPtr.assumingMemoryBound(to: UInt8.self)
            return .init(Float(typed[column]) / Float(UInt8.max), 0, 0, 0)
        default:
            return nil
        }
    }
}

//
//  ExportViewController.swift
//  ExampleOfiOSLiDAR
//
//  Created by TokyoYoshida on 2021/02/10.
//  Modified by Sergei Kazakov on 2024/06/07
//

import UIKit
import RealityKit
import ARKit
import os

class ExportViewController: UIViewController, ARSessionDelegate {
    
    @IBOutlet var arView: ARView!
    var worldAnchors: [AnchorEntity] = []
    
    var topLocation: CGPoint! = nil
    
    var checkTimes = 10;
    
    var averageHeight: Float = 0;
    
    var isRunning: Bool = false;
    
    let request = VNDetectBarcodesRequest()
    let requestQueue = DispatchQueue(label: "Request Queue")
    
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
        label.backgroundColor = UIColor(white: 1, alpha: 0);
        return label;
    }()

    override func viewDidLoad() {
        func setARViewOptions() {
            arView.debugOptions.insert(.showSceneUnderstanding)
            arView.environment.sceneUnderstanding.options = []
            //arView.environment.sceneUnderstanding.options.insert(.occlusion)
            arView.environment.sceneUnderstanding.options.insert(.physics)
            
            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tapRecognizer.numberOfTapsRequired = 1
            arView.addGestureRecognizer(tapRecognizer)
        }
        func buildWorldConfigure() -> ARWorldTrackingConfiguration {
            let configuration = ARWorldTrackingConfiguration()

            //configuration.environmentTexturing = .automatic
            configuration.sceneReconstruction = .mesh
            if type(of: configuration).supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics = .sceneDepth
            }

            return configuration
        }
        func initARView() {
            setARViewOptions()
            let configuration = buildWorldConfigure()
            arView.session.run(configuration)
        }
        arView.session.delegate = self;
        super.viewDidLoad();
        initARView();
        view.addSubview(infoLabel);
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        infoLabel.frame = CGRect(x: 0, y: 150, width: view.bounds.width, height: 64)
        if (orientation.isLandscape) {
            let width = CGFloat(Int(view.bounds.width * (192 / view.bounds.height)))
            arView.frame = CGRect(x: (view.bounds.width - width) / 2, y: 0, width: width, height: view.bounds.height)
        } else {
            let height = CGFloat(Int(view.bounds.height * (256 / view.bounds.width)))
            arView.frame = CGRect(x: 0, y: (view.bounds.height - height) / 2, width: view.bounds.width, height: height)
        }
    }
    
    func buildBall(radius: Float, color: UIColor, position: SIMD3<Float>) -> AnchorEntity {
        let sphere = ModelEntity(mesh: .generateSphere(radius: radius), materials: [SimpleMaterial(color: color, isMetallic: true)]);
        let ballAnchor = AnchorEntity(world: position);
        //ballAnchor.name = anchorName
        ballAnchor.addChild(sphere);
        return ballAnchor;
    }
    
    @objc func handleTap(sender: UITapGestureRecognizer) {
        for anchor in worldAnchors {
            worldAnchors.removeFirst()
            arView.scene.removeAnchor(anchor);
        }
        
        let height = detectHeight();
        if let height = height {
            infoLabel.text = String(height);
        }
    }
    
    func detectHeight() -> Float? {
        let offset = arView.bounds.width / 6;
        var centerLeftLocation = CGPoint(x:(arView.bounds.width / 2) - offset, y:arView.bounds.height / 2);
        var ray = arView.ray(through: centerLeftLocation);
        // Looking for closest point (body)
        var closestDistance: Float = 9999;
        var closestPoint: SIMD3<Float>? = nil;
        while (true) {
            if (centerLeftLocation.x >= (arView.bounds.width / 2) + offset) {
                break;
            }
            ray = arView.ray(through: centerLeftLocation);
            let castHits = arView.scene.raycast(
                origin: ray!.origin,
                direction: ray!.direction,
                length: 1000,
                query: .nearest
            )
            guard let hitTest: CollisionCastHit = castHits.first else {
                centerLeftLocation.x += 1;
                continue;
            }
            if (hitTest.distance < closestDistance) {
                closestDistance = hitTest.distance;
                closestPoint = hitTest.position;
            }
            centerLeftLocation.x += 1;
        }
        if (closestPoint == nil) {
            return nil;
        }
        
        // Looking for body
        var leftRightDirection = "right";
        var upDownDirection = "up";
        var tempPoint = closestPoint!;
        let confidence: Float = 0.03;
        let maxHorizontalDistance: Float = 1 / 2;
        let maxVertialDistance: Float = 4 / 2;
        var maxVerticalPosition: Float = -9999;
        var minVerticalPosition: Float = 9999;
        while (true) {
            if (leftRightDirection == "right") {
                tempPoint.x += confidence;
                if (tempPoint.x > closestPoint!.x + maxHorizontalDistance) {
                    leftRightDirection = "left";
                    tempPoint.x = closestPoint!.x;
                }
            } else if (leftRightDirection == "left") {
                tempPoint.x -= confidence;
                if (upDownDirection == "up" && tempPoint.y > closestPoint!.y + maxVertialDistance) {
                    leftRightDirection = "right";
                    upDownDirection = "down";
                    tempPoint.x = closestPoint!.x;
                    tempPoint.y = closestPoint!.y - confidence;
                } else if (upDownDirection == "down" && tempPoint.y < closestPoint!.y - maxVertialDistance) {
                    break;
                } else if (tempPoint.x < closestPoint!.x - maxHorizontalDistance) {
                    leftRightDirection = "right";
                    tempPoint.x = closestPoint!.x;
                    if (upDownDirection == "up") {
                        tempPoint.y += confidence;
                    } else {
                        tempPoint.y -= confidence;
                    }
                }
            }
            let castHits = arView.scene.raycast(
                origin: ray!.origin,
                direction: tempPoint,
                length: 1000,
                query: .nearest
            )
            guard let hitTest: CollisionCastHit = castHits.first else {
                continue;
            }
            if (closestPoint!.z < hitTest.position.z + 0.2 && closestPoint!.z > hitTest.position.z - 0.2) {
                
                let ballAnchor = buildBall(radius: 0.02, color: .red, position: hitTest.position);
                arView.scene.addAnchor(ballAnchor);
                worldAnchors.append(ballAnchor);
                
                if (hitTest.position.y > maxVerticalPosition) {
                    maxVerticalPosition = hitTest.position.y;
                }
                if (hitTest.position.y < minVerticalPosition) {
                    minVerticalPosition = hitTest.position.y;
                }
            }
        }
        return (maxVerticalPosition - minVerticalPosition) + 0.03;
    }

    @IBAction func tappedExportButton(_ sender: UIButton) {
        guard let camera = arView.session.currentFrame?.camera else {return}

        func convertToAsset(meshAnchors: [ARMeshAnchor]) -> MDLAsset? {
            guard let device = MTLCreateSystemDefaultDevice() else {return nil}

            let asset = MDLAsset()

            for anchor in meshAnchors {
                let mdlMesh = anchor.geometry.toMDLMesh(device: device, camera: camera, modelMatrix: anchor.transform)
                asset.add(mdlMesh)
            }
            
            return asset
        }
        func export(asset: MDLAsset) throws -> URL {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let url = directory.appendingPathComponent("scaned.obj")

            try asset.export(to: url)

            return url
        }
        func share(url: URL) {
            let vc = UIActivityViewController(activityItems: [url],applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = sender
            self.present(vc, animated: true, completion: nil)
        }
        if let meshAnchors = arView.session.currentFrame?.anchors.compactMap({ $0 as? ARMeshAnchor }),
           let asset = convertToAsset(meshAnchors: meshAnchors) {
            do {
                let url = try export(asset: asset)
                share(url: url)
            } catch {
                print("export error")
            }
        }
    }
}

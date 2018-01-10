//
//  ViewController.swift
//  faceIT
//
//  Created by Michael Ruhl on 07.07.17.
//  Copyright © 2017 NovaTec GmbH. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision

import RxSwift
import RxCocoa
import Async
import PKHUD

class ViewController: UIViewController, ARSCNViewDelegate {
    
    @IBOutlet var sceneView: ARSCNView!
    
    var 👜 = DisposeBag()
    
    var faces: [Face] = []
    var face: Face?
    
    var bounds: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
        bounds = sceneView.bounds
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration)
        
        Observable<Int>.interval(0.6, scheduler: SerialDispatchQueueScheduler(qos: .default))
            .subscribeOn(SerialDispatchQueueScheduler(qos: .background))
            .concatMap{ _ in  self.faceObservation() }
            .flatMap{ Observable.from($0)}
            .subscribe { [unowned self] event in
                guard let element = event.element else {
                    print("No element available")
                    return
                }
                self.updateNode(observation: element.observation, position: element.position, frame: element.frame)
            }.disposed(by: 👜)
        
        
        Observable<Int>.interval(1.0, scheduler: SerialDispatchQueueScheduler(qos: .default))
            .subscribeOn(SerialDispatchQueueScheduler(qos: .background))
            .subscribe { [unowned self] _ in
                
                self.faces.filter{ $0.updated.isAfter(seconds: 1.5) && !$0.hidden }.forEach{ face in
                    print("Hide node: \(face.name)")
                    Async.main { face.node.hide() }
                }
            }.disposed(by: 👜)
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {

        switch camera.trackingState {
        case .limited(.initializing):
            PKHUD.sharedHUD.contentView = PKHUDProgressView(title: "Initializing", subtitle: nil)
            PKHUD.sharedHUD.show()
        case .notAvailable:
            print("Not available")
        default:
            PKHUD.sharedHUD.hide()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        👜 = DisposeBag()
        sceneView.session.pause()
    }
    
    private func faceObservation() -> Observable<[(observation: VNFaceObservation, position: SCNVector3, frame: ARFrame)]> {
        return Observable<[(observation: VNFaceObservation, position: SCNVector3, frame: ARFrame)]>.create{ observer in
            guard let frame = self.sceneView.session.currentFrame else {
                print("No frame available")
                observer.onCompleted()
                return Disposables.create()
            }

            // Create and rotate image
            let image = CIImage.init(cvPixelBuffer: frame.capturedImage).rotate
            
            let facesRequest = VNDetectFaceRectanglesRequest { request, error in
                guard error == nil else {
                    print("Face request error: \(error!.localizedDescription)")
                    observer.onCompleted()
                    return
                }
                
                guard let observations = request.results as? [VNFaceObservation] else {
                    print("No face observations")
                    observer.onCompleted()
                    return
                }
                
                // Map response
                let response = observations.map({ (face) -> (observation: VNFaceObservation, position: SCNVector3, frame: ARFrame) in
                    
                    // Determine position of the face
                    let boundingBox = self.transformBoundingBox(face.boundingBox)
                    let worldCoord = self.normalizeWorldCoord(boundingBox)
                    
                    return (observation: face, position: worldCoord!, frame: frame)
                })
                observer.onNext(response)
                observer.onCompleted()
                
            }
            try? VNImageRequestHandler(ciImage: image).perform([facesRequest])
            
            return Disposables.create()
        }
    }
    
    private func updateNode(observation: VNFaceObservation, position: SCNVector3, frame: ARFrame) {
        
//        guard let person = observations.first else {
//            print("No classification found")
//            return
//        }
        
//        let second = classes[1]
//        let name = person.identifier
//        print("""
//            FIRST
//            confidence: \(person.confidence) for \(person.identifier)
//            SECOND
//            confidence: \(second.confidence) for \(second.identifier)
//
//            """)
//        if person.confidence < 0.60 || person.identifier == "unknown" {
//            print("not so sure")
//            return
//        }
//
//        // Filter for existent face
//        let results = self.faces.filter{ $0.name == name && $0.timestamp != frame.timestamp }
//            .sorted{ $0.node.position.distance(toVector: position) < $1.node.position.distance(toVector: position) }
        
        // Create new face
//        guard let existentFace = results.first else {
        if self.face == nil {
            let node = SCNNode.init(withText: "Ari", position: position)
            
            Async.main {
                self.sceneView.scene.rootNode.addChildNode(node)
                node.show()
                
            }
            self.face = Face.init(name: "Ari", node: node, timestamp: frame.timestamp)
//            self.faces.append(face)
//            return
        }
        
        // Update existent face
        Async.main {
            
            // Filter for face that's already displayed
            if self.face != nil {

                let distance = self.face!.node.position.distance(toVector: position)
                if(distance >= 0.03 ) {
                    self.face!.node.move(position)
                }
                self.face!.timestamp = frame.timestamp

            } else {
                self.face!.node.position = position
                self.face!.node.show()
                self.face!.timestamp = frame.timestamp
            }
        }
    }

    /// In order to get stable vectors, we determine multiple coordinates within an interval.
    ///
    /// - Parameters:
    ///   - boundingBox: Rect of the face on the screen
    /// - Returns: the normalized vector
    private func normalizeWorldCoord(_ boundingBox: CGRect) -> SCNVector3? {
        
        var array: [SCNVector3] = []
        Array(0...2).forEach{_ in
            if let position = determineWorldCoord(boundingBox) {
                array.append(position)
            }
            usleep(12000) // .012 seconds
        }

        if array.isEmpty {
            return nil
        }
        
        return SCNVector3.center(array)
    }
    
    
    /// Determine the vector from the position on the screen.
    ///
    /// - Parameter boundingBox: Rect of the face on the screen
    /// - Returns: the vector in the sceneView
    private func determineWorldCoord(_ boundingBox: CGRect) -> SCNVector3? {
        let arHitTestResults = sceneView.hitTest(CGPoint(x: boundingBox.midX, y: boundingBox.midY), types: [.featurePoint])
        
        // Filter results that are to close
        if let closestResult = arHitTestResults.filter({ $0.distance > 0.10 }).first {
//            print("vector distance: \(closestResult.distance)")
            return SCNVector3.positionFromTransform(closestResult.worldTransform)
        }
        return nil
    }
    
    
    /// Transform bounding box according to device orientation
    ///
    /// - Parameter boundingBox: of the face
    /// - Returns: transformed bounding box
    private func transformBoundingBox(_ boundingBox: CGRect) -> CGRect {
        var size: CGSize
        var origin: CGPoint
        switch UIDevice.current.orientation {
        case .landscapeLeft, .landscapeRight:
            size = CGSize(width: boundingBox.width * bounds.height,
                          height: boundingBox.height * bounds.width)
        default:
            size = CGSize(width: boundingBox.width * bounds.width,
                          height: boundingBox.height * bounds.height)
        }
        
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            origin = CGPoint(x: boundingBox.minY * bounds.width,
                             y: boundingBox.minX * bounds.height)
        case .landscapeRight:
            origin = CGPoint(x: (1 - boundingBox.maxY) * bounds.width,
                             y: (1 - boundingBox.maxX) * bounds.height)
        case .portraitUpsideDown:
            origin = CGPoint(x: (1 - boundingBox.maxX) * bounds.width,
                             y: boundingBox.minY * bounds.height)
        default:
            origin = CGPoint(x: boundingBox.minX * bounds.width,
                             y: (1 - boundingBox.maxY) * bounds.height)
        }
        
        return CGRect(origin: origin, size: size)
    }
}

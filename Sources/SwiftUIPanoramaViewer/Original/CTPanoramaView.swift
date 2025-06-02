//
//  CTPanoramaView
//  CTPanoramaView
//
//  Created by Cihan Tek on 11/10/16.
//  Copyright © 2016 Home. All rights reserved.
//

import UIKit
import SceneKit
import CoreMotion
import ImageIO
import OSLog
import SpriteKit

public enum CTPanoramaControlMethod: Int {
	case motion
	case touch
	case both
}

public class CTPanoramaView: UIView, UIGestureRecognizerDelegate {

    public typealias MovementHandler = ((_ rotationAngle: CGFloat, _ fieldOfViewAngle: CGFloat) -> Void)
    public typealias TapHandler = ((CLLocationDirection) -> Void)

	public enum AnimateOption {
		case none
		case fade(duration: TimeInterval)
	}

	// MARK: Public properties

	public var movementHandler: MovementHandler?
    public var tapHandler: TapHandler?

	public var panSpeed = CGPoint(x: 0.4, y: 0.4)
    public var cameraStartAngle: CLLocationDirection = .pi

    public var imageRotationAngle: Float = .pi {
		didSet {
			geometryNode.rotation = SCNQuaternion(0, 1, 0, imageRotationAngle)
		}
	}

	public var cameraAngle: CGFloat {
		let quaternion = self.cameraNode.orientation
		// Convert quaternion to Euler angles (in radians)
		let yaw = atan2(2 * (quaternion.y * quaternion.w - quaternion.x * quaternion.z),
						1 - 2 * (quaternion.y * quaternion.y + quaternion.z * quaternion.z))

		return CGFloat(-yaw)
	}

	public var minFoV: CGFloat = 40
	public var maxFoV: CGFloat = 120

	private(set) var image: UIImage?

	public var controlMethod: CTPanoramaControlMethod = .touch {
		didSet {
            self.switchControlMethod(to: self.controlMethod)
            self.resetCameraAngles();
		}
	}

	// MARK: Overriding

	public override var backgroundColor: UIColor? {
		didSet {
            self.sceneView.backgroundColor = self.backgroundColor
		}
	}

	// MARK: Private properties

    private let rendererEventTracker = DebugEventTracker(category: "Renderer", name: "CTPanoramaView Lifecycle")
	private let MaxPanGestureRotation: Float = GLKMathDegreesToRadians(360)
	private let radius: CGFloat = 10
	private let sceneView = SCNView()
	private let scene = SCNScene()
	private let motionManager = CMMotionManager()
	private var geometryNode: Node!
	private var prevLocation = CGPoint.zero
	private var prevRotation = CGFloat.zero
	private var prevBounds = CGRect.zero

	// Parameters used by the .both method
	private var totalX = Float.zero
	private var totalY = Float.zero

	private var motionPaused = false

	private lazy var cameraNode: Node = {
        let node = Node(role: .camera)
		let camera = SCNCamera()
		node.camera = camera
		return node
	}()

	private lazy var motionQueue: OperationQueue = {
		let queue = OperationQueue()
		queue.qualityOfService = .userInteractive
		return queue
	}()

	private lazy var fovHeight: CGFloat = {
		return tan(self.yFov/2 * .pi / 180.0) * 2 * self.radius
	}()

	private var pinchStartScale: CGFloat = 0.0

	private var xFov: CGFloat {
        return self.yFov * self.bounds.width / self.bounds.height
	}

	private var yFov: CGFloat {
		get {
            return self.cameraNode.camera?.fieldOfView ?? 0
		}
		set {
            self.cameraNode.camera?.fieldOfView = newValue
		}
	}
    
    private var horizontalFieldOfView: Float {
        let verticalFieldOfViewInRadians = (cameraNode.camera?.fieldOfView ?? 0) * .pi / 180
        let aspectRatio = bounds.width / bounds.height
        let horizontalFieldOfViewInRadians = 2 * atan(tan(verticalFieldOfViewInRadians / 2) * aspectRatio)
        return Float(horizontalFieldOfViewInRadians * 180 / .pi)
    }

	// MARK: Class lifecycle methods

	public required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
        self.commonInit()
	}

	public override init(frame: CGRect) {
		super.init(frame: frame)
        self.commonInit()
	}

	deinit {
        self.rendererEventTracker.trackEnd(message: "deinit")

        if self.motionManager.isDeviceMotionActive {
            self.motionManager.stopDeviceMotionUpdates()
		}
	}

	// MARK: - Override

	public override func layoutSubviews() {
		super.layoutSubviews()
        if self.bounds.size.width != self.prevBounds.size.width || self.bounds.size.height != self.prevBounds.size.height {
            self.sceneView.setNeedsDisplay()
            self.reportMovement(CGFloat(-self.cameraNode.eulerAngles.y), self.xFov.toRadians(), callHandler: false)
		}
	}

	public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		// do not mix pan gestures with the others
		if (gestureRecognizer is UIPanGestureRecognizer) || (otherGestureRecognizer is UIPanGestureRecognizer) {
			return false;
		}
		return true
	}

	// MARK: Public methods

	public func resetCameraAngles() {
        self.yFov = 60
        self.cameraNode.eulerAngles = SCNVector3Make(0, Float(self.cameraStartAngle), 0)
        self.totalX = Float.zero
        self.totalY = Float.zero
        self.reportMovement(CGFloat(self.cameraStartAngle), self.xFov.toRadians(), callHandler: false)
	}

    public func transition(to image: UIImage, angle: Float, animation: AnimateOption = .fade(duration: 0.5), description: String? = nil, completion: (()->Void)? = nil) {
        defer {
            self.image = image
        }

        let transitionEventTracker = DebugEventTracker(category: "Transition", name: "Transition to Image")
        transitionEventTracker.trackBegin(message: description)

        let oldValue = self.geometryNode.geometry?.firstMaterial?.value(forKey: "newTexture")
        let newProperty = SCNMaterialProperty(contents: image)

        let material = SCNMaterial()
        material.isDoubleSided = false
        material.cullMode = .front
        material.setValue(oldValue, forKey: "oldTexture")
        material.setValue(newProperty, forKey: "newTexture")
        material.setValue(0.0, forKey: "blendFactor")

        // Shader modifier for texture blending
        material.shaderModifiers = [
            .fragment: """
            uniform sampler2D oldTexture;
            uniform sampler2D newTexture;
            uniform float blendFactor;
            uniform float rotation; // in radians

            vec2 flippedTexcoord = vec2(1.0 - _surface.diffuseTexcoord.x, _surface.diffuseTexcoord.y);
            
            // Adjust texture coordinate for horizontal rotation
            float u = fract(flippedTexcoord.x + rotation / (2.0 * 3.1415926)); // Normalize radians to [0,1)
            vec2 rotatedTexcoord = vec2(u, flippedTexcoord.y);

            vec4 oldColor = texture2D(oldTexture, rotatedTexcoord);
            vec4 newColor = texture2D(newTexture, rotatedTexcoord);
            _output.color = mix(oldColor, newColor, blendFactor);
            """
        ]
        self.geometryNode.geometry?.firstMaterial = material

        // Animate the blend
        SCNTransaction.begin()
        SCNTransaction.completionBlock = {
            transitionEventTracker.trackEnd(message: description)
            self.geometryNode.accessibilityLabel = description
            self.reportMovement(CGFloat(-self.cameraNode.eulerAngles.y), self.xFov.toRadians(), callHandler: true)
        }

        switch animation {
        case .none:
            SCNTransaction.disableActions = true
        case .fade(let duration):
            SCNTransaction.animationDuration = duration
        }

        material.setValue(1.0, forKey: "blendFactor")
        SCNTransaction.commit()
	}

	public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {      
		guard let touchLocation = touches.first?.location(in: sceneView) else { return }

        Logger.panoramaViewer.info("touch ended: \(touchLocation.debugDescription)")
        let tapIndicator = TapIndicator()
		self.addSubview(tapIndicator)
		tapIndicator.animateCircles(center: touchLocation)

        if let localSphereCoordinates = sceneView.hitTest(
            touchLocation, options: nil
        ).first?.localCoordinates {
            let widthPercentage = 0.5 + (atan2(localSphereCoordinates.z, localSphereCoordinates.x) / (2 * .pi))
            let angle = ((widthPercentage * 360) + 90).normalizeAngle() // the image starts before 90 degrees, so we add it back
            Logger.panoramaViewer.notice("tap angle is: \(angle)")
            self.tapHandler?(CLLocationDirection(angle))
        }
	}

    public func cleanup() {
        self.scene.rootNode.enumerateChildNodes { node, _ in
            node.removeAllAnimations()
            node.removeAllActions()
            node.removeFromParentNode()
        }

        self.sceneView.scene = nil
    }
}

// MARK: - Private

private extension CTPanoramaView {

	func commonInit() {
        self.rendererEventTracker.trackBegin(message: "init")

        self.add(view: self.sceneView)

        self.scene.rootNode.addChildNode(self.cameraNode)
        self.sceneView.scene = self.scene
        self.sceneView.backgroundColor = self.backgroundColor
        self.sceneView.accessibilityTraits = .image

        let sphere = SCNSphere(radius: self.radius)
        sphere.segmentCount = 360
        self.geometryNode = Node(role: .sphere)
        self.geometryNode.geometry = sphere
        self.scene.rootNode.addChildNode(self.geometryNode)

        let image = UIColor.black.render(in: CGSize(width: 100, height: 50))
        let newProperty = SCNMaterialProperty(contents: image)

        let material = SCNMaterial()
        material.setValue(newProperty, forKey: "newTexture")
        sphere.firstMaterial = material

        self.switchControlMethod(to: self.controlMethod)
	}

	// MARK: Configuration helper methods

	func startMotionUpdates(){
        guard self.motionManager.isDeviceMotionAvailable else {return}
        self.motionManager.deviceMotionUpdateInterval = 0.015

        self.motionPaused = false
        self.motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: self.motionQueue, withHandler: { [weak self] motionData, error in
			guard let panoramaView = self else {return}
			guard !panoramaView.motionPaused else {return}

			guard (panoramaView.controlMethod == .motion || panoramaView.controlMethod == .both) else {return}

			guard let motionData = motionData else {
                Logger.panoramaViewer.error("\(String(describing: error?.localizedDescription))")
				panoramaView.motionManager.stopDeviceMotionUpdates()
				return
			}

            DispatchQueue.main.async {
                // Use quaternions when in spherical mode to prevent gimbal lock
                var orientation = motionData.orientation()

                // Represent the orientation as a GLKQuaternion
                if(panoramaView.controlMethod == .both){

                    // same code as pan rotation
                    // but with our total accumulated
                    // movements

                    var glQuaternion = GLKQuaternionMake(orientation.x, orientation.y, orientation.z, orientation.w)

                    let xMultiplier = GLKQuaternionMakeWithAngleAndAxis(panoramaView.totalX, 1, 0, 0)
                    glQuaternion = GLKQuaternionMultiply(glQuaternion, xMultiplier)

                    let yMultiplier = GLKQuaternionMakeWithAngleAndAxis(panoramaView.totalY, 0, 1, 0)
                    glQuaternion = GLKQuaternionMultiply(yMultiplier, glQuaternion)

                    orientation = SCNQuaternion(x: glQuaternion.x, y: glQuaternion.y, z: glQuaternion.z, w: glQuaternion.w)

                }
                panoramaView.cameraNode.orientation = orientation
				panoramaView.reportMovement(CGFloat(-panoramaView.cameraNode.eulerAngles.y), panoramaView.xFov.toRadians())
			}
		})
	}

	func switchControlMethod(to method: CTPanoramaControlMethod) {
        self.sceneView.gestureRecognizers?.removeAll()

		if method == .touch {
			let panGestureRec = UIPanGestureRecognizer(target: self, action: #selector(handlePan(panRec:)))
            self.sceneView.addGestureRecognizer(panGestureRec)

			let pinchRec = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(pinchRec:)))
            self.sceneView.addGestureRecognizer(pinchRec)

			let rotateRec = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(rotRec:)))
            self.sceneView.addGestureRecognizer(rotateRec)

			pinchRec.delegate = self
			rotateRec.delegate = self

            if self.motionManager.isDeviceMotionActive {
                self.motionManager.stopDeviceMotionUpdates()
			}
		}
		else {
			if method == .both {
				let panGestureRec = UIPanGestureRecognizer(target: self, action: #selector(handlePan(panRec:)))
                self.sceneView.addGestureRecognizer(panGestureRec)

				let pinchRec = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(pinchRec:)))
                self.sceneView.addGestureRecognizer(pinchRec)

				let rotateRec = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(rotRec:)))
                self.sceneView.addGestureRecognizer(rotateRec)

				pinchRec.delegate = self
				rotateRec.delegate = self
			}
            self.startMotionUpdates()
		}
	}

	func reportMovement(_ rotationAngle: CGFloat, _ fieldOfViewAngle: CGFloat, callHandler: Bool = true) {
        guard callHandler else { return }

        self.movementHandler?(rotationAngle + CGFloat(self.cameraStartAngle), fieldOfViewAngle)
	}

	// MARK: Gesture handling

	@objc func handlePan(panRec: UIPanGestureRecognizer) {
		if panRec.state == .began {
            self.prevLocation = CGPoint.zero
		} else if panRec.state == .changed {
            let orientation = self.cameraNode.orientation
            let location = panRec.translation(in: self.sceneView)

			let translationDelta = CGPoint(
                x: (location.x - self.prevLocation.x) * self.panSpeed.x,
                y: (location.y - self.prevLocation.y) * self.panSpeed.y
			)

			// Accumulate these if wheb using .both method so that we can apply the rotations
			// to the sensor data and smoothly move with both touch and motion controls at the same time

			// If both, just accumulate, our sensor callback will handle it
            if (self.controlMethod == .both) {
				// Use the pan translation along the x axis to adjust the camera's rotation about the y axis (side to side navigation).
				let yScalar = Float(translationDelta.x / self.bounds.size.width)
				let yRadians = yScalar * MaxPanGestureRotation

				let xScalar = Float(translationDelta.y / self.bounds.size.height)
				let xRadians = xScalar * MaxPanGestureRotation

                self.totalX += xRadians
                self.totalY += yRadians
			} else { // Otherwise, do the math here since we have no sensor
				// Use the pan translation along the x axis to adjust the camera's rotation about the y axis (side to side navigation).
				let yScalar = Float(translationDelta.x / self.bounds.size.width)
				let yRadians = yScalar * MaxPanGestureRotation

				// Use the pan translation along the y axis to adjust the camera's rotation about the x axis (up and down navigation).
				let xScalar = Float(translationDelta.y / self.bounds.size.height)
				let xRadians = xScalar * MaxPanGestureRotation

				// Represent the orientation as a GLKQuaternion
				var glQuaternion = GLKQuaternionMake(orientation.x, orientation.y, orientation.z, orientation.w)

				// Perform up and down rotations around *CAMERA* X axis (note the order of multiplication)
				let xMultiplier = GLKQuaternionMakeWithAngleAndAxis(xRadians, 1, 0, 0)
				glQuaternion = GLKQuaternionMultiply(glQuaternion, xMultiplier)

				// Perform side to side rotations around *WORLD* Y axis (note the order of multiplication, different from above)
				let yMultiplier = GLKQuaternionMakeWithAngleAndAxis(yRadians, 0, 1, 0)
				glQuaternion = GLKQuaternionMultiply(yMultiplier, glQuaternion)

                self.cameraNode.orientation = SCNQuaternion(x: glQuaternion.x, y: glQuaternion.y, z: glQuaternion.z, w: glQuaternion.w)
			}

            self.prevLocation = location
            self.reportMovement(self.cameraAngle, self.xFov.toRadians())
		}
	}

	@objc func handlePinch(pinchRec: UIPinchGestureRecognizer) {
		if pinchRec.numberOfTouches != 2 {
			return
		}

		let zoom = CGFloat(pinchRec.scale)
		switch pinchRec.state {
		case .began:
            self.pinchStartScale = cameraNode.camera!.fieldOfView
		case .changed:
            let fov = self.pinchStartScale / zoom
            if fov > self.minFoV && fov <= self.maxFoV {
                self.cameraNode.camera!.fieldOfView = fov
			}
		default:
			break
		}
	}

	@objc func handleRotate(rotRec: UIRotationGestureRecognizer) {
		if rotRec.state == .began {
            self.prevRotation = CGFloat.zero

            if (self.controlMethod == .both) {
                self.motionPaused = true
			}
		} else if rotRec.state == .changed {
            let orientation = self.cameraNode.orientation
			let rotation = rotRec.rotation

			let zRadians = rotation - prevRotation

			// use a Quaternion instead of eluer angles so we
            // can switch from sensor to finger rotation smoothly
			var glQuaternion = GLKQuaternionMake(orientation.x, orientation.y, orientation.z, orientation.w)

			let zMultiplier = GLKQuaternionMakeWithAngleAndAxis(Float(zRadians), 0, 0, 1)
			glQuaternion = GLKQuaternionMultiply(glQuaternion, zMultiplier)

            self.cameraNode.orientation = SCNQuaternion(x: glQuaternion.x, y: glQuaternion.y, z: glQuaternion.z, w: glQuaternion.w)
            self.prevRotation = rotation
		}
		else {
            self.motionPaused = false
		}
	}
}

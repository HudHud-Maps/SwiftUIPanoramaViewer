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

@MainActor
@objc public protocol CTPanoramaCompass {
	func updateUI(rotationAngle: CGFloat, fieldOfViewAngle: CGFloat)
}

@objc public enum CTPanoramaControlMethod: Int {
	case motion
	case touch
	case both
}

@objc public enum CTPanoramaType: Int {
	case cylindrical
	case spherical
}

@objc public enum CTNavigationDirection: Int, CaseIterable {
	case north
	case east
	case south
	case west
}

@objc public class CTPanoramaView: UIView, UIGestureRecognizerDelegate {

	public enum AnimateOption {
		case none
		case fade(duration: TimeInterval)
	}

	// MARK: Public properties

	@objc public var compass: CTPanoramaCompass?
	@objc public var movementHandler: ((_ rotationAngle: CGFloat, _ fieldOfViewAngle: CGFloat) -> Void)?
    @objc public var tapHandler: ((Float) -> Void)?

	@objc public var panSpeed = CGPoint(x: 0.4, y: 0.4)
	@objc public var startAngle: Float = 0
	@objc public var rotationHandler: ((_ rotationKey: Float) -> Void)?

	@objc public var angleOffset: Float = 0 {
		didSet {
			geometryNode?.rotation = SCNQuaternion(0, 1, 0, angleOffset)
		}
	}

	@objc public var cameraAngle: CGFloat {
		let quaternion = self.cameraNode.orientation
		// Convert quaternion to Euler angles (in radians)
		let yaw = atan2(2 * (quaternion.y * quaternion.w - quaternion.x * quaternion.z),
						1 - 2 * (quaternion.y * quaternion.y + quaternion.z * quaternion.z))

		return CGFloat(-yaw)
	}

	@objc public var minFoV: CGFloat = 40
	@objc public var maxFoV: CGFloat = 100

	private(set) var image: UIImage?
	private(set) var isTransitioningImage: Bool = false

	@objc public var overlayView: UIView? {
		didSet {
			replace(overlayView: oldValue, with: overlayView)
		}
	}

	@objc public var panoramaType: CTPanoramaType {
		return (geometryNode?.geometry is SCNSphere) ? .spherical : .cylindrical
	}

	@objc public var controlMethod: CTPanoramaControlMethod = .touch {
		didSet {
			switchControlMethod(to: controlMethod)
			resetCameraAngles();
		}
	}

	// MARK: Overriding

	public override var backgroundColor: UIColor? {
		didSet {
			sceneView.backgroundColor = backgroundColor
		}
	}

	// MARK: Private properties

	private let MaxPanGestureRotation: Float = GLKMathDegreesToRadians(360)
	private let radius: CGFloat = 10
	private let sceneView = SCNView()
	private let scene = SCNScene()
	private let motionManager = CMMotionManager()
	private var geometryNode: SCNNode?
	private var temporaryGeometryNode: SCNNode?
	private var prevLocation = CGPoint.zero
	private var prevRotation = CGFloat.zero
	private var prevBounds = CGRect.zero

	// Parameters used by the .both method
	private var totalX = Float.zero
	private var totalY = Float.zero

	private var motionPaused = false

	private lazy var cameraNode: SCNNode = {
		let node = SCNNode()
		let camera = SCNCamera()
		node.camera = camera
		return node
	}()

	private lazy var opQueue: OperationQueue = {
		let queue = OperationQueue()
		queue.qualityOfService = .userInteractive
		return queue
	}()

	private lazy var fovHeight: CGFloat = {
		return tan(self.yFov/2 * .pi / 180.0) * 2 * self.radius
	}()

	private var startScale: CGFloat = 0.0

	private var xFov: CGFloat {
		return yFov * self.bounds.width / self.bounds.height
	}

	private var yFov: CGFloat {
		get {
			return cameraNode.camera?.fieldOfView ?? 0
		}
		set {
			cameraNode.camera?.fieldOfView = newValue
		}
	}
    
    private var horizontalFieldOfView: CGFloat {
        let verticalFieldOfViewInRadians = (cameraNode.camera?.fieldOfView ?? 0) * .pi / 180
        let aspectRatio = bounds.width / bounds.height
        let horizontalFieldOfViewInRadians = 2 * atan(tan(verticalFieldOfViewInRadians / 2) * aspectRatio)
        return horizontalFieldOfViewInRadians * 180 / .pi
    }

	// MARK: Class lifecycle methods

	public required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		commonInit()
	}

	public override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	public convenience init(frame: CGRect, image: UIImage) {
		self.init(frame: frame)
		// Force Swift to call the property observer by calling the setter from a non-init context
		({ self.image = image })()
	}

	deinit {
		if motionManager.isDeviceMotionActive {
			motionManager.stopDeviceMotionUpdates()
		}
	}

	// MARK: - Override

	public override func layoutSubviews() {
		super.layoutSubviews()
		if bounds.size.width != prevBounds.size.width || bounds.size.height != prevBounds.size.height {
			sceneView.setNeedsDisplay()
			reportMovement(CGFloat(-cameraNode.eulerAngles.y), xFov.toRadians(), callHandler: false)
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
		yFov = maxFoV
		cameraNode.eulerAngles = SCNVector3Make(0, startAngle, 0)
		totalX = Float.zero
		totalY = Float.zero
		self.reportMovement(CGFloat(startAngle), xFov.toRadians(), callHandler: false)
	}

	public func transition(to image: UIImage, animation: AnimateOption = .fade(duration: 0.5), completion: (()->Void)? = nil) {
		self.isTransitioningImage = true
		self.temporaryGeometryNode?.removeAllActions()
		self.geometryNode?.removeAllActions()

		let newNode = self.createGeometryNode(for: image)
		self.scene.rootNode.addChildNode(newNode)
		self.temporaryGeometryNode = newNode

		DispatchQueue.main.async {
			switch animation {
			case .none:
				self.geometryNode?.removeFromParentNode()
				self.geometryNode = newNode
				self.temporaryGeometryNode = nil
				self.image = image
				self.isTransitioningImage = false
				completion?()
			case .fade(let duration):
				self.geometryNode?.runAction(SCNAction.fadeOut(duration: duration))
				newNode.runAction(SCNAction.fadeIn(duration: duration)) {
					self.geometryNode?.removeFromParentNode()
					self.geometryNode = newNode
					self.temporaryGeometryNode = nil
					DispatchQueue.main.async {
						self.image = image
						self.isTransitioningImage = false
						completion?()
					}
				}
			}
		}
	}

	public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		guard let touchLocation = touches.first?.location(in: sceneView) else { return }

		// use this to approximate distance
//        let hitResults = sceneView.hitTest(touchLocation, options: nil)
//        print(hitResults.first?.localCoordinates.y)

		print(touchLocation)
        let tapIndicator = TapIndicator()
		self.addSubview(tapIndicator)
		tapIndicator.animateCircles(center: touchLocation)

		let angle = Float(self.cameraAngle) + self.startAngle
		let adjustedRadians = angle.truncatingRemainder(dividingBy: 2 * .pi)
//		let degrees = adjustedRadians * 180 / .pi
        
        let percentage = touchLocation.x / sceneView.frame.width
        print(percentage)
        let angleToAdd = horizontalFieldOfView * percentage
        let cameraAngleInDegrees = abs(cameraAngle.toDegrees())
        let startCameraAngle = cameraAngleInDegrees - (horizontalFieldOfView / 2)
        let finalAngle = startCameraAngle + angleToAdd
        print("percentage: \(percentage), fieldOfView: \(horizontalFieldOfView), angleToAdd: \(angleToAdd), startCameraAngle: \(startCameraAngle), final angle: \(finalAngle)")

        self.tapHandler?(Float(finalAngle))
	}
}

// MARK: - Private

private extension CTPanoramaView {

	func commonInit() {
		add(view: sceneView)

		scene.rootNode.addChildNode(cameraNode)

		sceneView.scene = scene
		sceneView.backgroundColor = self.backgroundColor

		switchControlMethod(to: controlMethod)
	}

	// MARK: Configuration helper methods

	func createGeometryNode(for image: UIImage) -> SCNNode {
		let material = SCNMaterial()
		material.diffuse.contents = image
		material.diffuse.mipFilter = .nearest
		material.diffuse.magnificationFilter = .nearest
		material.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, 1, 1)
		material.diffuse.wrapS = .repeat
		material.cullMode = .front

		if image.panoramaType == .spherical {
			let sphere = SCNSphere(radius: radius)
			sphere.segmentCount = 360
			sphere.firstMaterial = material

			let sphereNode = SCNNode()
			sphereNode.geometry = sphere
			sphereNode.rotation = SCNQuaternion(0, 1, 0, angleOffset)
			return sphereNode
		} else {
			let tube = SCNTube(innerRadius: radius, outerRadius: radius, height: fovHeight)
			tube.heightSegmentCount = 50
			tube.radialSegmentCount = 360
			tube.firstMaterial = material

			let tubeNode = SCNNode()
			tubeNode.geometry = tube
			tubeNode.rotation  = SCNQuaternion(0, 1, 0, angleOffset)
			return tubeNode
		}
	}

	func replace(overlayView: UIView?, with newOverlayView: UIView?) {
		overlayView?.removeFromSuperview()
		guard let newOverlayView = newOverlayView else {return}
		add(view: newOverlayView)
	}

	func startMotionUpdates(){
		guard motionManager.isDeviceMotionAvailable else {return}
		motionManager.deviceMotionUpdateInterval = 0.015

		motionPaused = false
		motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: opQueue,
											   withHandler: { [weak self] (motionData, error) in
			guard let panoramaView = self else {return}
			guard !panoramaView.motionPaused else {return}

			guard (panoramaView.controlMethod == .motion || panoramaView.controlMethod == .both) else {return}

			guard let motionData = motionData else {
				print("\(String(describing: error?.localizedDescription))")
				panoramaView.motionManager.stopDeviceMotionUpdates()
				return
			}


			DispatchQueue.main.async {
				if panoramaView.panoramaType == .cylindrical {

					let rotationMatrix = motionData.attitude.rotationMatrix
					var userHeading = .pi - atan2(rotationMatrix.m32, rotationMatrix.m31)
					userHeading += .pi/2

					var startAngle = panoramaView.startAngle

					if (panoramaView.controlMethod == .both) {
						startAngle += panoramaView.totalY
					}
					// Prevent vertical movement in a cylindrical panorama
					panoramaView.cameraNode.eulerAngles = SCNVector3Make(0, startAngle + Float(-userHeading), 0)

				} else {
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

				}

				panoramaView.reportMovement(CGFloat(-panoramaView.cameraNode.eulerAngles.y), panoramaView.xFov.toRadians())
			}
		})
	}

	func switchControlMethod(to method: CTPanoramaControlMethod) {
		sceneView.gestureRecognizers?.removeAll()

		if method == .touch {
			let panGestureRec = UIPanGestureRecognizer(target: self, action: #selector(handlePan(panRec:)))
			sceneView.addGestureRecognizer(panGestureRec)

			let pinchRec = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(pinchRec:)))
			sceneView.addGestureRecognizer(pinchRec)

			let rotateRec = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(rotRec:)))
			sceneView.addGestureRecognizer(rotateRec)

			pinchRec.delegate = self
			rotateRec.delegate = self

			if motionManager.isDeviceMotionActive {
				motionManager.stopDeviceMotionUpdates()
			}

		}
		else {
			if method == .both {
				let panGestureRec = UIPanGestureRecognizer(target: self, action: #selector(handlePan(panRec:)))
				sceneView.addGestureRecognizer(panGestureRec)

				let pinchRec = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(pinchRec:)))
				sceneView.addGestureRecognizer(pinchRec)

				let rotateRec = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(rotRec:)))
				sceneView.addGestureRecognizer(rotateRec)

				pinchRec.delegate = self
				rotateRec.delegate = self
			}

			startMotionUpdates()

		}
	}

	func reportMovement(_ rotationAngle: CGFloat, _ fieldOfViewAngle: CGFloat, callHandler: Bool = true) {
		compass?.updateUI(rotationAngle: rotationAngle, fieldOfViewAngle: fieldOfViewAngle)
		if callHandler {
			movementHandler?(rotationAngle, fieldOfViewAngle)
		}

		if let rotationHandler = rotationHandler {
			// HACK: Create a unique "key" value for rotation to key events off of.

			let a = rotationAngle.toDegrees()
			let b = (cameraNode.rotation.y * cameraNode.orientation.y).toDegrees()
			//let resolution = Float(5.0)
			let s = "\(Int(a * 0.50))\(Int(b * 0.70))"
			let k = Int(s)!
			rotationHandler(Float(rotationAngle))
			PanoramaManager.lastRotationKey = k
		}
	}

	// MARK: Gesture handling

	@objc func handlePan(panRec: UIPanGestureRecognizer) {
		if panRec.state == .began {
			prevLocation = CGPoint.zero

		} else if panRec.state == .changed {

			var modifiedPanSpeed = panSpeed

			if (panoramaType == .cylindrical) {
				modifiedPanSpeed.y = 0 // Prevent vertical movement in a cylindrical panorama
			}

			let orientation = cameraNode.orientation
			let location = panRec.translation(in: sceneView)

			let translationDelta = CGPoint(
				x: (location.x - prevLocation.x) * modifiedPanSpeed.x,
				y: (location.y - prevLocation.y) * modifiedPanSpeed.y
			)

			// Accumulate these if wheb using .both method so that we can apply the rotations
			// to the sensor data and smoothly move with both touch and motion controls at the same time

			// If both, just accumulate, our sensor callback will handle it
			if (controlMethod == .both) {

				// Use the pan translation along the x axis to adjust the camera's rotation about the y axis (side to side navigation).
				let yScalar = Float(translationDelta.x / self.bounds.size.width)
				let yRadians = yScalar * MaxPanGestureRotation

				let xScalar = Float(translationDelta.y / self.bounds.size.height)
				let xRadians = xScalar * MaxPanGestureRotation

				totalX += xRadians
				totalY += yRadians
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

				cameraNode.orientation = SCNQuaternion(x: glQuaternion.x, y: glQuaternion.y, z: glQuaternion.z, w: glQuaternion.w)

			}

			prevLocation = location
			reportMovement(self.cameraAngle, xFov.toRadians())
		}
	}

	@objc func handlePinch(pinchRec: UIPinchGestureRecognizer) {
		if pinchRec.numberOfTouches != 2 {
			return
		}

		let zoom = CGFloat(pinchRec.scale)
		switch pinchRec.state {
		case .began:
			startScale = cameraNode.camera!.fieldOfView
		case .changed:
			let fov = startScale / zoom
			if fov > minFoV && fov <= maxFoV {
				cameraNode.camera!.fieldOfView = fov
			}
		default:
			break
		}
	}

	@objc func handleRotate(rotRec: UIRotationGestureRecognizer) {

		// no rotation for cylindrical
		if panoramaType == .cylindrical{
			return
		}

		if rotRec.state == .began {
			prevRotation = CGFloat.zero

			if (controlMethod == .both) {
				motionPaused = true
			}

		} else if rotRec.state == .changed {

			let orientation = cameraNode.orientation
			let rotation = rotRec.rotation

			let zRadians = rotation - prevRotation

			// use a Quaternion instead of eluer angles
			// so we can switch from sensor to finger rotation
			// smoothly

			var glQuaternion = GLKQuaternionMake(orientation.x, orientation.y, orientation.z, orientation.w)

			let zMultiplier = GLKQuaternionMakeWithAngleAndAxis(Float(zRadians), 0, 0, 1)
			glQuaternion = GLKQuaternionMultiply(glQuaternion, zMultiplier)

			cameraNode.orientation = SCNQuaternion(x: glQuaternion.x, y: glQuaternion.y, z: glQuaternion.z, w: glQuaternion.w)

			prevRotation = rotation

		}
		else {
			motionPaused = false
		}
	}
}

@MainActor
private extension CMDeviceMotion {

	func orientation() -> SCNVector4 {

		let attitude = self.attitude.quaternion
		let attitudeQuanternion = GLKQuaternion(quanternion: attitude)

		let result: SCNVector4

		switch UIApplication.shared.statusBarOrientation {

		case .landscapeRight:
			let cq1 = GLKQuaternionMakeWithAngleAndAxis(.pi/2, 0, 1, 0)
			let cq2 = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 1, 0, 0)
			var quanternionMultiplier = GLKQuaternionMultiply(cq1, attitudeQuanternion)
			quanternionMultiplier = GLKQuaternionMultiply(cq2, quanternionMultiplier)

			result = quanternionMultiplier.vector(for: .landscapeRight)

		case .landscapeLeft:
			let cq1 = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 0, 1, 0)
			let cq2 = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 1, 0, 0)
			var quanternionMultiplier = GLKQuaternionMultiply(cq1, attitudeQuanternion)
			quanternionMultiplier = GLKQuaternionMultiply(cq2, quanternionMultiplier)

			result = quanternionMultiplier.vector(for: .landscapeLeft)

		case .portraitUpsideDown:
			let cq1 = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 1, 0, 0)
			let cq2 = GLKQuaternionMakeWithAngleAndAxis(.pi, 0, 0, 1)
			var quanternionMultiplier = GLKQuaternionMultiply(cq1, attitudeQuanternion)
			quanternionMultiplier = GLKQuaternionMultiply(cq2, quanternionMultiplier)

			result = quanternionMultiplier.vector(for: .portraitUpsideDown)

		default:
			let clockwiseQuanternion = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 1, 0, 0)
			let quanternionMultiplier = GLKQuaternionMultiply(clockwiseQuanternion, attitudeQuanternion)

			result = quanternionMultiplier.vector(for: .portrait)
		}
		return result
	}
}

private extension UIImage {

	var panoramaType: CTPanoramaType {
		if self.size.width / self.size.height == 2 {
			return .spherical
		}
		return .cylindrical
	}
}

private extension UIView {
	func add(view: UIView) {
		view.translatesAutoresizingMaskIntoConstraints = false
		addSubview(view)
		let views = ["view": view]
		let hConstraints = NSLayoutConstraint.constraints(withVisualFormat: "|[view]|", options: [], metrics: nil, views: views)
		let vConstraints = NSLayoutConstraint.constraints(withVisualFormat: "V:|[view]|", options: [], metrics: nil, views: views)
		self.addConstraints(hConstraints)
		self.addConstraints(vConstraints)
	}
}

private extension FloatingPoint {
	func toDegrees() -> Self {
		return self * 180 / .pi
	}

	func toRadians() -> Self {
		return self * .pi / 180
	}
}

private extension GLKQuaternion {
	init(quanternion: CMQuaternion) {
		self.init(q: (Float(quanternion.x), Float(quanternion.y), Float(quanternion.z), Float(quanternion.w)))
	}

	func vector(for orientation: UIInterfaceOrientation) -> SCNVector4 {
		switch orientation {
		case .landscapeRight:
			return SCNVector4(x: -self.y, y: self.x, z: self.z, w: self.w)

		case .landscapeLeft:
			return SCNVector4(x: self.y, y: -self.x, z: self.z, w: self.w)

		case .portraitUpsideDown:
			return SCNVector4(x: -self.x, y: -self.y, z: self.z, w: self.w)

		default:
			return SCNVector4(x: self.x, y: self.y, z: self.z, w: self.w)
		}
	}
}

extension CMMotionManager: @retroactive @unchecked Sendable {}

//
//  PanoramaViewer.swift
//  Escape from Mystic Manor (iOS)
//
//  Created by Kevin Mullins on 2/8/22.
//  https://www.hackingwithswift.com/quick-start/swiftui/how-to-wrap-a-custom-uiview-for-swiftui
//
//  From: https://github.com/scihant/CTPanoramaView

import Foundation
import SwiftUI
import UIKit

/// The `PanoramaViewer` allows you to display an interactive panorama viewer in a SwiftUI `View`.
///
/// Take the following example:
///
/// ```swift
/// @State var rotationIndicator:Float = 0.0
/// ...
///
/// ZStack {
/// PanoramaViewer(image: SwiftUIPanoramaViewer.bindImage("PanoramaImageName")) {key in }
/// cameraMoved: { pitch, yaw, roll in
///     rotationIndicator = yaw
/// }
///
/// CompassView()
///    .frame(width: 50.0, height: 50.0)
///    .rotationEffect(Angle(degrees: Double(rotationIndicator)))
/// }
/// // If using `SwiftUIGamepad` package, allow the gamepad to rotate the view.
/// .onGamepadLeftThumbstick(viewID: viewID) { xAxis, yAxis in
///     PanoramaManager.moveCamera(xAxis: xAxis, yAxis: yAxis)
/// }
/// ```
///
public struct PanoramaViewer<ID: Equatable>: UIViewRepresentable {

	public enum ProgressiveImage {
        case loading(progress: Float, image: UIImage?, id: ID, angle: Float)
        case finished(image: UIImage, id: ID, angle: Float)

		var image: UIImage? {
			switch self {
			case let .loading(_, image, _, _):
				return image
			case let .finished(image, _, _):
				return image
			}
		}
	}

	public class Coordinator {
		var id: ID? = nil
        var lastAppliedStartAngle: Float = 0
        weak var panoramaView: CTPanoramaView?
	}

	public func makeCoordinator() -> Coordinator {
		return Coordinator()
	}

    // MARK: - Type
    /// The type of view being managed by the `PanoramaViewer`.
    public typealias UIViewType = CTPanoramaView
    
    // MARK: - Properties
    /// The `UIImage` being displayed in the `PanoramaViewer`.
	@Binding public var progressiveImage: ProgressiveImage?

    /// The type of panorama image being displayed.
    public var panoramaType: CTPanoramaType = .spherical
    
    /// The type of user interaction that the `PanoramaViewer` supports.
    public var controlMethod: CTPanoramaControlMethod = .touch

	@Binding public var rotation: Float

    /// The viewer background color.
    public var backgroundColor:UIColor = .black

    public var tapHandler: ((Float) -> Void)?

    // MARK: - Initializers
    /// Creates a new instance.
    /// - Parameters:
    ///   - image: The `UIImage` being displayed in the `PanoramaViewer`.
    ///   - panoramaType: The type of panorama image being displayed.
    ///   - controlMethod: The type of user interaction that the `PanoramaViewer` supports.
    ///   - backgroundColor: The viewer background color.
    ///   - rotationHandler: Handle the panorama being rotated.
	public init(progressiveImage: Binding<ProgressiveImage?>, panoramaType: CTPanoramaType = .spherical, controlMethod: CTPanoramaControlMethod = .touch, rotation: Binding<Float>, backgroundColor:UIColor = .black, tapHandler: ((Float) -> Void)? = nil) {
        self._progressiveImage = progressiveImage
        self.panoramaType = panoramaType
        self.controlMethod = controlMethod
        self._rotation = rotation
        self.backgroundColor = backgroundColor
		self.tapHandler = tapHandler
    }
    
    // MARK: - Functions
    /// Creates a new instance of the `PanoramaViewer`.
    /// - Parameter context: The context to create the viewer in.
    /// - Returns: Returns the new `PanoramaViewer`.
    public func makeUIView(context: Context) -> UIViewType {
        print("Hello from makeUIView\n")
        // Create and initialize
        let view = CTPanoramaView()
		view.startAngle = self.rotation.toRadians()
        view.controlMethod = controlMethod
        view.backgroundColor = backgroundColor
        view.rotationHandler = { rotation in
            self.rotation = rotation.toDegrees()
        }
		view.tapHandler = tapHandler
		if let image = self.progressiveImage?.image {
			view.transition(to: image, startAngle: 0, animation: .none)
		}

        context.coordinator.panoramaView = view

        // Save reference to connect to compass view
        PanoramaManager.lastPanoramaViewer = view
        
        // Return viewer
        return view
    }
    
    /// Handles the `PanoramaViewer` being updated.
    /// - Parameters:
    ///   - uiView: The `PanoramaViewer` that is updating.
    ///   - context: The context that the view is updating in.
    public func updateUIView(_ uiView: UIViewType, context: Context) {
        // Print current angles to debug
        print("DEBUG: Current angles - uiView.startAngle: \(uiView.startAngle), self.startAngle: \(self.rotation.toRadians())")

        // Only update if the angle has changed significantly from the last applied value
        if abs(context.coordinator.lastAppliedStartAngle - self.rotation.toRadians()) > 0.05 {
            print("DEBUG: ✅ Applying angle change - Old: \(uiView.startAngle), New: \(self.rotation.toRadians()), Difference: \(abs(context.coordinator.lastAppliedStartAngle - self.rotation.toRadians()))")
            uiView.startAngle = self.rotation.toRadians()
//            uiView.updateRotation()
            context.coordinator.lastAppliedStartAngle = self.rotation.toRadians()
        } else {
            print("DEBUG: ❌ Skipping angle update - Difference too small: \(abs(context.coordinator.lastAppliedStartAngle - self.rotation.toRadians())) lastApplied: \(context.coordinator.lastAppliedStartAngle), self.startAngle: \(self.rotation.toRadians())")
        }
        
		switch self.progressiveImage {
		case let .loading(_, image, id, angle):
			if let image, image != uiView.image, uiView.isTransitioningImage == false {
				let animation: CTPanoramaView.AnimateOption = context.coordinator.id == id ? .none : .fade(duration: 0.5)
				uiView.transition(to: image, startAngle: angle, animation: animation)
			}
		case let .finished(image, id, angle):
			let animation: CTPanoramaView.AnimateOption = context.coordinator.id == id ? .none : .fade(duration: 0.5)
			uiView.transition(to: image, startAngle: angle, animation: animation)
		case .none:
			break
		}
    }
}

extension FloatingPoint {

    func toDegrees() -> Self {
        return self * 180 / .pi
    }

    func toRadians() -> Self {
        return self * .pi / 180
    }
}

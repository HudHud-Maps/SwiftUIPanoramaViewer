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
import OSLog
import UIKit
import CoreLocation

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

        var angle: Float {
            switch self {
            case let .loading(_, _, _, angle):
                return angle
            case let .finished(_, _, angle):
                return angle
            }
        }
	}

	public class Coordinator {
		var id: ID? = nil
	}

	public func makeCoordinator() -> Coordinator {
		return Coordinator()
	}

    // MARK: - Type

    public typealias UIViewType = CTPanoramaView
    
    // MARK: - Properties

	@Binding public var progressiveImage: ProgressiveImage?

    public var controlMethod: CTPanoramaControlMethod = .touch
    public var backgroundColor: UIColor = .black
    public var initialCameraAngle: CLLocationDegrees = 0
    public var movementHandler: CTPanoramaView.MovementHandler?
    public var tapHandler: CTPanoramaView.TapHandler?

    // MARK: - Initializers
    /// Creates a new instance.
    /// - Parameters:
    ///   - image: The `UIImage` being displayed in the `PanoramaViewer`.
    ///   - panoramaType: The type of panorama image being displayed.
    ///   - controlMethod: The type of user interaction that the `PanoramaViewer` supports.
    ///   - backgroundColor: The viewer background color.
    ///   - rotationHandler: Handle the panorama being rotated.
    ///   - cameraMoved: Handles the panorama camera being moved and returns the new Pitch, Yaw and Rotation.
    public init(progressiveImage: Binding<ProgressiveImage?>,
                controlMethod: CTPanoramaControlMethod = .touch,
                backgroundColor:UIColor = .black,
                initialCameraAngle: CLLocationDegrees = 0,
                movementHandler: CTPanoramaView.MovementHandler? = nil,
                tapHandler: CTPanoramaView.TapHandler?) {
        self._progressiveImage = progressiveImage
        self.controlMethod = controlMethod
        self.backgroundColor = backgroundColor
        self.initialCameraAngle = initialCameraAngle
        self.movementHandler = movementHandler
		self.tapHandler = tapHandler
    }
    
    // MARK: - Functions
    /// Creates a new instance of the `PanoramaViewer`.
    /// - Parameter context: The context to create the viewer in.
    /// - Returns: Returns the new `PanoramaViewer`.
    public func makeUIView(context: Context) -> UIViewType {
        let view = CTPanoramaView()
        view.controlMethod = self.controlMethod
        view.backgroundColor = self.backgroundColor
        view.movementHandler = self.movementHandler
        view.tapHandler = self.tapHandler
//        view.cameraStartAngle = self.initialCameraAngle + .pi
        return view
    }

    public static func dismantleUIView(_ uiView: CTPanoramaView, coordinator: Coordinator) {
        Logger.panoramaViewer.notice("CTPanoramaView cleanup")
        uiView.cleanup()
    }

    /// Handles the `PanoramaViewer` being updated.
    /// - Parameters:
    ///   - uiView: The `PanoramaViewer` that is updating.
    ///   - context: The context that the view is updating in.
    public func updateUIView(_ uiView: UIViewType, context: Context) {
		switch self.progressiveImage {
		case let .loading(_, image, id, angle):
			if let image, image != uiView.image {
				let animation: CTPanoramaView.AnimateOption = context.coordinator.id == id ? .none : .fade(duration: 0.5)
                uiView.transition(to: image, angle: angle.toRadians(), animation: animation, description: String(describing: id))
			}
		case let .finished(image, id, angle):
            let animation: CTPanoramaView.AnimateOption = context.coordinator.id == id ? .none : .fade(duration: 0.5)
            uiView.transition(to: image, angle: angle.toRadians(), animation: animation, description: String(describing: id))
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


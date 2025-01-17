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
public struct PanoramaViewer: UIViewRepresentable {
    // MARK: - Type
    /// The type of view being managed by the `PanoramaViewer`.
    public typealias UIViewType = CTPanoramaView
    
    // MARK: - Properties
    /// The `UIImage` being displayed in the `PanoramaViewer`.
    @Binding public var image: UIImage?
    
    /// The type of panorama image being displayed.
    public var panoramaType: CTPanoramaType = .spherical
    
    /// The type of user interaction that the `PanoramaViewer` supports.
    public var controlMethod: CTPanoramaControlMethod = .touch

	public var startAngle: Float = 0

    /// The viewer background color.
    public var backgroundColor:UIColor = .black
    
    /// Handles the view rotating.
	public var rotationHandler: ((_ rotationKey: Float) -> Void)?

    /// Handles the camera being moved.
    public var cameraMoved: ((_ pitch:Float, _ yaw:Float, _ roll:Float) -> Void)?

    public var tapHandler: ((Float) -> Void)?

    // MARK: - Initializers
    /// Creates a new instance.
    /// - Parameters:
    ///   - image: The `UIImage` being displayed in the `PanoramaViewer`.
    ///   - panoramaType: The type of panorama image being displayed.
    ///   - controlMethod: The type of user interaction that the `PanoramaViewer` supports.
    ///   - backgroundColor: The viewer background color.
    ///   - rotationHandler: Handle the panorama being rotated.
    ///   - cameraMoved: Handles the panorama camera being moved and returns the new Pitch, Yaw and Rotation.
    public init(image: Binding<UIImage?>, panoramaType: CTPanoramaType = .spherical, controlMethod: CTPanoramaControlMethod = .touch, startAngle: Float = 0, backgroundColor:UIColor = .black, rotationHandler: ((_ rotationKey: Float) -> Void)? = nil, cameraMoved: ((_ pitch:Float, _ yaw:Float, _ roll:Float) -> Void)? = nil, tapHandler: ((Float) -> Void)? = nil) {
        self._image = image
        self.panoramaType = panoramaType
        self.controlMethod = controlMethod
		self.startAngle = startAngle
        self.backgroundColor = backgroundColor
        self.rotationHandler = rotationHandler
        self.cameraMoved = cameraMoved
		self.tapHandler = tapHandler
    }
    
    // MARK: - Functions
    /// Creates a new instance of the `PanoramaViewer`.
    /// - Parameter context: The context to create the viewer in.
    /// - Returns: Returns the new `PanoramaViewer`.
    public func makeUIView(context: Context) -> UIViewType {
        // Create and initialize
        let view = CTPanoramaView()
		view.startAngle = self.startAngle
        view.controlMethod = controlMethod
        view.backgroundColor = backgroundColor
        view.rotationHandler = rotationHandler
		view.tapHandler = tapHandler
		if let image {
			view.transition(to: image, animation: .none)
		}

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
		if let image, image != uiView.image, uiView.isTransitioningImage == false {
			print("image changed, animating")
			uiView.transition(to: image)
        }
    }
}

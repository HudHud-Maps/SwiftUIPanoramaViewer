//
//  File.swift
//  SwiftUIPanoramaViewer
//
//  Created by Patrick Kladek on 27.05.25.
//

import Foundation
import OSLog

extension Logger {

    fileprivate static var subsystem = "SwiftUIPanoramaViewer" //Bundle(for: PanoramaManager.self).bundleIdentifier!

    static let panoramaViewer = Logger(subsystem: subsystem, category: "PanoramaViewer")
    static let sceneKit = Logger(subsystem: subsystem, category: "SceneKit")
}

extension OSSignposter {
    static let renderer = OSSignposter(subsystem: Logger.subsystem, category: "Renderer")
    static let scene = OSSignposter(subsystem: Logger.subsystem, category: "Scene")
    static let transition = OSSignposter(subsystem: Logger.subsystem, category: "Transition")
}

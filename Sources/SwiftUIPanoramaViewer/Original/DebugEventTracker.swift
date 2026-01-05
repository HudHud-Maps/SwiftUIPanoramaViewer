//
//  DebugEventTracker.swift
//  SwiftUIPanoramaViewer
//
//  Created by Patrick Kladek on 30.05.25.
//

import Foundation
import OSLog

public extension Logger {

    static var subsystem = "SwiftUIPanoramaViewer"

    static let panoramaViewer = Logger(subsystem: Logger.subsystem, category: "PanoramaViewer")
}

public class DebugEventTracker {

    let category: String
    let name: StaticString
    let signposter: OSSignposter
    let logger: Logger
    private var signpostState: OSSignpostIntervalState?

    // MARK: - Lifecycle

    public init(subsystem: String = Logger.subsystem, category: String, name: StaticString) {
        self.category = category
        self.name = name
        self.signposter = OSSignposter(subsystem: subsystem, category: category)
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    // MARK: - DebugEventTracker

    public func trackBegin(message: String? = nil) {
        let signpostID = self.signposter.makeSignpostID(from: self)

        if let message {
            self.signpostState = self.signposter.beginInterval(self.name, id: signpostID, "\(message)")
            self.logger.notice("Begin \(self.name): \(message)")
        } else {
            self.signpostState = self.signposter.beginInterval(name, id: signpostID)
            self.logger.notice("Begin \(self.name)")
        }
    }

    public func trackEnd(message: String? = nil) {
        guard let signpostState = self.signpostState else { return }

        if let message {
            self.signposter.endInterval(name, signpostState, "\(message)")
            self.logger.notice("End \(self.name): \(message)")
        } else {
            self.signposter.endInterval(self.name, signpostState)
            self.logger.notice("End \(self.name)")
        }
    }

    public func trackEvent(message: String? = nil) {
        let signpostID = self.signposter.makeSignpostID(from: self)

        if let message {
            self.signposter.emitEvent(self.name, id: signpostID, "\(message)")
            self.logger.notice("Event \(self.name): \(message)")
        } else {
            self.signposter.emitEvent(self.name, id: signpostID)
            self.logger.notice("Event \(self.name)")
        }
    }
}

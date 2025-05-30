//
//  File.swift
//  SwiftUIPanoramaViewer
//
//  Created by Patrick Kladek on 27.05.25.
//

import Foundation
import SceneKit
import OSLog

final class Node: SCNNode {

    private var role: Role {
        didSet {
            self.name = role.rawValue
        }
    }

    enum Role: String {
        case camera
        case persistent
        case new
    }

    let eventTracker = DebugEventTracker(category: "Scene", name: "Node Lifecycle")

    // MARK: - Lifecycle

    @available(*, unavailable)
    override init() {
        fatalError("")
    }

    init(role: Role) {
        self.role = role
        super.init()
        self.name = role.rawValue

        eventTracker.trackBegin(message: "Role: '\(role.rawValue)'")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.eventTracker.trackEnd(message: "Role: '\(self.role.rawValue)'")
    }

    // MARK: - Node

    func change(role: Role) {
        self.eventTracker.trackEvent(message: "'\(self.role.rawValue)' changed to '\(role.rawValue)'")
        self.role = role
    }
}

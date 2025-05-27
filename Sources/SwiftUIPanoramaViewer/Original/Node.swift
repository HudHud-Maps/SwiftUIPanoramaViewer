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

    private var signpostID: OSSignpostID!
    private var signpostState: OSSignpostIntervalState!
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

    @available(*, unavailable)
    override init() {
        fatalError("")
    }

    init(role: Role) {
        self.role = role
        super.init()
        self.name = role.rawValue

        self.signpostID = OSSignposter.scene.makeSignpostID(from: self)
        Logger.sceneKit.notice("Node init, role: '\(role.rawValue)'")
        self.signpostState = OSSignposter.scene.beginInterval("Node Lifecycle", id: self.signpostID, "Role: '\(role.rawValue)'")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        Logger.sceneKit.notice("Node deinit, role: '\(self.role.rawValue)'")
        OSSignposter.scene.endInterval("Node Lifecycle", self.signpostState, "Role: '\(self.role.rawValue)'")
    }

    // MARK: - Node

    func change(role: Role) {
        Logger.sceneKit.notice("Role changed from '\(self.role.rawValue)' to '\(role.rawValue)'")
        OSSignposter.scene.emitEvent("Role changed", id: self.signpostID, "'\(self.role.rawValue)' changed to '\(role.rawValue)'")
        self.role = role
    }
}

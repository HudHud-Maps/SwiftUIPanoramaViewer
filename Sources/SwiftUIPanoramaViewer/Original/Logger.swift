//
//  Logger.swift
//  SwiftUIPanoramaViewer
//
//  Created by Patrick Kladek on 24.09.24.
//

import OSLog

extension Logger {
	private static var subsystem = Bundle(for: CTPanoramaView.self).bundleIdentifier!

	static let panoramaView = Logger(subsystem: subsystem, category: "PanoramaView")
}

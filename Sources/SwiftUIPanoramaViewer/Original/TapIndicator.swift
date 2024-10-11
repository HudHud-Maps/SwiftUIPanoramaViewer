//
//  TapIndicator.swift
//  CTPanoramaView
//
//  Created by Patrick Kladek on 11.10.24.
//  Copyright © 2024 scihant. All rights reserved.
//

import UIKit

extension UIView {

    static func forAutolayout() -> Self {
        let view = Self()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
}

final class CircleView: UIView {

    override func layoutSubviews() {
        super.layoutSubviews()

        self.layer.cornerRadius = min(self.bounds.width, self.bounds.height) / 2.0
    }
}

final class TapIndicator: UIView {

    private let smallCircle: CircleView = .forAutolayout()
    private let largeCircle: CircleView = .forAutolayout()

    convenience init() {
        self.init(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupCircles()
        self.alpha = 0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupCircles()
        self.alpha = 0
    }

    private func setupCircles() {
        // Set the initial size and appearance of the circles
        self.smallCircle.layer.borderColor = UIColor.white.cgColor
        self.smallCircle.layer.borderWidth = 1.0

        self.largeCircle.layer.borderColor = UIColor.white.cgColor
        self.largeCircle.layer.borderWidth = 1.0

        // Add the circles to the view
        self.addSubview(self.largeCircle)
        self.addSubview(self.smallCircle)

        NSLayoutConstraint.activate([
            self.smallCircle.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.smallCircle.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.smallCircle.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 0.5),
            self.smallCircle.heightAnchor.constraint(equalTo: self.heightAnchor, multiplier: 0.5),

            self.largeCircle.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.largeCircle.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.largeCircle.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 1),
            self.largeCircle.heightAnchor.constraint(equalTo: self.heightAnchor, multiplier: 1),
        ])
    }

    func animateCircles(center: CGPoint) {
        self.center = center
        self.alpha = 1
        self.smallCircle.transform = CGAffineTransformMakeScale(0, 0)
        self.largeCircle.transform = CGAffineTransformMakeScale(0, 0)
        self.largeCircle.alpha = 1

        UIView.animateKeyframes(withDuration: 1, delay: 0) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1 / 2) {
                self.smallCircle.transform = CGAffineTransformIdentity;
            }

            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1) {
                self.largeCircle.transform = CGAffineTransformMakeScale(2, 2);
            }

            UIView.addKeyframe(withRelativeStartTime: 1 / 2, relativeDuration: 1 / 2) {
                self.smallCircle.transform = CGAffineTransformMakeScale(0.5, 0.5);
                self.largeCircle.alpha = 0
            }
        } completion: { finished in
            UIView.animate(withDuration: 0.25) {
                self.alpha = 0
            } completion: { finished in
                self.removeFromSuperview()
            }
        }
    }
}

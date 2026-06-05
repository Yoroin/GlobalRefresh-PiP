//
//  AdaptiveSheetPresentation.swift
//  pip_swift
//

import UIKit

extension UIViewController {
    func configureAdaptivePageSheet(preferredHeightRatio: CGFloat = 0.58) {
        modalPresentationStyle = .pageSheet

        guard #available(iOS 15.0, *), let sheet = sheetPresentationController else {
            return
        }

        if #available(iOS 26.0, *) {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            return
        }

        let ratio = min(max(preferredHeightRatio, 0.45), 0.82)
        if #available(iOS 16.0, *) {
            sheet.detents = [
                .custom(identifier: .init("adaptive")) { context in
                    context.maximumDetentValue * ratio
                },
                .large()
            ]
        } else {
            sheet.detents = [.medium(), .large()]
        }
        sheet.selectedDetentIdentifier = .medium
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        sheet.preferredCornerRadius = adaptiveSheetCornerRadius
    }

    func applyLegacyGlassSheetBackground() -> UIView {
        guard #unavailable(iOS 26.0) else {
            view.backgroundColor = .systemGroupedBackground
            return view
        }

        view.backgroundColor = .clear
        let glassView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        glassView.contentView.backgroundColor = UIColor.systemGroupedBackground.withAlphaComponent(0.42)
        glassView.layer.cornerRadius = adaptiveSheetCornerRadius
        glassView.layer.cornerCurve = .continuous
        glassView.clipsToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(glassView)
        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            glassView.topAnchor.constraint(equalTo: view.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        return glassView.contentView
    }

    private var adaptiveSheetCornerRadius: CGFloat {
        let screenBounds = UIScreen.main.bounds
        let shortestSide = min(screenBounds.width, screenBounds.height)
        switch shortestSide {
        case ..<360:
            return 22
        case ..<430:
            return 26
        default:
            return 30
        }
    }
}

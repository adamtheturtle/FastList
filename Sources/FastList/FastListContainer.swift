#if os(macOS)
import AppKit
import SwiftUI

/// Scroll view plus an optional empty-state overlay for the AppKit backend.
public final class FastListContainerView: NSView {
    let scrollView: NSScrollView
    private let emptyHostingView = NSHostingView(rootView: AnyView(EmptyView()))

    override init(frame frameRect: NSRect) {
        scrollView = NSScrollView(frame: frameRect)
        super.init(frame: frameRect)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyHostingView.translatesAutoresizingMaskIntoConstraints = false
        emptyHostingView.isHidden = true
        addSubview(scrollView)
        addSubview(emptyHostingView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyHostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            emptyHostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            emptyHostingView.topAnchor.constraint(equalTo: topAnchor),
            emptyHostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func updateEmptyState(_ view: AnyView?, isVisible: Bool) {
        if let view {
            emptyHostingView.rootView = view
        }
        emptyHostingView.isHidden = !isVisible
        scrollView.isHidden = isVisible
    }
}
#endif

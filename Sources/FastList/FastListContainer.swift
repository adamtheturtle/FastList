#if os(macOS)
import AppKit
import SwiftUI

/// Scroll view with optional header, footer, and empty-state overlay for the AppKit backend.
public final class FastListContainerView: NSView {
    let headerHostingView = NSHostingView(rootView: AnyView(EmptyView()))
    let scrollView: NSScrollView
    let footerHostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private let emptyHostingView = NSHostingView(rootView: AnyView(EmptyView()))

    override init(frame frameRect: NSRect) {
        scrollView = NSScrollView(frame: frameRect)
        super.init(frame: frameRect)
        [headerHostingView, scrollView, footerHostingView, emptyHostingView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        headerHostingView.isHidden = true
        footerHostingView.isHidden = true
        emptyHostingView.isHidden = true
        NSLayoutConstraint.activate([
            headerHostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerHostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerHostingView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: headerHostingView.bottomAnchor),
            footerHostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerHostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerHostingView.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            footerHostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyHostingView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            emptyHostingView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            emptyHostingView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            emptyHostingView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func updateChrome(header: AnyView?, footer: AnyView?) {
        if let header {
            headerHostingView.rootView = header
            headerHostingView.isHidden = false
        } else {
            headerHostingView.isHidden = true
        }
        if let footer {
            footerHostingView.rootView = footer
            footerHostingView.isHidden = false
        } else {
            footerHostingView.isHidden = true
        }
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

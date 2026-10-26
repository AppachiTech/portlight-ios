import PortlightSSH
import UIKit

/// The row of extra keys above the keyboard: Esc, sticky Ctrl/Alt, Tab,
/// arrows (with auto-repeat), shell symbols, F-keys and snippets. Scrolls
/// sideways, so it works in portrait and landscape.
final class KeyBarView: UIInputView {
    static let height: CGFloat = 46

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var buttons: [KeyBarItem: UIButton] = [:]
    private let handler: (KeyBarItem) -> Void
    private var repeatTimer: Timer?
    private let tapFeedback = UIImpactFeedbackGenerator(style: .light)

    private static let repeating: Set<KeyBarItem> = [
        .key(.up), .key(.down), .key(.left), .key(.right), .key(.backspace), .key(.delete),
    ]

    init(items: [KeyBarItem], handler: @escaping (KeyBarItem) -> Void) {
        self.handler = handler
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.height), inputViewStyle: .keyboard)
        autoresizingMask = [.flexibleWidth]
        allowsSelfSizing = true

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: Self.height - 10),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
        setItems(items)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.height)
    }

    func setItems(_ items: [KeyBarItem]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        var seen = Set<KeyBarItem>()
        for item in items where seen.insert(item).inserted {
            let button = makeButton(for: item)
            buttons[item] = button
            stack.addArrangedSubview(button)
        }
    }

    private func makeButton(for item: KeyBarItem) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        configuration.baseForegroundColor = .label
        var title = AttributedString(item.label)
        title.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .medium)
        configuration.attributedTitle = title
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = accessibilityName(for: item)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true

        if Self.repeating.contains(item) {
            button.addAction(UIAction { [weak self] _ in self?.startRepeating(item) }, for: .touchDown)
            button.addAction(UIAction { [weak self] _ in self?.stopRepeating() }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        } else {
            button.addAction(UIAction { [weak self] _ in self?.fire(item) }, for: .touchUpInside)
        }
        return button
    }

    private func fire(_ item: KeyBarItem) {
        tapFeedback.impactOccurred()
        handler(item)
    }

    private func startRepeating(_ item: KeyBarItem) {
        fire(item)
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                self?.handler(item)
            }
        }
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    /// Shows the sticky modifiers: tinted once, filled when locked.
    func update(_ sticky: StickyModifiers) {
        style(buttons[.ctrl], sticky.ctrl)
        style(buttons[.alt], sticky.alt)
    }

    private func style(_ button: UIButton?, _ state: StickyModifiers.State) {
        guard let button, var configuration = button.configuration else { return }
        switch state {
        case .off:
            configuration.baseBackgroundColor = nil
            configuration.baseForegroundColor = .label
            configuration.background.strokeWidth = 0
        case .once:
            configuration.baseBackgroundColor = .systemOrange.withAlphaComponent(0.35)
            configuration.baseForegroundColor = .label
            configuration.background.strokeWidth = 0
        case .locked:
            configuration.baseBackgroundColor = .systemOrange
            configuration.baseForegroundColor = .black
            configuration.background.strokeColor = .label
            configuration.background.strokeWidth = 1
        }
        button.configuration = configuration
        button.accessibilityValue = state == .off ? "off" : (state == .once ? "on for next key" : "locked")
    }

    private func accessibilityName(for item: KeyBarItem) -> String {
        switch item {
        case .ctrl: "Control"
        case .alt: "Alt"
        case .snippets: "Saved commands"
        case .keyboard: "Toggle keyboard"
        case .key(let key):
            switch key {
            case .escape: "Escape"
            case .tab: "Tab"
            case .up: "Up arrow"
            case .down: "Down arrow"
            case .left: "Left arrow"
            case .right: "Right arrow"
            case .home: "Home"
            case .end: "End"
            case .pageUp: "Page up"
            case .pageDown: "Page down"
            case .function(let n): "F\(n)"
            case .enter: "Return"
            case .backspace: "Delete backward"
            case .delete: "Delete forward"
            case .insert: "Insert"
            case .text(let text): text
            }
        }
    }
}

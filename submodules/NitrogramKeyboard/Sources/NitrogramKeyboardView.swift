import Foundation
import UIKit

/// Optional hooks. Typing itself is handled by the keyboard - the delegate only
/// hears about the two actions the host has to decide on.
public protocol NitrogramKeyboardViewDelegate: AnyObject {
    /// The return key was pressed. Return true if handled (e.g. the message was
    /// sent); returning false inserts a newline instead.
    func nitrogramKeyboardReturn() -> Bool
    /// The user asked to go back to the system keyboard.
    func nitrogramKeyboardDismiss()
}

public struct NitrogramKeyboardTheme {
    public let background: UIColor
    public let keyBackground: UIColor
    public let functionalKeyBackground: UIColor
    public let accentKeyBackground: UIColor
    public let keyText: UIColor
    public let accentKeyText: UIColor
    public let keyShadow: UIColor

    public init(background: UIColor, keyBackground: UIColor, functionalKeyBackground: UIColor, accentKeyBackground: UIColor, keyText: UIColor, accentKeyText: UIColor, keyShadow: UIColor) {
        self.background = background
        self.keyBackground = keyBackground
        self.functionalKeyBackground = functionalKeyBackground
        self.accentKeyBackground = accentKeyBackground
        self.keyText = keyText
        self.accentKeyText = accentKeyText
        self.keyShadow = keyShadow
    }

    public static func standard(isDark: Bool, accent: UIColor) -> NitrogramKeyboardTheme {
        if isDark {
            return NitrogramKeyboardTheme(
                background: UIColor(white: 0.13, alpha: 1.0),
                keyBackground: UIColor(white: 0.42, alpha: 1.0),
                functionalKeyBackground: UIColor(white: 0.27, alpha: 1.0),
                accentKeyBackground: accent,
                keyText: .white,
                accentKeyText: .white,
                keyShadow: UIColor(white: 0.0, alpha: 0.5)
            )
        } else {
            return NitrogramKeyboardTheme(
                background: UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1.0),
                keyBackground: .white,
                functionalKeyBackground: UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1.0),
                accentKeyBackground: accent,
                keyText: .black,
                accentKeyText: .white,
                keyShadow: UIColor(white: 0.5, alpha: 0.6)
            )
        }
    }
}

private final class NitrogramKeyButton: UIButton {
    let key: NitrogramKey

    init(key: NitrogramKey, theme: NitrogramKeyboardTheme) {
        self.key = key
        super.init(frame: CGRect())

        self.setTitle(key.title, for: .normal)
        self.layer.cornerRadius = 5.0
        self.layer.shadowColor = theme.keyShadow.cgColor
        self.layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
        self.layer.shadowRadius = 0.0
        self.layer.shadowOpacity = 1.0

        switch key.style {
        case .normal:
            self.backgroundColor = theme.keyBackground
            self.setTitleColor(theme.keyText, for: .normal)
        case .functional:
            self.backgroundColor = theme.functionalKeyBackground
            self.setTitleColor(theme.keyText, for: .normal)
        case .accent:
            self.backgroundColor = theme.accentKeyBackground
            self.setTitleColor(theme.accentKeyText, for: .normal)
        }

        let isWordKey = key.title.count > 1
        self.titleLabel?.font = UIFont.systemFont(ofSize: isWordKey ? 16.0 : 22.0)
        self.titleLabel?.adjustsFontSizeToFitWidth = true
        self.titleLabel?.minimumScaleFactor = 0.6
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }
}

/// A self-contained on-screen keyboard.
///
/// Following the project's view-frame rule, this never writes its own frame: the
/// owner sizes it (as a text view's `inputView`, UIKit does) and it lays its keys
/// out against `self.bounds`.
public final class NitrogramKeyboardView: UIView {
    public weak var delegate: NitrogramKeyboardViewDelegate?

    private var theme: NitrogramKeyboardTheme
    private var layouts: [NitrogramKeyboardLayout]
    private var layoutIndex: Int = 0
    private var page: NitrogramKeyboardPage = .letters
    private var isShifted: Bool = true
    private var returnTitle: String

    private var rows: [[NitrogramKey]] = []
    private var buttons: [[NitrogramKeyButton]] = []

    /// Called when the active letter layout changes, so the owner can remember it.
    public var layoutDidChange: ((String) -> Void)?

    public init(theme: NitrogramKeyboardTheme, layouts: [NitrogramKeyboardLayout] = NitrogramKeyboardLayout.all, initialLayoutIdentifier: String? = nil, returnTitle: String = "return") {
        self.theme = theme
        self.layouts = layouts.isEmpty ? [.qwerty] : layouts
        self.returnTitle = returnTitle
        super.init(frame: CGRect())

        if let identifier = initialLayoutIdentifier, let index = self.layouts.firstIndex(where: { $0.identifier == identifier }) {
            self.layoutIndex = index
        }

        self.backgroundColor = theme.background
        self.rebuildKeys()
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    public func updateTheme(_ theme: NitrogramKeyboardTheme) {
        self.theme = theme
        self.backgroundColor = theme.background
        self.rebuildKeys()
    }

    /// Height the keyboard wants for a given width. The owner decides the frame;
    /// this only advises.
    public static func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        // Four rows plus padding, kept close to the system keyboard's proportions.
        let rowHeight = min(54.0, max(40.0, width / 8.0))
        return rowHeight * 4.0 + 16.0
    }

    private var currentLayout: NitrogramKeyboardLayout {
        return self.layouts[self.layoutIndex]
    }

    private func rebuildKeys() {
        for row in self.buttons {
            for button in row {
                button.removeFromSuperview()
            }
        }
        self.buttons.removeAll()

        self.rows = nitrogramKeyRows(
            page: self.page,
            layout: self.currentLayout,
            isShifted: self.isShifted,
            returnTitle: self.returnTitle,
            hasMultipleLayouts: self.layouts.count > 1
        )

        for row in self.rows {
            var rowButtons: [NitrogramKeyButton] = []
            for key in row {
                let button = NitrogramKeyButton(key: key, theme: self.theme)
                button.addTarget(self, action: #selector(self.keyPressed(_:)), for: .touchUpInside)
                self.addSubview(button)
                rowButtons.append(button)
            }
            self.buttons.append(rowButtons)
        }

        self.setNeedsLayout()
    }

    @objc private func keyPressed(_ sender: NitrogramKeyButton) {
        switch sender.key.action {
        case let .character(value):
            NitrogramKeyboardTextTarget.insertText(value)
            if self.isShifted && self.page == .letters {
                // Shift is one-shot, like the system keyboard's non-locked state.
                self.isShifted = false
                self.rebuildKeys()
            }
        case .shift:
            self.isShifted = !self.isShifted
            self.rebuildKeys()
        case .backspace:
            NitrogramKeyboardTextTarget.deleteBackward()
        case .space:
            NitrogramKeyboardTextTarget.insertText(" ")
        case .returnKey:
            if self.delegate?.nitrogramKeyboardReturn() != true {
                NitrogramKeyboardTextTarget.insertText("
")
            }
        case let .page(page):
            self.page = page
            if page == .letters {
                self.isShifted = false
            }
            self.rebuildKeys()
        case .nextLayout:
            self.layoutIndex = (self.layoutIndex + 1) % self.layouts.count
            self.layoutDidChange?(self.currentLayout.identifier)
            self.rebuildKeys()
        case .dismiss:
            self.delegate?.nitrogramKeyboardDismiss()
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        let bounds = self.bounds
        guard bounds.width > 0.0, bounds.height > 0.0, !self.rows.isEmpty else {
            return
        }

        let horizontalInset: CGFloat = 3.0
        let verticalInset: CGFloat = 6.0
        let keySpacing: CGFloat = 5.0

        let availableHeight = bounds.height - verticalInset * 2.0
        let rowCount = CGFloat(self.rows.count)
        let rowHeight = (availableHeight - keySpacing * (rowCount - 1.0)) / rowCount

        var y = verticalInset
        for (rowIndex, row) in self.rows.enumerated() {
            let totalWeight = row.reduce(CGFloat(0.0), { $0 + $1.widthWeight })
            let availableWidth = bounds.width - horizontalInset * 2.0 - keySpacing * CGFloat(row.count - 1)
            let unitWidth = totalWeight > 0.0 ? availableWidth / totalWeight : 0.0

            var x = horizontalInset
            for (keyIndex, key) in row.enumerated() {
                let width = unitWidth * key.widthWeight
                if rowIndex < self.buttons.count && keyIndex < self.buttons[rowIndex].count {
                    self.buttons[rowIndex][keyIndex].frame = CGRect(x: x, y: y, width: width, height: rowHeight)
                }
                x += width + keySpacing
            }
            y += rowHeight + keySpacing
        }
    }
}

import Foundation

/// What a key does when it is tapped.
public enum NitrogramKeyAction: Equatable {
    case character(String)
    case shift
    case backspace
    case space
    case returnKey
    /// Switches between letters, numbers and symbols.
    case page(NitrogramKeyboardPage)
    /// Cycles through the enabled letter layouts.
    case nextLayout
    /// Hands control back to the system keyboard.
    case dismiss
}

public enum NitrogramKeyboardPage: Equatable {
    case letters
    case numbers
    case symbols
}

/// A single key. `width` is a share of the row, not a point value: the view
/// turns these into frames once it knows its own bounds.
public struct NitrogramKey: Equatable {
    public enum Style: Equatable {
        case normal
        case functional
        case accent
    }

    public let title: String
    public let action: NitrogramKeyAction
    public let style: Style
    public let widthWeight: CGFloat

    public init(title: String, action: NitrogramKeyAction, style: Style = .normal, widthWeight: CGFloat = 1.0) {
        self.title = title
        self.action = action
        self.style = style
        self.widthWeight = widthWeight
    }

    /// Convenience for a plain letter or digit.
    public static func character(_ value: String, widthWeight: CGFloat = 1.0) -> NitrogramKey {
        return NitrogramKey(title: value, action: .character(value), style: .normal, widthWeight: widthWeight)
    }
}

/// A named letter layout. Only letters differ between languages; the number and
/// symbol pages are shared.
public struct NitrogramKeyboardLayout: Equatable {
    public let identifier: String
    public let displayName: String
    /// Rows of letters, lowercase. Shift uppercases them for display and input.
    public let letterRows: [[String]]

    public init(identifier: String, displayName: String, letterRows: [[String]]) {
        self.identifier = identifier
        self.displayName = displayName
        self.letterRows = letterRows
    }

    public static let qwerty = NitrogramKeyboardLayout(
        identifier: "en",
        displayName: "English",
        letterRows: [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
            ["z", "x", "c", "v", "b", "n", "m"]
        ]
    )

    public static let jcuken = NitrogramKeyboardLayout(
        identifier: "ru",
        displayName: "Русская",
        letterRows: [
            ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х"],
            ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
            ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"]
        ]
    )

    public static let all: [NitrogramKeyboardLayout] = [.qwerty, .jcuken]

    public static func layout(withIdentifier identifier: String) -> NitrogramKeyboardLayout {
        return self.all.first(where: { $0.identifier == identifier }) ?? .qwerty
    }
}

private let numberRows: [[String]] = [
    ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    ["-", "/", ":", ";", "(", ")", "₽", "&", "@", "\""],
    [".", ",", "?", "!", "'"]
]

private let symbolRows: [[String]] = [
    ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
    ["_", "\\", "|", "~", "<", ">", "$", "€", "£", "•"],
    [".", ",", "?", "!", "'"]
]

/// Builds the rows of keys for the current page and state.
public func nitrogramKeyRows(page: NitrogramKeyboardPage, layout: NitrogramKeyboardLayout, isShifted: Bool, returnTitle: String, hasMultipleLayouts: Bool) -> [[NitrogramKey]] {
    var rows: [[NitrogramKey]] = []

    switch page {
    case .letters:
        for row in layout.letterRows {
            rows.append(row.map({ character in
                let title = isShifted ? character.uppercased() : character
                return NitrogramKey.character(title)
            }))
        }
        // Shift and backspace flank the last letter row.
        var lastRow: [NitrogramKey] = [
            NitrogramKey(title: isShifted ? "⇧" : "⇧", action: .shift, style: .functional, widthWeight: 1.5)
        ]
        lastRow.append(contentsOf: rows.removeLast())
        lastRow.append(NitrogramKey(title: "⌫", action: .backspace, style: .functional, widthWeight: 1.5))
        rows.append(lastRow)
    case .numbers, .symbols:
        let source = page == .numbers ? numberRows : symbolRows
        for row in source.dropLast() {
            rows.append(row.map({ NitrogramKey.character($0) }))
        }
        var lastRow: [NitrogramKey] = [
            NitrogramKey(title: page == .numbers ? "#+=" : "123", action: .page(page == .numbers ? .symbols : .numbers), style: .functional, widthWeight: 1.5)
        ]
        lastRow.append(contentsOf: (source.last ?? []).map({ NitrogramKey.character($0) }))
        lastRow.append(NitrogramKey(title: "⌫", action: .backspace, style: .functional, widthWeight: 1.5))
        rows.append(lastRow)
    }

    var bottomRow: [NitrogramKey] = [
        NitrogramKey(title: page == .letters ? "123" : "ABC", action: .page(page == .letters ? .numbers : .letters), style: .functional, widthWeight: 1.5)
    ]
    if hasMultipleLayouts {
        bottomRow.append(NitrogramKey(title: "🌐", action: .nextLayout, style: .functional, widthWeight: 1.0))
    }
    bottomRow.append(NitrogramKey(title: "⌨", action: .dismiss, style: .functional, widthWeight: 1.0))
    bottomRow.append(NitrogramKey(title: "space", action: .space, style: .normal, widthWeight: 4.0))
    bottomRow.append(NitrogramKey(title: returnTitle, action: .returnKey, style: .accent, widthWeight: 2.0))
    rows.append(bottomRow)

    return rows
}

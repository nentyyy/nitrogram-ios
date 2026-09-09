import Foundation
import UIKit

private final class NitrogramFirstResponderBox {
    static weak var responder: UIResponder?
}

private extension UIResponder {
    @objc func nitrogramCaptureFirstResponder(_ sender: Any?) {
        NitrogramFirstResponderBox.responder = self
    }
}

/// Types text into whatever is currently editing.
///
/// The chat composer has two interchangeable backends and neither exposes an
/// insertion API on its shared protocol. Both are `UIKeyInput` though, and while
/// the custom keyboard is on screen the editor is the first responder - so
/// routing through it works for either backend without touching the composer
/// protocol or its conformers.
public enum NitrogramKeyboardTextTarget {
    /// The object currently editing, if it accepts key input.
    public static var current: UIKeyInput? {
        NitrogramFirstResponderBox.responder = nil
        UIApplication.shared.sendAction(#selector(UIResponder.nitrogramCaptureFirstResponder(_:)), to: nil, from: nil, for: nil)
        return NitrogramFirstResponderBox.responder as? UIKeyInput
    }

    public static func insertText(_ text: String) {
        self.current?.insertText(text)
    }

    public static func deleteBackward() {
        self.current?.deleteBackward()
    }
}

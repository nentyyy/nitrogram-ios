import Foundation
import Postbox

/// Marks a message the peer deleted that Nitrogram kept in the local history
/// instead of removing.
///
/// The message stays exactly as it was; only this attribute is added, so
/// nothing about how it was received or rendered changes apart from the
/// deleted marker.
public class NitrogramDeletedMessageAttribute: MessageAttribute {
    /// When the deletion was observed, not when the message was sent.
    public let date: Int32

    public init(date: Int32) {
        self.date = date
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
    }
}

public extension Message {
    /// When the peer deleted this message, or nil if it is a normal message.
    var nitrogramDeletedDate: Int32? {
        for attribute in self.attributes {
            if let attribute = attribute as? NitrogramDeletedMessageAttribute {
                return attribute.date
            }
        }
        return nil
    }

    var isNitrogramDeleted: Bool {
        return self.nitrogramDeletedDate != nil
    }
}

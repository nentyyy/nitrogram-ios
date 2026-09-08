import Foundation

/// A value a mod setting can hold. Mods are authored in JavaScript, so the
/// representable types are deliberately limited to what survives a round trip
/// through JSON and JavaScriptCore without surprises.
public enum ModSettingValue: Equatable {
    case bool(Bool)
    case number(Double)
    case string(String)

    public init?(json: Any) {
        if let value = json as? Bool {
            self = .bool(value)
        } else if let value = json as? NSNumber {
            // NSNumber bridges both Bool and numeric literals; the Bool case is
            // handled above, so anything reaching here is genuinely numeric.
            self = .number(value.doubleValue)
        } else if let value = json as? String {
            self = .string(value)
        } else {
            return nil
        }
    }

    public var jsonValue: Any {
        switch self {
        case let .bool(value):
            return value
        case let .number(value):
            return value
        case let .string(value):
            return value
        }
    }

    public var boolValue: Bool {
        switch self {
        case let .bool(value):
            return value
        case let .number(value):
            return value != 0.0
        case let .string(value):
            return value == "true"
        }
    }

    public var doubleValue: Double {
        switch self {
        case let .bool(value):
            return value ? 1.0 : 0.0
        case let .number(value):
            return value
        case let .string(value):
            return Double(value) ?? 0.0
        }
    }

    public var stringValue: String {
        switch self {
        case let .bool(value):
            return value ? "true" : "false"
        case let .number(value):
            // Render whole numbers without a trailing ".0" so that values used
            // as identifiers stay readable.
            if value == value.rounded() && abs(value) < 1e15 {
                return String(Int64(value))
            }
            return String(value)
        case let .string(value):
            return value
        }
    }
}

/// One row of a mod's settings screen. The host renders these with native
/// components; a mod never builds UI itself.
public struct ModSettingItem {
    public enum Kind: Equatable {
        case toggle
        case slider(min: Double, max: Double, step: Double?)
        case segmented(options: [String])
        case text(placeholder: String)
    }

    public let key: String
    public let title: String
    public let subtitle: String?
    public let kind: Kind
    public let defaultValue: ModSettingValue

    public init(key: String, title: String, subtitle: String?, kind: Kind, defaultValue: ModSettingValue) {
        self.key = key
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.defaultValue = defaultValue
    }

    public init?(json: [String: Any]) {
        guard let key = json["key"] as? String, !key.isEmpty else {
            return nil
        }
        guard let type = json["type"] as? String else {
            return nil
        }
        self.key = key
        self.title = (json["title"] as? String) ?? key
        self.subtitle = json["subtitle"] as? String

        let declaredDefault = json["default"].flatMap({ ModSettingValue(json: $0) })

        switch type {
        case "switch", "toggle", "bool":
            self.kind = .toggle
            self.defaultValue = declaredDefault ?? .bool(false)
        case "slider", "number":
            let min = (json["min"] as? NSNumber)?.doubleValue ?? 0.0
            let max = (json["max"] as? NSNumber)?.doubleValue ?? 1.0
            // A zero or inverted range would make the rendered slider unusable.
            guard max > min else {
                return nil
            }
            let step = (json["step"] as? NSNumber)?.doubleValue
            self.kind = .slider(min: min, max: max, step: step.flatMap({ $0 > 0.0 ? $0 : nil }))
            self.defaultValue = declaredDefault ?? .number(min)
        case "segmented", "options":
            guard let options = json["options"] as? [String], !options.isEmpty else {
                return nil
            }
            self.kind = .segmented(options: options)
            self.defaultValue = declaredDefault ?? .string(options[0])
        case "text", "string":
            self.kind = .text(placeholder: (json["placeholder"] as? String) ?? "")
            self.defaultValue = declaredDefault ?? .string("")
        default:
            return nil
        }
    }
}

/// Everything the host knows about a mod without running a single line of its code.
public struct ModManifest {
    public static let currentFormat = 1

    public let format: Int
    public let name: String
    public let modDescription: String
    public let version: String
    public let author: String?
    public let extra: String?
    /// Raw base64 of a PNG or JPEG, without a `data:` prefix - same convention
    /// the Android client uses.
    public let iconBase64: String?
    public let settings: [ModSettingItem]

    public var hasSettings: Bool {
        return !self.settings.isEmpty
    }

    public init(format: Int, name: String, modDescription: String, version: String, author: String?, extra: String?, iconBase64: String?, settings: [ModSettingItem]) {
        self.format = format
        self.name = name
        self.modDescription = modDescription
        self.version = version
        self.author = author
        self.extra = extra
        self.iconBase64 = iconBase64
        self.settings = settings
    }

    public var iconData: Data? {
        guard let iconBase64 = self.iconBase64 else {
            return nil
        }
        return Data(base64Encoded: iconBase64, options: [.ignoreUnknownCharacters])
    }

    public var defaultValues: [String: ModSettingValue] {
        var result: [String: ModSettingValue] = [:]
        for item in self.settings {
            result[item.key] = item.defaultValue
        }
        return result
    }
}

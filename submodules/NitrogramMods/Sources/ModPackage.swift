import Foundation

public enum ModPackageError: Error {
    case notJSON
    case unsupportedFormat(Int)
    case missingField(String)
    case emptySource
}

/// A `.ngmod` file: a single self-contained JSON document holding the mod's
/// metadata, its declarative settings schema and its JavaScript source.
///
/// Keeping a mod to exactly one file is deliberate - it is what makes a mod
/// shareable in a chat the same way the Android client shares a `.so`.
public struct ModPackage {
    public let manifest: ModManifest
    public let source: String

    public init(manifest: ModManifest, source: String) {
        self.manifest = manifest
        self.source = source
    }

    public static func parse(data: Data) throws -> ModPackage {
        let object = try? JSONSerialization.jsonObject(with: data, options: [])
        guard let json = object as? [String: Any] else {
            throw ModPackageError.notJSON
        }

        let format = (json["format"] as? NSNumber)?.intValue ?? ModManifest.currentFormat
        guard format <= ModManifest.currentFormat else {
            // A newer package may rely on host APIs this build does not have,
            // so refuse it instead of running it half-supported.
            throw ModPackageError.unsupportedFormat(format)
        }

        guard let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            throw ModPackageError.missingField("name")
        }
        guard let source = json["source"] as? String, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModPackageError.emptySource
        }

        var settings: [ModSettingItem] = []
        if let rawSettings = json["settings"] as? [[String: Any]] {
            for rawItem in rawSettings {
                if let item = ModSettingItem(json: rawItem) {
                    settings.append(item)
                }
            }
        }

        let manifest = ModManifest(
            format: format,
            name: name,
            modDescription: (json["description"] as? String) ?? "",
            version: (json["version"] as? String) ?? "1.0",
            author: json["author"] as? String,
            extra: json["extra"] as? String,
            iconBase64: json["icon"] as? String,
            settings: settings
        )

        return ModPackage(manifest: manifest, source: source)
    }

    public static func parse(fileAt url: URL) throws -> ModPackage {
        let data = try Data(contentsOf: url)
        return try self.parse(data: data)
    }

    /// Stable identity for a mod, so that re-importing the same file replaces
    /// the existing entry rather than creating a duplicate.
    public var identifier: String {
        let seed = "\(self.manifest.name)|\(self.manifest.version)"
        return "m" + String(format: "%08x", UInt32(truncatingIfNeeded: seed.stableHash))
    }
}

private extension String {
    /// Swift's `hashValue` is seeded per process, which would change a mod's
    /// identity on every launch. This is a plain FNV-1a so identity is stable.
    var stableHash: UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in self.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

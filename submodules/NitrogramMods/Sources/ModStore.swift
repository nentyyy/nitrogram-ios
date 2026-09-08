import Foundation

public struct InstalledMod {
    public let identifier: String
    public let package: ModPackage
    public let isEnabled: Bool
    public let values: [String: ModSettingValue]

    public var manifest: ModManifest {
        return self.package.manifest
    }
}

/// On-disk home for imported mods.
///
/// Layout under `rootURL`:
///   packages/<identifier>.ngmod   - the imported file, byte for byte
///   state.json                    - enabled flags and setting values
///
/// Keeping the original file untouched means a mod can always be re-exported
/// and shared onwards exactly as it was received.
public final class ModStore {
    private let rootURL: URL
    private let packagesURL: URL
    private let stateURL: URL
    private let fileManager = FileManager.default

    private var state: [String: ModState] = [:]

    private struct ModState {
        var isEnabled: Bool
        var values: [String: ModSettingValue]
    }

    public init(rootURL: URL) {
        self.rootURL = rootURL
        self.packagesURL = rootURL.appendingPathComponent("packages", isDirectory: true)
        self.stateURL = rootURL.appendingPathComponent("state.json", isDirectory: false)
        self.loadState()
    }

    // MARK: - Reading

    public func installedMods() -> [InstalledMod] {
        guard let names = try? self.fileManager.contentsOfDirectory(atPath: self.packagesURL.path) else {
            return []
        }

        var result: [InstalledMod] = []
        for name in names.sorted() where name.hasSuffix(".ngmod") {
            let url = self.packagesURL.appendingPathComponent(name)
            guard let package = try? ModPackage.parse(fileAt: url) else {
                continue
            }
            let identifier = String(name.dropLast(".ngmod".count))
            let modState = self.state[identifier]
            result.append(InstalledMod(
                identifier: identifier,
                package: package,
                isEnabled: modState?.isEnabled ?? false,
                values: self.resolvedValues(package: package, stored: modState?.values ?? [:])
            ))
        }
        return result
    }

    public func mod(withIdentifier identifier: String) -> InstalledMod? {
        return self.installedMods().first(where: { $0.identifier == identifier })
    }

    /// Stored values only cover keys the user has actually changed; everything
    /// else falls back to the manifest default.
    private func resolvedValues(package: ModPackage, stored: [String: ModSettingValue]) -> [String: ModSettingValue] {
        var values = package.manifest.defaultValues
        for (key, value) in stored {
            values[key] = value
        }
        return values
    }

    // MARK: - Mutating

    @discardableResult
    public func importMod(from url: URL) throws -> InstalledMod {
        let data = try Data(contentsOf: url)
        let package = try ModPackage.parse(data: data)
        let identifier = package.identifier

        try self.fileManager.createDirectory(at: self.packagesURL, withIntermediateDirectories: true, attributes: nil)
        let destination = self.packagesURL.appendingPathComponent("\(identifier).ngmod")
        if self.fileManager.fileExists(atPath: destination.path) {
            try self.fileManager.removeItem(at: destination)
        }
        try data.write(to: destination, options: .atomic)

        // Re-importing an updated build of a mod keeps the user's settings, but
        // a brand new mod starts out disabled: nothing runs without consent.
        if self.state[identifier] == nil {
            self.state[identifier] = ModState(isEnabled: false, values: [:])
            self.saveState()
        }

        guard let installed = self.mod(withIdentifier: identifier) else {
            throw ModPackageError.notJSON
        }
        return installed
    }

    public func remove(identifier: String) {
        let destination = self.packagesURL.appendingPathComponent("\(identifier).ngmod")
        try? self.fileManager.removeItem(at: destination)
        self.state.removeValue(forKey: identifier)
        self.saveState()
    }

    public func setEnabled(_ isEnabled: Bool, identifier: String) {
        var modState = self.state[identifier] ?? ModState(isEnabled: false, values: [:])
        modState.isEnabled = isEnabled
        self.state[identifier] = modState
        self.saveState()
    }

    public func setValue(_ value: ModSettingValue, forKey key: String, identifier: String) {
        var modState = self.state[identifier] ?? ModState(isEnabled: false, values: [:])
        modState.values[key] = value
        self.state[identifier] = modState
        self.saveState()
    }

    // MARK: - Persistence

    private func loadState() {
        guard let data = try? Data(contentsOf: self.stateURL),
              let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            return
        }

        for (identifier, rawState) in json {
            guard let rawState = rawState as? [String: Any] else {
                continue
            }
            var values: [String: ModSettingValue] = [:]
            if let rawValues = rawState["values"] as? [String: Any] {
                for (key, rawValue) in rawValues {
                    if let value = ModSettingValue(json: rawValue) {
                        values[key] = value
                    }
                }
            }
            self.state[identifier] = ModState(
                isEnabled: (rawState["enabled"] as? Bool) ?? false,
                values: values
            )
        }
    }

    private func saveState() {
        var json: [String: Any] = [:]
        for (identifier, modState) in self.state {
            var values: [String: Any] = [:]
            for (key, value) in modState.values {
                values[key] = value.jsonValue
            }
            json[identifier] = ["enabled": modState.isEnabled, "values": values]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []) else {
            return
        }
        try? self.fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true, attributes: nil)
        try? data.write(to: self.stateURL, options: .atomic)
    }
}

import Foundation

/// Host events a mod can subscribe to with `Nitrogram.on(event, handler)`.
public enum ModEvent {
    public static let modsLoaded = "modsLoaded"
    public static let appDidBecomeActive = "appDidBecomeActive"
    public static let appWillResignActive = "appWillResignActive"
    public static let chatOpened = "chatOpened"
    public static let messageSent = "messageSent"
    public static let messageReceived = "messageReceived"
}

public struct ModLogEntry {
    public let modIdentifier: String
    public let modName: String
    public let message: String
    public let isError: Bool
    public let date: Date
}

/// Owns the installed mods and the runtimes of the enabled ones.
///
/// The public API is main-thread only. Runtime callbacks arrive on each mod's
/// private queue and are hopped back to main here, so callers never have to
/// think about the mod queues.
public final class ModManager: ModRuntimeDelegate {
    public static let logCapacity = 200

    private let store: ModStore
    private var runtimes: [String: ModRuntime] = [:]
    private var log: [ModLogEntry] = []

    public var logDidUpdate: (() -> Void)?

    public init(rootURL: URL) {
        self.store = ModStore(rootURL: rootURL)
    }

    // MARK: - Catalogue

    public func installedMods() -> [InstalledMod] {
        return self.store.installedMods()
    }

    public func mod(withIdentifier identifier: String) -> InstalledMod? {
        return self.store.mod(withIdentifier: identifier)
    }

    public var enabledModCount: Int {
        return self.runtimes.count
    }

    // MARK: - Lifecycle

    /// Starts every mod the user has enabled. Call once, after the account is up.
    public func startEnabledMods() {
        for mod in self.store.installedMods() where mod.isEnabled {
            self.startRuntime(for: mod)
        }
        self.dispatch(event: ModEvent.modsLoaded, payload: [:])
    }

    @discardableResult
    public func importMod(from url: URL) throws -> InstalledMod {
        let mod = try self.store.importMod(from: url)
        // An imported mod is inert until the user turns it on, so there is
        // nothing to start here.
        return mod
    }

    public func setEnabled(_ isEnabled: Bool, identifier: String) {
        self.store.setEnabled(isEnabled, identifier: identifier)

        if isEnabled {
            guard self.runtimes[identifier] == nil, let mod = self.store.mod(withIdentifier: identifier) else {
                return
            }
            self.startRuntime(for: mod)
        } else {
            self.runtimes[identifier]?.stop()
            self.runtimes.removeValue(forKey: identifier)
        }
    }

    public func remove(identifier: String) {
        self.runtimes[identifier]?.stop()
        self.runtimes.removeValue(forKey: identifier)
        self.store.remove(identifier: identifier)
    }

    public func setValue(_ value: ModSettingValue, forKey key: String, identifier: String) {
        self.store.setValue(value, forKey: key, identifier: identifier)
        guard let runtime = self.runtimes[identifier], let mod = self.store.mod(withIdentifier: identifier) else {
            return
        }
        runtime.updateValues(mod.values)
    }

    // MARK: - Events

    public func dispatch(event: String, payload: [String: Any]) {
        for runtime in self.runtimes.values {
            runtime.dispatch(event: event, payload: payload)
        }
    }

    // MARK: - Log

    public func logEntries() -> [ModLogEntry] {
        return self.log
    }

    public func clearLog() {
        self.log.removeAll()
        self.logDidUpdate?()
    }

    // MARK: - ModRuntimeDelegate

    public func modRuntime(_ runtime: ModRuntime, didSetValue value: ModSettingValue, forKey key: String) {
        let identifier = runtime.identifier
        DispatchQueue.main.async { [weak self] in
            // The mod changed its own setting, so only persistence is needed -
            // pushing the value back would re-enter applySettings for no reason.
            self?.store.setValue(value, forKey: key, identifier: identifier)
        }
    }

    public func modRuntime(_ runtime: ModRuntime, didLog message: String, isError: Bool) {
        let entry = ModLogEntry(
            modIdentifier: runtime.identifier,
            modName: runtime.manifest.name,
            message: message,
            isError: isError,
            date: Date()
        )
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }
            self.log.append(entry)
            if self.log.count > ModManager.logCapacity {
                self.log.removeFirst(self.log.count - ModManager.logCapacity)
            }
            self.logDidUpdate?()
        }
    }

    // MARK: - Private

    private func startRuntime(for mod: InstalledMod) {
        // Idempotent, so calling startEnabledMods() more than once cannot leave
        // two runtimes running the same mod.
        guard self.runtimes[mod.identifier] == nil else {
            return
        }
        let runtime = ModRuntime(mod: mod, delegate: self)
        self.runtimes[mod.identifier] = runtime
        runtime.start()
    }
}

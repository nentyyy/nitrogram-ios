import Foundation
import JavaScriptCore

public protocol ModRuntimeDelegate: AnyObject {
    /// A mod asked to persist one of its settings.
    func modRuntime(_ runtime: ModRuntime, didSetValue value: ModSettingValue, forKey key: String)
    /// A line the mod wrote through `Nitrogram.log`, or a runtime error.
    func modRuntime(_ runtime: ModRuntime, didLog message: String, isError: Bool)
}

/// Runs a single mod's JavaScript in its own isolated context.
///
/// Everything happens on a private serial queue rather than the main thread: a
/// mod that loops forever burns one background core instead of freezing the UI.
/// JavaScriptCore has no public execution watchdog, so this containment is the
/// realistic protection available.
public final class ModRuntime {
    public let identifier: String
    public let manifest: ModManifest

    public weak var delegate: ModRuntimeDelegate?

    private let source: String
    private let queue: DispatchQueue

    private var context: JSContext?
    private var eventHandlers: [String: [JSValue]] = [:]
    private var values: [String: ModSettingValue]
    private var isStarted = false

    public init(mod: InstalledMod, delegate: ModRuntimeDelegate?) {
        self.identifier = mod.identifier
        self.manifest = mod.manifest
        self.source = mod.package.source
        self.values = mod.values
        self.delegate = delegate
        self.queue = DispatchQueue(label: "org.nitrogram.mod.\(mod.identifier)", qos: .utility)
    }

    // MARK: - Lifecycle

    public func start() {
        self.queue.async { [weak self] in
            guard let self = self, !self.isStarted else {
                return
            }
            self.isStarted = true

            guard let context = JSContext() else {
                self.log("failed to create a JavaScript context", isError: true)
                return
            }
            self.context = context
            context.name = self.manifest.name
            context.exceptionHandler = { [weak self] _, exception in
                let message = exception?.toString() ?? "unknown error"
                self?.log(message, isError: true)
            }

            self.installHostAPI(in: context)

            context.evaluateScript(self.source, withSourceURL: URL(string: "nitrogram-mod://\(self.identifier).js"))

            // Mirrors the Android contract: apply() once, then applySettings()
            // with whatever the user had stored.
            self.invokeGlobal("apply", arguments: [])
            self.invokeApplySettings()
        }
    }

    public func stop() {
        self.queue.async { [weak self] in
            guard let self = self else {
                return
            }
            self.invokeGlobal("unapply", arguments: [])
            self.eventHandlers.removeAll()
            self.context = nil
            self.isStarted = false
        }
    }

    public func updateValues(_ values: [String: ModSettingValue]) {
        self.queue.async { [weak self] in
            guard let self = self else {
                return
            }
            self.values = values
            self.invokeApplySettings()
        }
    }

    /// Delivers a host event to every handler the mod registered for it.
    public func dispatch(event: String, payload: [String: Any]) {
        self.queue.async { [weak self] in
            guard let self = self, let context = self.context else {
                return
            }
            guard let handlers = self.eventHandlers[event], !handlers.isEmpty else {
                return
            }
            let argument = JSValue(object: payload, in: context) ?? JSValue(undefinedIn: context)!
            for handler in handlers {
                handler.call(withArguments: [argument])
            }
        }
    }

    // MARK: - Host API

    private func installHostAPI(in context: JSContext) {
        guard let namespace = JSValue(newObjectIn: context) else {
            return
        }

        let logBlock: @convention(block) (String) -> Void = { [weak self] message in
            self?.log(message, isError: false)
        }
        namespace.setObject(logBlock, forKeyedSubscript: "log" as NSString)

        let onBlock: @convention(block) (String, JSValue) -> Void = { [weak self] event, handler in
            guard let self = self, !event.isEmpty, !handler.isUndefined, !handler.isNull else {
                return
            }
            var handlers = self.eventHandlers[event] ?? []
            handlers.append(handler)
            self.eventHandlers[event] = handlers
        }
        namespace.setObject(onBlock, forKeyedSubscript: "on" as NSString)

        // Mod metadata, so a mod can report its own version without hardcoding it.
        if let info = JSValue(newObjectIn: context) {
            info.setObject(self.identifier, forKeyedSubscript: "id" as NSString)
            info.setObject(self.manifest.name, forKeyedSubscript: "name" as NSString)
            info.setObject(self.manifest.version, forKeyedSubscript: "version" as NSString)
            namespace.setObject(info, forKeyedSubscript: "mod" as NSString)
        }

        if let settings = JSValue(newObjectIn: context) {
            let getBlock: @convention(block) (String) -> Any? = { [weak self] key in
                return self?.values[key]?.jsonValue
            }
            settings.setObject(getBlock, forKeyedSubscript: "get" as NSString)

            let setBlock: @convention(block) (String, JSValue) -> Void = { [weak self] key, rawValue in
                guard let self = self, !key.isEmpty else {
                    return
                }
                guard let value = ModRuntime.settingValue(from: rawValue) else {
                    return
                }
                self.values[key] = value
                if let delegate = self.delegate {
                    delegate.modRuntime(self, didSetValue: value, forKey: key)
                }
            }
            settings.setObject(setBlock, forKeyedSubscript: "set" as NSString)
            namespace.setObject(settings, forKeyedSubscript: "settings" as NSString)
        }

        context.setObject(namespace, forKeyedSubscript: "Nitrogram" as NSString)
    }

    private static func settingValue(from value: JSValue) -> ModSettingValue? {
        if value.isBoolean {
            return .bool(value.toBool())
        } else if value.isNumber {
            return .number(value.toDouble())
        } else if value.isString {
            return .string(value.toString() ?? "")
        }
        return nil
    }

    // MARK: - Calling into the mod

    private func invokeApplySettings() {
        var json: [String: Any] = [:]
        for (key, value) in self.values {
            json[key] = value.jsonValue
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        self.invokeGlobal("applySettings", arguments: [string])
    }

    private func invokeGlobal(_ name: String, arguments: [Any]) {
        guard let context = self.context else {
            return
        }
        guard let function = context.objectForKeyedSubscript(name), !function.isUndefined, !function.isNull else {
            return
        }
        function.call(withArguments: arguments)
    }

    private func log(_ message: String, isError: Bool) {
        guard let delegate = self.delegate else {
            return
        }
        delegate.modRuntime(self, didLog: message, isError: isError)
    }
}

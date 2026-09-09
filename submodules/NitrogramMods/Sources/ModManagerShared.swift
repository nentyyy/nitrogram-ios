import Foundation
#if canImport(UIKit)
import UIKit
#endif

public extension ModManager {
    /// The app-wide mod manager.
    ///
    /// Mods live in Application Support rather than Documents so they do not
    /// show up as user documents, and are excluded from iCloud backup: a mod is
    /// re-importable, and backing up executable content is not worth the risk.
    static let shared: ModManager = {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        var rootURL = base.appendingPathComponent("nitrogram-mods", isDirectory: true)

        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? rootURL.setResourceValues(resourceValues)

        let manager = ModManager(rootURL: rootURL)
        manager.observeApplicationLifecycle()
        manager.startEnabledMods()
        return manager
    }()
}

extension ModManager {
    /// Forwards app foreground/background transitions to the mods.
    ///
    /// Doing it here rather than from the app delegate keeps these two events
    /// entirely inside the mods module - nothing in the host app has to know
    /// about them.
    func observeApplicationLifecycle() {
        #if canImport(UIKit)
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.dispatch(event: ModEvent.appDidBecomeActive, payload: [:])
        }
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.dispatch(event: ModEvent.appWillResignActive, payload: [:])
        }
        #endif
    }
}

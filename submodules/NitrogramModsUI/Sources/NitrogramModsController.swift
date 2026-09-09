import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import NitrogramMods

private final class NitrogramModsArguments {
    let importMod: () -> Void
    let openMod: (String) -> Void
    let setModEnabled: (String, Bool) -> Void
    let openLog: () -> Void

    init(
        importMod: @escaping () -> Void,
        openMod: @escaping (String) -> Void,
        setModEnabled: @escaping (String, Bool) -> Void,
        openLog: @escaping () -> Void
    ) {
        self.importMod = importMod
        self.openMod = openMod
        self.setModEnabled = setModEnabled
        self.openLog = openLog
    }
}

private enum NitrogramModsSection: Int32 {
    case importSection
    case mods
    case log
}

struct ModListEntryData: Equatable {
    let identifier: String
    let name: String
    let version: String
    let summary: String
    let isEnabled: Bool
}

private enum NitrogramModsEntry: ItemListNodeEntry {
    case importAction(String)
    case importInfo(String)
    case modsHeader(String)
    case modsEmpty(String)
    case mod(Int32, ModListEntryData)
    case logAction(String)
    case logInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .importAction, .importInfo:
            return NitrogramModsSection.importSection.rawValue
        case .modsHeader, .modsEmpty, .mod:
            return NitrogramModsSection.mods.rawValue
        case .logAction, .logInfo:
            return NitrogramModsSection.log.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .importAction:
            return 0
        case .importInfo:
            return 1
        case .modsHeader:
            return 2
        case .modsEmpty:
            return 3
        case let .mod(index, _):
            // Offset well past the fixed rows so ordering stays stable as the
            // list grows.
            return 100 + index
        case .logAction:
            return 10000
        case .logInfo:
            return 10001
        }
    }

    static func <(lhs: NitrogramModsEntry, rhs: NitrogramModsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NitrogramModsArguments
        switch self {
        case let .importAction(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importMod()
            })
        case let .importInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .modsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .modsEmpty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .mod(_, mod):
            return ItemListSwitchItem(presentationData: presentationData, title: mod.name, text: mod.summary, value: mod.isEnabled, maximumNumberOfLines: 2, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setModEnabled(mod.identifier, value)
            }, action: {
                arguments.openMod(mod.identifier)
            })
        case let .logAction(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openLog()
            })
        case let .logInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func nitrogramModsEntries(mods: [ModListEntryData]) -> [NitrogramModsEntry] {
    var entries: [NitrogramModsEntry] = []

    entries.append(.importAction("Import Mod..."))
    entries.append(.importInfo("A mod is a single .ngmod file. Send one to yourself in a chat or save it to Files, then import it here."))

    entries.append(.modsHeader("INSTALLED MODS"))
    if mods.isEmpty {
        entries.append(.modsEmpty("No mods installed yet."))
    } else {
        var index: Int32 = 0
        for mod in mods {
            entries.append(.mod(index, mod))
            index += 1
        }
    }

    entries.append(.logAction("Mod Log"))
    entries.append(.logInfo("Anything a mod reports, plus any error it runs into."))

    return entries
}

func modListEntryData(from mod: InstalledMod) -> ModListEntryData {
    var summary = mod.manifest.modDescription
    if summary.isEmpty {
        summary = "Version " + mod.manifest.version
    }
    return ModListEntryData(
        identifier: mod.identifier,
        name: mod.manifest.name,
        version: mod.manifest.version,
        summary: summary,
        isEnabled: mod.isEnabled
    )
}

/// Retains itself until the picker reports back - UIKit holds a document
/// picker's delegate weakly, so something has to keep it alive.
private final class ModDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private var retainedSelf: ModDocumentPickerDelegate?
    private let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
        super.init()
        self.retainedSelf = self
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completion(urls.first)
        self.retainedSelf = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.completion(nil)
        self.retainedSelf = nil
    }
}

public func nitrogramModsController(context: AccountContext) -> ViewController {
    let manager = ModManager.shared

    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var getControllerImpl: (() -> ViewController?)?

    let modsPromise = ValuePromise<[ModListEntryData]>([], ignoreRepeated: true)
    let reload: () -> Void = {
        modsPromise.set(manager.installedMods().map(modListEntryData(from:)))
    }
    reload()

    let presentMessage: (String) -> Void = { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: text, actions: [
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
        ]))
    }

    let arguments = NitrogramModsArguments(
        importMod: {
            guard #available(iOS 14.0, *) else {
                presentMessage("Importing mods requires iOS 14 or later.")
                return
            }
            guard let hostController = getControllerImpl?() else {
                return
            }
            let delegate = ModDocumentPickerDelegate(completion: { url in
                guard let url = url else {
                    return
                }
                do {
                    let mod = try manager.importMod(from: url)
                    reload()
                    presentMessage("Imported " + mod.manifest.name + " " + mod.manifest.version + ". Turn it on to start it.")
                } catch {
                    presentMessage("That file is not a valid mod.")
                }
            })
            // Any file type is accepted because `.ngmod` is a custom extension
            // the system does not recognise; the contents are validated instead.
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data], asCopy: true)
            picker.delegate = delegate
            picker.allowsMultipleSelection = false
            (hostController as UIViewController).present(picker, animated: true, completion: nil)
        },
        openMod: { identifier in
            guard let mod = manager.mod(withIdentifier: identifier) else {
                return
            }
            pushControllerImpl?(modDetailController(context: context, modIdentifier: mod.identifier, modsUpdated: reload))
        },
        setModEnabled: { identifier, isEnabled in
            manager.setEnabled(isEnabled, identifier: identifier)
            reload()
        },
        openLog: {
            pushControllerImpl?(modLogController(context: context))
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        modsPromise.get()
    )
    |> map { presentationData, mods -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Mods"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: nitrogramModsEntries(mods: mods), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    getControllerImpl = { [weak controller] in
        return controller
    }
    return controller
}

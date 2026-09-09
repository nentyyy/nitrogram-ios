import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import NitrogramMods

private final class ModDetailArguments {
    let setEnabled: (Bool) -> Void
    let setValue: (String, ModSettingValue) -> Void
    let openOptions: (Int) -> Void
    let deleteMod: () -> Void

    init(
        setEnabled: @escaping (Bool) -> Void,
        setValue: @escaping (String, ModSettingValue) -> Void,
        openOptions: @escaping (Int) -> Void,
        deleteMod: @escaping () -> Void
    ) {
        self.setEnabled = setEnabled
        self.setValue = setValue
        self.openOptions = openOptions
        self.deleteMod = deleteMod
    }
}

private enum ModDetailSection: Int32 {
    case state
    case info
    case settings
    case delete
}

private struct ModDetailState: Equatable {
    var isEnabled: Bool
    var values: [String: ModSettingValue]
}

private enum ModDetailEntry: ItemListNodeEntry {
    case enabledSwitch(String, Bool)
    case enabledInfo(String)
    case infoHeader(String)
    case infoText(String)
    case settingsHeader(String)
    case settingToggle(Int32, String, String?, String, Bool)
    case settingChoice(Int32, String, String, Int)
    case settingText(Int32, String, String, String)
    case deleteAction(String)

    var section: ItemListSectionId {
        switch self {
        case .enabledSwitch, .enabledInfo:
            return ModDetailSection.state.rawValue
        case .infoHeader, .infoText:
            return ModDetailSection.info.rawValue
        case .settingsHeader, .settingToggle, .settingChoice, .settingText:
            return ModDetailSection.settings.rawValue
        case .deleteAction:
            return ModDetailSection.delete.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .enabledSwitch:
            return 0
        case .enabledInfo:
            return 1
        case .infoHeader:
            return 2
        case .infoText:
            return 3
        case .settingsHeader:
            return 4
        case let .settingToggle(index, _, _, _, _):
            return 100 + index
        case let .settingChoice(index, _, _, _):
            return 100 + index
        case let .settingText(index, _, _, _):
            return 100 + index
        case .deleteAction:
            return 10000
        }
    }

    static func <(lhs: ModDetailEntry, rhs: ModDetailEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ModDetailArguments
        switch self {
        case let .enabledSwitch(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setEnabled(value)
            })
        case let .enabledInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .infoHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .infoText(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .settingsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .settingToggle(_, key, subtitle, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, text: subtitle, value: value, maximumNumberOfLines: 2, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setValue(key, .bool(value))
            })
        case let .settingChoice(_, title, label, itemIndex):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openOptions(itemIndex)
            })
        case let .settingText(_, key, title, value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: title, font: Font.regular(17.0), textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: "", sectionId: self.section, textUpdated: { text in
                arguments.setValue(key, .string(text))
            }, action: {})
        case let .deleteAction(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.deleteMod()
            })
        }
    }
}

/// Discrete steps for a slider setting. Sliders are rendered as a choice list
/// because ItemListUI has no slider row, and a stepped list keeps the value
/// exact and readable.
func sliderSteps(min: Double, max: Double, step: Double?) -> [Double] {
    let resolvedStep: Double
    if let step = step, step > 0.0 {
        resolvedStep = step
    } else {
        resolvedStep = (max - min) / 10.0
    }
    guard resolvedStep > 0.0 else {
        return [min]
    }

    var values: [Double] = []
    var current = min
    // Cap the list so a mod declaring a tiny step cannot generate thousands of rows.
    while current <= max + resolvedStep * 0.001 && values.count < 101 {
        values.append((current * 10000.0).rounded() / 10000.0)
        current += resolvedStep
    }
    if values.isEmpty {
        values.append(min)
    }
    return values
}

private func modDetailEntries(mod: InstalledMod, state: ModDetailState, presentationData: PresentationData) -> [ModDetailEntry] {
    var entries: [ModDetailEntry] = []

    entries.append(.enabledSwitch("Enabled", state.isEnabled))
    entries.append(.enabledInfo(state.isEnabled ? "The mod is running." : "The mod is installed but not running."))

    var info = mod.manifest.modDescription
    if let author = mod.manifest.author, !author.isEmpty {
        if !info.isEmpty {
            info += "\n\n"
        }
        info += "By " + author
    }
    if let extra = mod.manifest.extra, !extra.isEmpty {
        if !info.isEmpty {
            info += "\n\n"
        }
        info += extra
    }
    if !info.isEmpty {
        entries.append(.infoHeader("ABOUT " + mod.manifest.name.uppercased() + " " + mod.manifest.version))
        entries.append(.infoText(info))
    }

    if !mod.manifest.settings.isEmpty {
        entries.append(.settingsHeader("SETTINGS"))
        var index: Int32 = 0
        for item in mod.manifest.settings {
            let value = state.values[item.key] ?? item.defaultValue
            switch item.kind {
            case .toggle:
                entries.append(.settingToggle(index, item.key, item.subtitle, item.title, value.boolValue))
            case .segmented, .slider:
                entries.append(.settingChoice(index, item.title, value.stringValue, Int(index)))
            case .text:
                entries.append(.settingText(index, item.key, item.title, value.stringValue))
            }
            index += 1
        }
    }

    entries.append(.deleteAction("Delete Mod"))

    let _ = presentationData
    return entries
}

func modDetailController(context: AccountContext, modIdentifier: String, modsUpdated: @escaping () -> Void) -> ViewController {
    let manager = ModManager.shared

    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?

    guard let initialMod = manager.mod(withIdentifier: modIdentifier) else {
        // The mod vanished between screens; hand back an empty list rather than
        // crashing on a force unwrap.
        return ItemListController(context: context, state: context.sharedContext.presentationData
        |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Mod"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
            let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: [ModDetailEntry](), style: .blocks)
            return (controllerState, (listState, ModDetailArguments(setEnabled: { _ in }, setValue: { _, _ in }, openOptions: { _ in }, deleteMod: {})))
        })
    }

    let statePromise = ValuePromise<ModDetailState>(ModDetailState(isEnabled: initialMod.isEnabled, values: initialMod.values), ignoreRepeated: true)
    let reload: () -> Void = {
        guard let mod = manager.mod(withIdentifier: modIdentifier) else {
            return
        }
        statePromise.set(ModDetailState(isEnabled: mod.isEnabled, values: mod.values))
        modsUpdated()
    }

    let arguments = ModDetailArguments(
        setEnabled: { isEnabled in
            manager.setEnabled(isEnabled, identifier: modIdentifier)
            reload()
        },
        setValue: { key, value in
            manager.setValue(value, forKey: key, identifier: modIdentifier)
            reload()
        },
        openOptions: { itemIndex in
            // Resolved from the manifest on tap, so the row only has to carry an index.
            let settings = manager.mod(withIdentifier: modIdentifier)?.manifest.settings ?? initialMod.manifest.settings
            guard itemIndex >= 0 && itemIndex < settings.count else {
                return
            }
            let item = settings[itemIndex]

            let options: [(String, ModSettingValue)]
            switch item.kind {
            case let .segmented(choices):
                options = choices.map({ ($0, ModSettingValue.string($0)) })
            case let .slider(min, max, step):
                options = sliderSteps(min: min, max: max, step: step).map({ value -> (String, ModSettingValue) in
                    let settingValue = ModSettingValue.number(value)
                    return (settingValue.stringValue, settingValue)
                })
            default:
                return
            }

            let currentValue = manager.mod(withIdentifier: modIdentifier)?.values[item.key] ?? item.defaultValue
            pushControllerImpl?(modOptionsController(context: context, title: item.title, options: options, selected: currentValue, apply: { value in
                manager.setValue(value, forKey: item.key, identifier: modIdentifier)
                reload()
            }))
        },
        deleteMod: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentControllerImpl?(textAlertController(context: context, title: nil, text: "Delete " + initialMod.manifest.name + "? Its settings are removed too.", actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                    manager.remove(identifier: modIdentifier)
                    modsUpdated()
                    dismissImpl?()
                })
            ]))
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let mod = manager.mod(withIdentifier: modIdentifier) ?? initialMod
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(mod.manifest.name), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: modDetailEntries(mod: mod, state: state, presentationData: presentationData), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}

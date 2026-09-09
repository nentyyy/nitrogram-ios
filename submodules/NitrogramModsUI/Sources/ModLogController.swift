import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import TextFormat
import NitrogramMods

private final class ModLogArguments {
    let clearLog: () -> Void

    init(clearLog: @escaping () -> Void) {
        self.clearLog = clearLog
    }
}

private enum ModLogSection: Int32 {
    case entries
    case actions
}

private struct ModLogLine: Equatable {
    let title: String
    let text: String
    let isError: Bool
}

private enum ModLogEntryItem: ItemListNodeEntry {
    case empty(String)
    case line(Int32, ModLogLine)
    case clearAction(String)

    var section: ItemListSectionId {
        switch self {
        case .empty, .line:
            return ModLogSection.entries.rawValue
        case .clearAction:
            return ModLogSection.actions.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .empty:
            return 0
        case let .line(index, _):
            return 100 + index
        case .clearAction:
            return 10000
        }
    }

    static func <(lhs: ModLogEntryItem, rhs: ModLogEntryItem) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ModLogArguments
        switch self {
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .line(_, line):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: line.title, text: line.text, style: .blocks, textColor: line.isError ? .accent : .primary, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: nil)
        case let .clearAction(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearLog()
            })
        }
    }
}

private let logTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()

func modLogController(context: AccountContext) -> ViewController {
    let manager = ModManager.shared

    let linesPromise = ValuePromise<[ModLogLine]>([], ignoreRepeated: true)
    let reload: () -> Void = {
        // Newest first: a mod that logs steadily should not push its own errors
        // off the bottom of the screen.
        linesPromise.set(manager.logEntries().reversed().map({ entry -> ModLogLine in
            let prefix = entry.isError ? "error" : "log"
            return ModLogLine(
                title: entry.modName + " - " + prefix + " - " + logTimeFormatter.string(from: entry.date),
                text: entry.message,
                isError: entry.isError
            )
        }))
    }
    reload()

    let arguments = ModLogArguments(clearLog: {
        manager.clearLog()
        reload()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        linesPromise.get()
    )
    |> map { presentationData, lines -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ModLogEntryItem] = []
        if lines.isEmpty {
            entries.append(.empty("Nothing logged yet."))
        } else {
            var index: Int32 = 0
            for line in lines {
                entries.append(.line(index, line))
                index += 1
            }
            entries.append(.clearAction("Clear Log"))
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Mod Log"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    // The manager owns this callback, so it has to let go once the screen is
    // gone - otherwise every visit would leave another live closure behind.
    manager.logDidUpdate = { [weak controller] in
        guard controller != nil else {
            ModManager.shared.logDidUpdate = nil
            return
        }
        reload()
    }
    return controller
}

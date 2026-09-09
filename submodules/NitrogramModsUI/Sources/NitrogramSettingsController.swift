import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import NitrogramSettings

private final class NitrogramSettingsArguments {
    let setFlag: (NitrogramSettings.Key, Bool) -> Void
    let openMods: () -> Void
    let openCleanup: () -> Void

    init(setFlag: @escaping (NitrogramSettings.Key, Bool) -> Void, openMods: @escaping () -> Void, openCleanup: @escaping () -> Void) {
        self.setFlag = setFlag
        self.openMods = openMods
        self.openCleanup = openCleanup
    }
}

private enum NitrogramSettingsSection: Int32 {
    case ghost
    case deleted
    case keyboard
    case tools
    case mods
}

private struct NitrogramFlagsState: Equatable {
    var ghostReadReceipts: Bool
    var ghostOnlineStatus: Bool
    var keepDeletedMessages: Bool
    var customKeyboard: Bool
}

private enum NitrogramSettingsEntry: ItemListNodeEntry {
    case ghostHeader(String)
    case ghostReadReceipts(String, Bool)
    case ghostOnlineStatus(String, Bool)
    case ghostInfo(String)
    case deletedHeader(String)
    case keepDeletedMessages(String, Bool)
    case deletedInfo(String)
    case keyboardHeader(String)
    case customKeyboard(String, Bool)
    case keyboardInfo(String)
    case cleanupAction(String)
    case cleanupInfo(String)
    case modsAction(String)
    case modsInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .ghostReadReceipts, .ghostOnlineStatus, .ghostInfo:
            return NitrogramSettingsSection.ghost.rawValue
        case .deletedHeader, .keepDeletedMessages, .deletedInfo:
            return NitrogramSettingsSection.deleted.rawValue
        case .keyboardHeader, .customKeyboard, .keyboardInfo:
            return NitrogramSettingsSection.keyboard.rawValue
        case .cleanupAction, .cleanupInfo:
            return NitrogramSettingsSection.tools.rawValue
        case .modsAction, .modsInfo:
            return NitrogramSettingsSection.mods.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostHeader:
            return 0
        case .ghostReadReceipts:
            return 1
        case .ghostOnlineStatus:
            return 2
        case .ghostInfo:
            return 3
        case .deletedHeader:
            return 10
        case .keepDeletedMessages:
            return 11
        case .deletedInfo:
            return 12
        case .keyboardHeader:
            return 20
        case .customKeyboard:
            return 21
        case .keyboardInfo:
            return 22
        case .cleanupAction:
            return 30
        case .cleanupInfo:
            return 31
        case .modsAction:
            return 100
        case .modsInfo:
            return 101
        }
    }

    static func <(lhs: NitrogramSettingsEntry, rhs: NitrogramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NitrogramSettingsArguments
        switch self {
        case let .ghostHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .ghostReadReceipts(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setFlag(.ghostReadReceipts, value)
            })
        case let .ghostOnlineStatus(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setFlag(.ghostOnlineStatus, value)
            })
        case let .ghostInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .deletedHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .keepDeletedMessages(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setFlag(.keepDeletedMessages, value)
            })
        case let .deletedInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .keyboardHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .customKeyboard(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setFlag(.customKeyboard, value)
            })
        case let .keyboardInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .cleanupAction(title):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCleanup()
            })
        case let .cleanupInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .modsAction(title):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openMods()
            })
        case let .modsInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func nitrogramSettingsEntries(state: NitrogramFlagsState) -> [NitrogramSettingsEntry] {
    var entries: [NitrogramSettingsEntry] = []

    entries.append(.ghostHeader("GHOST MODE"))
    entries.append(.ghostReadReceipts("Don't Send Read Receipts", state.ghostReadReceipts))
    entries.append(.ghostOnlineStatus("Hide Online Status", state.ghostOnlineStatus))
    entries.append(.ghostInfo("Read receipts stay on this device, so senders keep seeing one check mark. Hiding your online status also stops \"last seen\" from updating.\n\nBoth apply to this app only - replying from a notification, or from another device, still reports normally. Telegram may still show you as read if you react or reply."))

    entries.append(.deletedHeader("DELETED MESSAGES"))
    entries.append(.keepDeletedMessages("Keep Deleted Messages", state.keepDeletedMessages))
    entries.append(.deletedInfo("When someone deletes a message in a one-to-one chat, keep it and mark it with a trash icon next to its timestamp.\n\nOnly messages received after turning this on can be kept, and only theirs - your own deletions still go through. A kept message may still disappear if the chat history is reloaded from the server."))

    entries.append(.keyboardHeader("KEYBOARD"))
    entries.append(.customKeyboard("Use Nitrogram Keyboard", state.customKeyboard))
    entries.append(.keyboardInfo("Replaces the system keyboard while typing in Nitrogram, with English and Russian layouts. The globe key switches layout; the keyboard key hands control back to iOS."))

    entries.append(.cleanupAction("Clean Up Chats"))
    entries.append(.cleanupInfo("Delete many chats, bots and channels at once, picking exactly which ones."))

    entries.append(.modsAction("Mods"))
    entries.append(.modsInfo("Import and manage .ngmod files."))

    return entries
}

public func nitrogramSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let readState: () -> NitrogramFlagsState = {
        return NitrogramFlagsState(
            ghostReadReceipts: NitrogramSettings.isEnabled(.ghostReadReceipts),
            ghostOnlineStatus: NitrogramSettings.isEnabled(.ghostOnlineStatus),
            keepDeletedMessages: NitrogramSettings.isEnabled(.keepDeletedMessages),
            customKeyboard: NitrogramSettings.isEnabled(.customKeyboard)
        )
    }

    let statePromise = ValuePromise<NitrogramFlagsState>(readState(), ignoreRepeated: true)

    let arguments = NitrogramSettingsArguments(
        setFlag: { key, value in
            NitrogramSettings.setEnabled(value, for: key)
            statePromise.set(readState())
        },
        openMods: {
            pushControllerImpl?(nitrogramModsController(context: context))
        },
        openCleanup: {
            pushControllerImpl?(nitrogramCleanupController(context: context))
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Nitrogram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: nitrogramSettingsEntries(state: state), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}

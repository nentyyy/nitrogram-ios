import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private enum CleanupCategory: Int32, CaseIterable {
    case bots
    case channels
    case groups
    case privateChats

    var title: String {
        switch self {
        case .bots:
            return "BOTS"
        case .channels:
            return "CHANNELS"
        case .groups:
            return "GROUPS"
        case .privateChats:
            return "PRIVATE CHATS"
        }
    }
}

private struct CleanupChat: Equatable {
    let peerId: EnginePeer.Id
    let title: String
    let category: CleanupCategory
}

private final class NitrogramCleanupArguments {
    let toggleChat: (EnginePeer.Id) -> Void
    let toggleCategory: (CleanupCategory) -> Void
    let deleteSelected: () -> Void

    init(toggleChat: @escaping (EnginePeer.Id) -> Void, toggleCategory: @escaping (CleanupCategory) -> Void, deleteSelected: @escaping () -> Void) {
        self.toggleChat = toggleChat
        self.toggleCategory = toggleCategory
        self.deleteSelected = deleteSelected
    }
}

private enum NitrogramCleanupEntry: ItemListNodeEntry {
    case intro(String)
    case categoryHeader(Int32, CleanupCategory, String, Bool)
    case chat(Int32, CleanupChat, Bool)
    case deleteAction(Int32, String, Bool)
    case deleteInfo(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case .intro:
            return 0
        case let .categoryHeader(_, category, _, _):
            return ItemListSectionId(category.rawValue + 1)
        case let .chat(_, chat, _):
            return ItemListSectionId(chat.category.rawValue + 1)
        case .deleteAction, .deleteInfo:
            return 100
        }
    }

    var stableId: Int32 {
        switch self {
        case .intro:
            return 0
        case let .categoryHeader(index, _, _, _):
            return index
        case let .chat(index, _, _):
            return index
        case let .deleteAction(index, _, _):
            return index
        case let .deleteInfo(index, _):
            return index
        }
    }

    static func <(lhs: NitrogramCleanupEntry, rhs: NitrogramCleanupEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NitrogramCleanupArguments
        switch self {
        case let .intro(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .categoryHeader(_, category, text, allSelected):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, actionText: allSelected ? "Deselect All" : "Select All", action: {
                arguments.toggleCategory(category)
            }, sectionId: self.section)
        case let .chat(_, chat, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, title: chat.title, style: .left, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleChat(chat.peerId)
            })
        case let .deleteAction(_, title, isEnabled):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: isEnabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if isEnabled {
                    arguments.deleteSelected()
                }
            })
        case let .deleteInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func cleanupEntries(chats: [CleanupChat], selected: Set<EnginePeer.Id>) -> [NitrogramCleanupEntry] {
    var entries: [NitrogramCleanupEntry] = []
    var index: Int32 = 0

    entries.append(.intro("Pick the chats to leave behind. Deleting a channel or group also leaves it."))
    index += 1

    for category in CleanupCategory.allCases {
        let categoryChats = chats.filter({ $0.category == category })
        if categoryChats.isEmpty {
            continue
        }
        let allSelected = categoryChats.allSatisfy({ selected.contains($0.peerId) })
        entries.append(.categoryHeader(index, category, "\(category.title) (\(categoryChats.count))", allSelected))
        index += 1

        for chat in categoryChats {
            entries.append(.chat(index, chat, selected.contains(chat.peerId)))
            index += 1
        }
    }

    let title = selected.isEmpty ? "Delete Selected" : "Delete Selected (\(selected.count))"
    entries.append(.deleteAction(index, title, !selected.isEmpty))
    index += 1
    entries.append(.deleteInfo(index, "This cannot be undone. Saved Messages and your own account are never listed."))

    return entries
}

private func cleanupCategory(for peer: EnginePeer) -> CleanupCategory? {
    switch peer {
    case let .user(user):
        return user.botInfo != nil ? .bots : .privateChats
    case .legacyGroup:
        return .groups
    case let .channel(channel):
        switch channel.info {
        case .broadcast:
            return .channels
        case .group:
            return .groups
        }
    case .secretChat:
        return .privateChats
    case .community:
        // Communities do not map onto any of the four buckets, so they are left
        // out of cleanup rather than misfiled into one.
        return nil
    }
}

public func nitrogramCleanupController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?

    let selectedPromise = ValuePromise<Set<EnginePeer.Id>>(Set(), ignoreRepeated: true)
    let selectedValue = Atomic<Set<EnginePeer.Id>>(value: Set())
    let updateSelected: ((inout Set<EnginePeer.Id>) -> Void) -> Void = { f in
        selectedPromise.set(selectedValue.modify({ current in
            var updated = current
            f(&updated)
            return updated
        }))
    }

    let accountPeerId = context.account.peerId
    let chatsSignal = context.engine.messages.chatList(group: .root, count: 500)
    |> map { chatList -> [CleanupChat] in
        var result: [CleanupChat] = []
        for item in chatList.items {
            guard case let .chatList(peerId) = item.id else {
                continue
            }
            // Never offer to delete Saved Messages or the account itself.
            if peerId == accountPeerId {
                continue
            }
            guard let peer = item.renderedPeer.chatMainPeer else {
                continue
            }
            guard let category = cleanupCategory(for: peer) else {
                continue
            }
            let title = peer.compactDisplayTitle
            result.append(CleanupChat(peerId: peerId, title: title.isEmpty ? "Chat" : title, category: category))
        }
        return result
    }

    let chatsPromise = Promise<[CleanupChat]>()
    chatsPromise.set(chatsSignal)

    let arguments = NitrogramCleanupArguments(
        toggleChat: { peerId in
            updateSelected { selected in
                if selected.contains(peerId) {
                    selected.remove(peerId)
                } else {
                    selected.insert(peerId)
                }
            }
        },
        toggleCategory: { category in
            let _ = (chatsPromise.get()
            |> take(1)
            |> deliverOnMainQueue).start(next: { chats in
                let categoryIds = chats.filter({ $0.category == category }).map({ $0.peerId })
                updateSelected { selected in
                    let allSelected = categoryIds.allSatisfy({ selected.contains($0) })
                    for id in categoryIds {
                        if allSelected {
                            selected.remove(id)
                        } else {
                            selected.insert(id)
                        }
                    }
                }
            })
        },
        deleteSelected: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let selected = selectedValue.with { $0 }
            if selected.isEmpty {
                return
            }
            presentControllerImpl?(textAlertController(context: context, title: nil, text: "Delete \(selected.count) chats? This cannot be undone.", actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                    for peerId in selected {
                        let _ = context.engine.peers.removePeerChat(peerId: peerId, reportChatSpam: false).start()
                    }
                    updateSelected { selected in
                        selected.removeAll()
                    }
                })
            ]))
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        chatsPromise.get(),
        selectedPromise.get()
    )
    |> map { presentationData, chats, selected -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Clean Up Chats"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: cleanupEntries(chats: chats, selected: selected), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

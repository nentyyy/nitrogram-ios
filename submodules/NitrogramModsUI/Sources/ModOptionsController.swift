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

private final class ModOptionsArguments {
    let selectOption: (Int) -> Void

    init(selectOption: @escaping (Int) -> Void) {
        self.selectOption = selectOption
    }
}

private enum ModOptionsEntry: ItemListNodeEntry {
    case option(Int32, String, Bool)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .option(index, _, _):
            return index
        }
    }

    static func <(lhs: ModOptionsEntry, rhs: ModOptionsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ModOptionsArguments
        switch self {
        case let .option(index, title, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .left, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectOption(Int(index))
            })
        }
    }
}

/// A one-section list of choices, used for both `segmented` settings and the
/// stepped values of a `slider` setting.
func modOptionsController(context: AccountContext, title: String, options: [(String, ModSettingValue)], selected: ModSettingValue, apply: @escaping (ModSettingValue) -> Void) -> ViewController {
    var dismissImpl: (() -> Void)?

    let selectedPromise = ValuePromise<ModSettingValue>(selected, ignoreRepeated: true)

    let arguments = ModOptionsArguments(selectOption: { index in
        guard index >= 0 && index < options.count else {
            return
        }
        let value = options[index].1
        selectedPromise.set(value)
        apply(value)
        dismissImpl?()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        selectedPromise.get()
    )
    |> map { presentationData, selectedValue -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ModOptionsEntry] = []
        var index: Int32 = 0
        for option in options {
            entries.append(.option(index, option.0, option.1 == selectedValue))
            index += 1
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}

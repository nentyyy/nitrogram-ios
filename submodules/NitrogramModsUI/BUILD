load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "NitrogramModsUI",
    module_name = "NitrogramModsUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/AccountContext:AccountContext",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/TextFormat:TextFormat",
        "//submodules/NitrogramMods:NitrogramMods",
    ],
    visibility = [
        "//visibility:public",
    ],
)

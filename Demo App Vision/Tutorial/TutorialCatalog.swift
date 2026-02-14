import Foundation

enum TutorialVideoSource: Hashable {
    case bundled(name: String, fileExtension: String)
    case remote(urlString: String)
}

struct TutorialVideoModule: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let durationLabel: String
    let source: TutorialVideoSource
}

enum TutorialCatalog {
    static let modules: [TutorialVideoModule] = [
        .init(
            id: "navigation-basics",
            title: "Navigation Basics",
            summary: "Move between Home, Details, and Settings efficiently.",
            durationLabel: "1:30",
            source: .bundled(name: "tutorial_navigation_basics", fileExtension: "mp4")
        ),
        .init(
            id: "import-models",
            title: "Importing Models",
            summary: "Bring USDZ files into your workspace safely.",
            durationLabel: "2:10",
            source: .bundled(name: "tutorial_import_models", fileExtension: "mp4")
        ),
        .init(
            id: "editing-models",
            title: "Editing Models",
            summary: "Scale, move, and fine-tune model settings.",
            durationLabel: "2:00",
            source: .bundled(name: "tutorial_editing_models", fileExtension: "mp4")
        ),
        .init(
            id: "projects-save-load",
            title: "Saving and Loading Projects",
            summary: "Persist room layouts and restore them reliably.",
            durationLabel: "1:45",
            source: .bundled(name: "tutorial_projects_save_load", fileExtension: "mp4")
        ),
        .init(
            id: "focus-mode",
            title: "Focus Mode",
            summary: "Use focus controls to reduce real-world distractions.",
            durationLabel: "1:20",
            source: .bundled(name: "tutorial_focus_mode", fileExtension: "mp4")
        ),
    ]
}


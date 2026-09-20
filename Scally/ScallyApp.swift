import SwiftUI
import SwiftData

@main
struct ScallyApp: App {
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            ImportView()
                .preferredColorScheme(colorScheme)
                .tint(Palette.accent)
        }
        .modelContainer(for: UpscaleRecord.self)
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

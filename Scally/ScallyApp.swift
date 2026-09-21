import SwiftUI
import SwiftData

@main
struct ScallyApp: App {
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            RootView()
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

/// Whether the app can draw a truthful first frame yet.
///
/// A reference type on purpose: `LaunchView` reads this from inside a running
/// task, and a `let` copied into that task at creation would never see the
/// change.
@MainActor @Observable
final class AppReadiness {
    private(set) var isReady = false

    func warm() async {
        // Import's trust panel totals the library from disk, in its own body.
        // That is a directory walk that grows with the history, so it is done
        // here - behind the mark - rather than as a stutter in the first frame.
        let store = LibraryStore()
        _ = await Task.detached(priority: .userInitiated) { store.totalBytes() }.value
        isReady = true
    }
}

/// The launch mark, then the app. Import is not in the hierarchy at all until
/// the mark has left the screen, which is what the design means by "the splash
/// clears before the app is shown".
struct RootView: View {
    @State private var readiness = AppReadiness()
    @State private var launched = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if launched {
                ImportView().transition(.opacity)
            } else {
                LaunchView(readiness: readiness) {
                    withAnimation(.easeOut(duration: 0.2)) { launched = true }
                }
            }
        }
        .task { await readiness.warm() }
    }
}

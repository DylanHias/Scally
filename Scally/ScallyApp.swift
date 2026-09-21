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

/// The launch mark, then the app.
///
/// The design brings Import in *under* the clearing splash rather than after
/// it: `sc-app` runs from 1.90 s to 2.24 s while `sc-splash` fades over the
/// same stretch. The mark itself is already gone by 1.70 s, so Import still
/// never appears behind it.
struct RootView: View {
    @State private var readiness = AppReadiness()
    @State private var launched = false
    @State private var appOpacity: Double = 0
    @State private var appOffset: CGFloat = 6

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            ImportView()
                .opacity(appOpacity)
                .offset(y: appOffset)

            if !launched {
                LaunchView(readiness: readiness) {
                    // cubic-bezier(.2,.7,.2,1) over 0.34 s, the source's sc-app.
                    withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.34)) {
                        appOpacity = 1
                        appOffset = 0
                    }
                } onFinish: {
                    launched = true
                }
            }
        }
        .task { await readiness.warm() }
    }
}

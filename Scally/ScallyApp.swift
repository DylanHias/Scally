import SwiftUI
import SwiftData

@main
struct ScallyApp: App {
    var body: some Scene {
        WindowGroup {
            PlaceholderView()
        }
        .modelContainer(for: UpscaleRecord.self)
    }
}

/// Replaced by `ImportView` in Task 16. Exists so the app target builds and
/// runs while ScallyKit is still being assembled.
struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 40, weight: .light))
            Text("Scally")
                .font(.title2.weight(.semibold))
            Text("Scaffold only. No pipeline yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

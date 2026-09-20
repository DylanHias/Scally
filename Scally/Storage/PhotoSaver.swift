import Foundation
import Photos

enum PhotoSaver {
    enum SaveError: LocalizedError {
        case notAuthorised
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorised: "Scally needs permission to add photos to your library."
            case .failed(let reason): reason
            }
        }
    }

    /// Add-only authorisation: the app never needs to read the library.
    static func save(fileURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.notAuthorised }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: fileURL, options: nil)
            }
        } catch {
            throw SaveError.failed(error.localizedDescription)
        }
    }
}

import Foundation

enum VaultBoxError: LocalizedError {
    case photoImportFailed
    case decryptionFailed
    case iCloudUnavailable
    case iCloudFull
    case cameraPermissionDenied
    case photosPermissionDenied
    case purchaseFailed
    case networkError

    var errorDescription: String? {
        switch self {
        case .photoImportFailed:
            return String(localized: "Couldn't import this photo. Please try again.")
        case .decryptionFailed:
            return String(localized: "This item couldn't be opened. It may be corrupted.")
        case .iCloudUnavailable:
            return String(localized: "iCloud is not available. Check your Apple ID in Settings.")
        case .iCloudFull:
            return String(localized: "Your iCloud storage is full. Backup paused.")
        case .cameraPermissionDenied:
            return String(localized: "VaultBox needs camera access for this feature.")
        case .photosPermissionDenied:
            return String(localized: "VaultBox needs photo access to import your photos.")
        case .purchaseFailed:
            return String(localized: "Purchase couldn't be completed. Please try again.")
        case .networkError:
            return String(localized: "Backup paused — no internet connection.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .iCloudUnavailable, .cameraPermissionDenied, .photosPermissionDenied:
            return String(localized: "Open Settings to update permissions.")
        case .iCloudFull:
            return String(localized: "Manage your iCloud storage in Settings.")
        case .networkError:
            return String(localized: "Will retry automatically when connected.")
        default:
            return nil
        }
    }
}

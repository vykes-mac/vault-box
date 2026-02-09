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
            return "Couldn't import this photo. Please try again."
        case .decryptionFailed:
            return "This item couldn't be opened. It may be corrupted."
        case .iCloudUnavailable:
            return "iCloud is not available. Check your Apple ID in Settings."
        case .iCloudFull:
            return "Your iCloud storage is full. Backup paused."
        case .cameraPermissionDenied:
            return "VaultBox needs camera access for this feature."
        case .photosPermissionDenied:
            return "VaultBox needs photo access to import your photos."
        case .purchaseFailed:
            return "Purchase couldn't be completed. Please try again."
        case .networkError:
            return "Backup paused — no internet connection."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .iCloudUnavailable, .cameraPermissionDenied, .photosPermissionDenied:
            return "Open Settings to update permissions."
        case .iCloudFull:
            return "Manage your iCloud storage in Settings."
        case .networkError:
            return "Will retry automatically when connected."
        default:
            return nil
        }
    }
}

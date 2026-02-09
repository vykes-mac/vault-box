import SwiftUI
import SwiftData

@MainActor
@Observable
class AuthViewModel {
    let authService: AuthService

    var isUnlocked: Bool { authService.isUnlocked }
    var isDecoyMode: Bool { authService.isDecoyMode }

    init(authService: AuthService) {
        self.authService = authService
    }

    func verifyPIN(_ pin: String) async -> AuthResult {
        await authService.verifyPIN(pin)
    }

    func authenticateWithBiometrics() async -> Bool {
        await authService.authenticateWithBiometrics()
    }

    func lock() {
        authService.lock()
    }

    func isSetupComplete(modelContext: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? modelContext.fetch(descriptor).first else { return false }
        return settings.isSetupComplete
    }
}

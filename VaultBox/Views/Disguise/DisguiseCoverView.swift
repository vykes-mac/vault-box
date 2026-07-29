import SwiftUI
import UIKit

struct LockedAppOverlay: View {
    let authService: AuthService
    let onPresented: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var isAuthenticationVisible = false

    private var activeDisguise: AppDisguise? {
        AppDisguise(iconName: UIApplication.shared.alternateIconName)
    }

    var body: some View {
        Group {
            if let activeDisguise, !isAuthenticationVisible {
                DisguiseCoverView(disguise: activeDisguise) {
                    Haptics.itemSelected()
                    isAuthenticationVisible = true
                }
            } else {
                LockScreenView(authService: authService, onPresented: onPresented)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: onPresented)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                isAuthenticationVisible = false
            }
        }
    }
}

struct AppPrivacyShieldView: View {
    private var activeDisguise: AppDisguise? {
        AppDisguise(iconName: UIApplication.shared.alternateIconName)
    }

    var body: some View {
        Group {
            if let activeDisguise {
                ZStack {
                    activeDisguise.backgroundColor
                    VStack(spacing: 16) {
                        Image(systemName: activeDisguise.systemImage)
                            .font(.system(size: 46, weight: .medium))
                            .foregroundStyle(activeDisguise.accentColor)
                        Text(activeDisguise.coverTitle)
                            .font(.headline)
                            .foregroundStyle(activeDisguise.primaryTextColor)
                    }
                }
            } else {
                Color.black
                    .overlay {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .ignoresSafeArea()
    }
}

struct DisguiseCoverView: View {
    let disguise: AppDisguise
    let revealAuthentication: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 8)
        .background(disguise.backgroundColor.ignoresSafeArea())
        .preferredColorScheme(disguise.preferredColorScheme)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: disguise.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(disguise.accentColor)
                .frame(width: 36, height: 36)
                .background(disguise.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

            Text(disguise.coverTitle)
                .font(.headline)
                .foregroundStyle(disguise.primaryTextColor)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.8, perform: revealAuthentication)
                .accessibilityAction(
                    named: String(localized: "Show details"),
                    revealAuthentication
                )

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch disguise {
        case .calculator:
            CalculatorDisguiseView()
        case .notes:
            NotesDisguiseView()
        case .weather:
            WeatherDisguiseView()
        case .compass:
            CompassDisguiseView()
        case .clock:
            ClockDisguiseView()
        case .stocks:
            StocksDisguiseView()
        case .translate:
            TranslateDisguiseView()
        case .measure:
            MeasureDisguiseView()
        }
    }
}

extension AppDisguise {
    var preferredColorScheme: ColorScheme {
        switch self {
        case .calculator, .clock, .stocks: .dark
        default: .light
        }
    }

    var backgroundColor: Color {
        switch self {
        case .calculator, .clock: Color(red: 0.06, green: 0.07, blue: 0.09)
        case .notes: Color(red: 0.98, green: 0.97, blue: 0.91)
        case .weather: Color(red: 0.84, green: 0.93, blue: 0.99)
        case .compass: Color(red: 0.95, green: 0.94, blue: 0.91)
        case .stocks: Color(red: 0.04, green: 0.07, blue: 0.06)
        case .translate: Color(red: 0.92, green: 0.96, blue: 1.0)
        case .measure: Color(red: 0.97, green: 0.95, blue: 0.86)
        }
    }

    var accentColor: Color {
        switch self {
        case .calculator: .orange
        case .notes, .measure: Color(red: 0.82, green: 0.59, blue: 0.05)
        case .weather, .translate: Color(red: 0.08, green: 0.42, blue: 0.82)
        case .compass: Color(red: 0.72, green: 0.15, blue: 0.12)
        case .clock: Color(red: 0.98, green: 0.45, blue: 0.18)
        case .stocks: Color(red: 0.16, green: 0.78, blue: 0.42)
        }
    }

    var primaryTextColor: Color {
        preferredColorScheme == .dark ? .white : Color(red: 0.10, green: 0.11, blue: 0.13)
    }

    var secondaryTextColor: Color {
        primaryTextColor.opacity(0.62)
    }
}

import Testing
@testable import VaultBox

@Suite("App Disguise Tests")
struct AppDisguiseTests {
    @Test("Every configured alternate icon maps to a disguise")
    @MainActor
    func configuredIconsMapToDisguises() {
        let configuredIDs = Set(AppIconService.iconCatalog.compactMap(\.id))
        let disguiseIDs = Set(AppDisguise.allCases.map(\.rawValue))

        #expect(configuredIDs == disguiseIDs)
        #expect(AppDisguise(iconName: nil) == nil)
        #expect(AppDisguise(iconName: "UnknownIcon") == nil)
    }

    @Test("The resulting icon state resolves system icon-change errors")
    @MainActor
    func resultingIconStateResolvesChange() {
        #expect(AppIconService.didApplyIcon(
            requestedIconName: "CalculatorIcon",
            actualIconName: "CalculatorIcon"
        ))
        #expect(AppIconService.didApplyIcon(
            requestedIconName: nil,
            actualIconName: nil
        ))
        #expect(!AppIconService.didApplyIcon(
            requestedIconName: "CalculatorIcon",
            actualIconName: "NotesIcon"
        ))
        #expect(!AppIconService.didApplyIcon(
            requestedIconName: nil,
            actualIconName: "CalculatorIcon"
        ))
    }

    @Test("Active disguises lock immediately in the background")
    func activeDisguisesLockImmediately() {
        #expect(shouldLockImmediatelyForDisguise(iconName: "CalculatorIcon"))
        #expect(shouldLockImmediatelyForDisguise(iconName: "StockIcon"))
        #expect(!shouldLockImmediatelyForDisguise(iconName: nil))
        #expect(!shouldLockImmediatelyForDisguise(iconName: "UnknownIcon"))
    }

    @Test("Unlock rehearsal appears only until the gesture is learned")
    func unlockGuidePresentation() {
        #expect(shouldPresentDisguiseUnlockGuide(
            iconName: "CalculatorIcon",
            hasLearnedGesture: false
        ))
        #expect(!shouldPresentDisguiseUnlockGuide(
            iconName: "CompassIcon",
            hasLearnedGesture: true
        ))
        #expect(!shouldPresentDisguiseUnlockGuide(
            iconName: nil,
            hasLearnedGesture: false
        ))
        #expect(!shouldPresentDisguiseUnlockGuide(
            iconName: "UnknownIcon",
            hasLearnedGesture: false
        ))
    }

    @Test("Icon changes suppress only their inactive transition")
    @MainActor
    func iconChangePrivacyShieldSuppression() {
        let shield = AppPrivacyShield()

        #expect(!shield.shouldSuppressForIconChange())

        shield.beginIconChange()
        #expect(shield.shouldSuppressForIconChange())
        #expect(shield.shouldSuppressForIconChange())

        shield.completeIconChangeRequest()
        #expect(shield.finishIconChangeOnActive())
        #expect(!shield.shouldSuppressForIconChange())
    }

    @Test("Icon suppression clears when no inactive transition occurs")
    @MainActor
    func iconChangeWithoutInactiveTransition() {
        let shield = AppPrivacyShield()

        shield.beginIconChange()
        shield.completeIconChangeRequest()

        #expect(!shield.shouldSuppressForIconChange())
        #expect(!shield.finishIconChangeOnActive())
    }

    @Test("Level readings print rounded motion values")
    func levelReadingFormatting() {
        let reading = LevelReading(roll: 12.6, pitch: -4.4)

        #expect(reading.displayText == "13°  -4°")
        #expect(reading.accessibilityValue == "Roll 13 degrees, pitch -4 degrees")
    }

    @Test("Compass readings print rounded normalized headings")
    func compassReadingFormatting() {
        let southwest = CompassReading(heading: 224.6)
        let north = CompassReading(heading: 359.6)

        #expect(southwest.displayText == "225°")
        #expect(southwest.accessibilityValue == "225 degrees magnetic")
        #expect(north.displayText == "0°")
        #expect(north.accessibilityValue == "0 degrees magnetic")
    }

    @Test("Calculator performs chained arithmetic")
    func calculatorArithmetic() {
        var calculator = CalculatorEngine()
        calculator.inputDigit("1")
        calculator.inputDigit("2")
        calculator.select(.add)
        calculator.inputDigit("3")
        calculator.equals()

        #expect(calculator.display == "15")
    }

    @Test("Calculator handles division by zero")
    func calculatorDivisionByZero() {
        var calculator = CalculatorEngine()
        calculator.inputDigit("8")
        calculator.select(.divide)
        calculator.inputDigit("0")
        calculator.equals()

        #expect(calculator.display == String(localized: "Error"))
    }

    @Test("Calculator supports decimal percentages")
    func calculatorPercent() {
        var calculator = CalculatorEngine()
        calculator.inputDigit("2")
        calculator.inputDigit("5")
        calculator.percent()

        #expect(calculator.display == "0.25")
    }

    // MARK: - Lapse Notice

    @Test("A lapsed subscriber still wearing a disguise is told what stopped")
    func lapseNoticeShownWhileDisguised() {
        #expect(
            shouldPresentDisguiseLapseNotice(
                isMainRoute: true,
                isPremium: false,
                hasResolvedCustomerInfo: true,
                iconName: AppDisguise.calculator.rawValue,
                hasShownNotice: false
            )
        )
    }

    @Test("Paying subscribers are never shown the lapse notice")
    func lapseNoticeHiddenWhilePremium() {
        #expect(
            !shouldPresentDisguiseLapseNotice(
                isMainRoute: true,
                isPremium: true,
                hasResolvedCustomerInfo: true,
                iconName: AppDisguise.calculator.rawValue,
                hasShownNotice: false
            )
        )
    }

    /// A cold launch reads `isPremium == false` before RevenueCat answers. Announcing a
    /// lapse there would accuse paying users of churning every time they open the app.
    @Test("Nothing is announced before the store has answered")
    func lapseNoticeWaitsForCustomerInfo() {
        #expect(
            !shouldPresentDisguiseLapseNotice(
                isMainRoute: true,
                isPremium: false,
                hasResolvedCustomerInfo: false,
                iconName: AppDisguise.calculator.rawValue,
                hasShownNotice: false
            )
        )
    }

    @Test("Users on the default icon have nothing to be told")
    func lapseNoticeSkippedWithoutDisguise() {
        #expect(
            !shouldPresentDisguiseLapseNotice(
                isMainRoute: true,
                isPremium: false,
                hasResolvedCustomerInfo: true,
                iconName: nil,
                hasShownNotice: false
            )
        )
    }

    @Test("The notice is not repeated within one lapse")
    func lapseNoticeShownOnce() {
        #expect(
            !shouldPresentDisguiseLapseNotice(
                isMainRoute: true,
                isPremium: false,
                hasResolvedCustomerInfo: true,
                iconName: AppDisguise.calculator.rawValue,
                hasShownNotice: true
            )
        )
    }

    /// Behind the lock screen the alert would be dismissed unseen, and during onboarding
    /// there is no subscription to have lapsed.
    @Test("The notice waits for the main screen")
    func lapseNoticeWaitsForMainRoute() {
        #expect(
            !shouldPresentDisguiseLapseNotice(
                isMainRoute: false,
                isPremium: false,
                hasResolvedCustomerInfo: true,
                iconName: AppDisguise.calculator.rawValue,
                hasShownNotice: false
            )
        )
    }
}

import Testing

@testable import VaultBox

@Suite("Activation checklist")
struct ActivationChecklistTests {

    // MARK: - Completion

    @Test("A brand-new vault starts with its completed security step credited")
    func creditsWorkAlreadyDone() {
        let checklist = ActivationChecklist(isDisguised: false, hasItems: false)

        #expect(checklist.isComplete(.secured))
        #expect(checklist.completedCount == 1)
        #expect(checklist.totalCount == 4)
        #expect(!checklist.isFullyComplete)
    }

    @Test("Completion follows the live icon and item state")
    func derivesCompletionFromRealSignals() {
        let disguisedOnly = ActivationChecklist(isDisguised: true, hasItems: false)
        #expect(disguisedOnly.isComplete(.disguise))
        #expect(!disguisedOnly.isComplete(.firstImport))
        #expect(disguisedOnly.completedCount == 2)

        let importedOnly = ActivationChecklist(isDisguised: false, hasItems: true)
        #expect(!importedOnly.isComplete(.disguise))
        #expect(importedOnly.isComplete(.firstImport))
        #expect(importedOnly.completedCount == 2)

        let sharedOnly = ActivationChecklist(isDisguised: false, hasItems: false, hasShared: true)
        #expect(sharedOnly.isComplete(.secureShare))
        #expect(sharedOnly.completedCount == 2)
    }

    @Test("Everything done reports fully complete")
    func fullyComplete() {
        let checklist = ActivationChecklist(isDisguised: true, hasItems: true, hasShared: true)

        #expect(checklist.completedCount == 4)
        #expect(checklist.isFullyComplete)
        #expect(checklist.nextStep == nil)
    }

    /// A user whose subscription lapses has their icon reverted by `ContentView`. The
    /// checklist must follow that back to incomplete rather than keeping a stale tick.
    @Test("Losing the disguise reopens the step")
    func revertedIconReopensStep() {
        var checklist = ActivationChecklist(isDisguised: true, hasItems: false)
        #expect(checklist.isComplete(.disguise))

        checklist.isDisguised = false

        #expect(!checklist.isComplete(.disguise))
        #expect(checklist.nextStep == .disguise)
    }

    // MARK: - Next step

    @Test("Disguise leads for a fresh install")
    func disguiseIsFirstUnfinishedStep() {
        let checklist = ActivationChecklist(isDisguised: false, hasItems: false)
        #expect(checklist.nextStep == .disguise)
    }

    @Test("Import takes over once a disguise is set")
    func importFollowsDisguise() {
        let checklist = ActivationChecklist(isDisguised: true, hasItems: false)
        #expect(checklist.nextStep == .firstImport)
    }

    @Test("Secure sharing follows the first import")
    func sharingFollowsImport() {
        let checklist = ActivationChecklist(isDisguised: true, hasItems: true)
        #expect(checklist.nextStep == .secureShare)
    }

    @Test("Only one step is ever highlighted")
    func exactlyOneNextStep() {
        for isDisguised in [true, false] {
            for hasItems in [true, false] {
                for hasShared in [true, false] {
                    let checklist = ActivationChecklist(
                        isDisguised: isDisguised,
                        hasItems: hasItems,
                        hasShared: hasShared
                    )
                    let highlighted = ActivationStep.allCases.filter { checklist.nextStep == $0 }
                    #expect(highlighted.count <= 1)
                }
            }
        }
    }

    // MARK: - Visibility

    @Test("Shows on an untouched, empty vault")
    func showsOnEmptyVault() {
        #expect(
            shouldShowActivationChecklist(
                isVaultEmpty: true,
                isSearching: false,
                isDecoyMode: false,
                hasDismissed: false
            )
        )
    }

    @Test("Hidden once the vault has content")
    func hiddenWhenVaultHasItems() {
        #expect(
            !shouldShowActivationChecklist(
                isVaultEmpty: false,
                isSearching: false,
                isDecoyMode: false,
                hasDismissed: false
            )
        )
    }

    @Test("Hidden while searching")
    func hiddenWhileSearching() {
        #expect(
            !shouldShowActivationChecklist(
                isVaultEmpty: true,
                isSearching: true,
                isDecoyMode: false,
                hasDismissed: false
            )
        )
    }

    /// The decoy vault exists to look like an ordinary vault to whoever is holding the
    /// phone. Offering to disguise the app there would reveal that a real one exists.
    @Test("Never shown in decoy mode")
    func neverShownInDecoyMode() {
        #expect(
            !shouldShowActivationChecklist(
                isVaultEmpty: true,
                isSearching: false,
                isDecoyMode: true,
                hasDismissed: false
            )
        )
    }

    @Test("Stays dismissed once dismissed")
    func respectsDismissal() {
        #expect(
            !shouldShowActivationChecklist(
                isVaultEmpty: true,
                isSearching: false,
                isDecoyMode: false,
                hasDismissed: true
            )
        )
    }

    @Test("Compact progress remains visible after import until setup is complete")
    func compactProgressAfterImport() {
        #expect(
            shouldShowActivationProgressCard(
                hasItems: true,
                isSearching: false,
                isSelecting: false,
                isDecoyMode: false,
                hasDismissed: false,
                isFullyComplete: false
            )
        )

        #expect(
            !shouldShowActivationProgressCard(
                hasItems: true,
                isSearching: false,
                isSelecting: false,
                isDecoyMode: false,
                hasDismissed: false,
                isFullyComplete: true
            )
        )
    }

    // MARK: - Analytics naming

    @Test("Wire names are stable and unique")
    func analyticsNamesAreStable() {
        let names = ActivationStep.allCases.map(\.analyticsName)
        #expect(names == ["secured", "disguise", "first_import", "secure_share"])
        #expect(Set(names).count == names.count)
    }
}

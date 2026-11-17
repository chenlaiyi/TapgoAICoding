import XCTest
import Foundation

let cases: [(String, () -> (XCTestCase, () throws -> Void))] = [
    ("catalog/keeps-levels", {
        let t = MobileModelCatalogTests()
        return (t, { t.testCatalogKeepsReasoningLevelsAndDescriptions() })
    }),
    ("catalog/skips-incomplete", {
        let t = MobileModelCatalogTests()
        return (t, { t.testCatalogSkipsIncompleteRoutes() })
    }),
    ("catalog/real-changes", {
        let t = MobileModelCatalogTests()
        return (t, { t.testSelectionNeedsARequestOnlyForRealChanges() })
    }),
    ("catalog/no-levels", {
        let t = MobileModelCatalogTests()
        return (t, { t.testRouteWithoutReasoningIgnoresLevels() })
    }),
    ("catalog/effort-name", {
        let t = MobileModelCatalogTests()
        return (t, { t.testEffortNameRequiresADeclaredLevel() })
    }),
    ("submission/unchanged", {
        let t = MobilePendingSubmissionTests()
        return (t, { t.testUnchangedDraftMatchesForRequestIdReuse() })
    }),
    ("submission/edited", {
        let t = MobilePendingSubmissionTests()
        return (t, { t.testEditedDraftDoesNotMatch() })
    }),
    ("submission/attachments", {
        let t = MobilePendingSubmissionTests()
        return (t, { t.testChangedAttachmentsDoNotMatch() })
    }),
    ("submission/explicit-id", {
        let t = MobilePendingSubmissionTests()
        return (t, { t.testExplicitRequestIdSurvives() })
    }),
    ("preference/round-trip", {
        let t = MobileModelPreferenceTests()
        return (t, { t.testEffortRoundTripsWithTheRoute() })
    }),
    ("preference/clears-stale", {
        let t = MobileModelPreferenceTests()
        return (t, { t.testSavingWithoutEffortClearsAStaleLevel() })
    }),
    ("preference/per-computer", {
        let t = MobileModelPreferenceTests()
        return (t, { t.testComputersKeepSeparateSelections() })
    }),
    ("thumbnail/downsample", {
        let t = MobileImageThumbnailTests()
        return (t, { t.testDownsamplesTheLongestEdgeAndKeepsTheAspectRatio() })
    }),
    ("thumbnail/small", {
        let t = MobileImageThumbnailTests()
        return (t, { t.testSmallImagesKeepTheirSize() })
    }),
    ("thumbnail/unreadable", {
        let t = MobileImageThumbnailTests()
        return (t, { t.testUnreadableBytesAreRejected() })
    }),
    ("address/https-and-lan", {
        let t = MobileConnectionAddressTests()
        return (t, { try t.testAcceptsHTTPSAnywhereAndHTTPOnTheLocalNetwork() })
    }),
    ("address/public-http", {
        let t = MobileConnectionAddressTests()
        return (t, { try t.testRejectsPublicHTTPAndMalformedPaths() })
    }),
    ("address/identity", {
        let t = MobileConnectionAddressTests()
        return (t, { try t.testIdentityKeepsTheSchemeAndPort() })
    }),
    ("address/ws-scheme", {
        let t = MobileConnectionAddressTests()
        return (t, { try t.testWebSocketSchemeFollowsTheOrigin() })
    }),
    ("failover/route-failures", {
        let t = MobileFailoverTests()
        return (t, { t.testTransportFailuresSwitchRoutes() })
    }),
    ("failover/protocol-keeps-route", {
        let t = MobileFailoverTests()
        return (t, { t.testProtocolAndAuthFailuresKeepTheRoute() })
    }),
    ("code/short", {
        let t = MobileCodePreviewTests()
        return (t, { t.testShortBlocksStayWhole() })
    }),
    ("code/collapse", {
        let t = MobileCodePreviewTests()
        return (t, { t.testLongBlocksCollapseAndExpand() })
    }),
    ("code/limit", {
        let t = MobileCodePreviewTests()
        return (t, { t.testZeroLimitDisablesCollapsing() })
    }),
    ("holdback/fence", {
        let t = MobileStreamFenceTests()
        return (t, { t.testPipesInsideAnOpenCodeFenceAreNotHeld() })
    }),
    ("holdback/closed-fence", {
        let t = MobileStreamFenceTests()
        return (t, { t.testClosedFenceThenTableStillHolds() })
    }),
    ("holdback/unfinished", {
        let t = MobileStreamTableHoldbackTests()
        return (t, { t.testHoldsBackAnUnfinishedTrailingTable() })
    }),
    ("holdback/complete", {
        let t = MobileStreamTableHoldbackTests()
        return (t, { t.testShowsACompletedTableAfterABlankLine() })
    }),
    ("holdback/newline", {
        let t = MobileStreamTableHoldbackTests()
        return (t, { t.testSingleTrailingNewlineKeepsTheTableHeld() })
    }),
    ("holdback/whole", {
        let t = MobileStreamTableHoldbackTests()
        return (t, { t.testWholeTableWaitsForItsBlock() })
    }),
    ("preview/short", {
        let t = MobileStreamPreviewTests()
        return (t, { t.testShortTextIsUnchanged() })
    }),
    ("preview/tail", {
        let t = MobileStreamPreviewTests()
        return (t, { t.testLongTextKeepsTheNewestTail() })
    }),
    ("preview/limit", {
        let t = MobileStreamPreviewTests()
        return (t, { t.testNonPositiveLimitDisablesBounding() })
    }),
    ("changes/categories", {
        let t = MobileChangesFilterTests()
        return (t, { t.testAllFilesAndDeliverablesAreSeparated() })
    }),
    ("changes/search", {
        let t = MobileChangesFilterTests()
        return (t, { t.testSearchFiltersOnPathAndDisplay() })
    }),
    ("changes/suffix", {
        let t = MobileChangesFilterTests()
        return (t, { t.testDeliverableMatchingAcceptsAbsoluteSuffixes() })
    }),
    ("voice-punctuation/pause", {
        let t = MobileVoicePunctuationTests()
        return (t, { t.testPauseBecomesCommaAndEndsWithFullStop() })
    }),
    ("voice-punctuation/keep", {
        let t = MobileVoicePunctuationTests()
        return (t, { t.testKeepsRecognizerPunctuation() })
    }),
    ("voice-punctuation/fallback", {
        let t = MobileVoicePunctuationTests()
        return (t, { t.testFallbackGetsOnlyFinalStop() })
    }),
    ("deliverables/same-file", {
        let t = MobileDeliverablesTests()
        return (t, { t.testDeduplicatesAbsoluteDeliverableAgainstRelativeLink() })
    }),
    ("deliverables/list", {
        let t = MobileDeliverablesTests()
        return (t, { t.testDeduplicatesAndNamesDeliverables() })
    }),
    ("deliverables/links", {
        let t = MobileDeliverablesTests()
        return (t, { t.testExtractsLocalMarkdownFileLinks() })
    }),
    ("deliverables/merge", {
        let t = MobileDeliverablesTests()
        return (t, { t.testMergesDeliverablesWithLinksAndSkipsNonFiles() })
    }),
    ("duration/text", {
        let t = MobileDurationTests()
        return (t, { t.testFormatsSecondsMinutesAndHours() })
    }),
    ("process/symbol", {
        let t = MobileProcessLabelTests()
        return (t, { t.testSymbolUsesTheDominantCategory() })
    }),
    ("process/counted", {
        let t = MobileProcessLabelTests()
        return (t, { t.testCountedTitleAggregatesSearchesAndCommands() })
    }),
    ("process/counted-running", {
        let t = MobileProcessLabelTests()
        return (t, { t.testCountedTitleKeepsCountsAndAppendsRunningCommand() })
    }),
    ("process/counted-fallback", {
        let t = MobileProcessLabelTests()
        return (t, { t.testCountedTitleFallsBackWhenNothingRan() })
    }),
    ("next-prompts/actionable", {
        let t = MobileNextPromptsTests()
        return (t, { t.testPicksOneActionableNonQuestionPrompt() })
    }),
    ("next-prompts/prefill", {
        let t = MobileNextPromptsTests()
        return (t, { t.testPrefillOnceAndSwitchWithoutDuplicatingRecommendations() })
    }),
    ("next-prompts/turn", {
        let t = MobileNextPromptsTests()
        return (t, { t.testRecommendationsFollowTheirTurnAndNeverReplaceDraftText() })
    }),
    ("composer/pending", {
        let t = MobileComposerStateTests()
        return (t, { t.testPlanPendingAndGoalRoundsAreProjected() })
    }),
    ("browser/labels", {
        let t = MobileFileBrowserTests()
        return (t, { t.testBuildsReadableEntryLabels() })
    }),
    ("browser/filter", {
        let t = MobileFileBrowserTests()
        return (t, { t.testFiltersByNameAndMapsHostCodes() })
    }),
    ("browser/paths", {
        let t = MobileFileBrowserTests()
        return (t, { t.testJoinsAndWalksPaths() })
    }),
    ("browser/sort", {
        let t = MobileFileBrowserTests()
        return (t, { t.testSortsDirectoriesBeforeFilesByName() })
    }),
    ("browser/decode", {
        let t = MobileFileBrowserTests()
        return (t, { try t.testDecodesTheHostListing() })
    }),
    ("code-expansion/round-trip", {
        let t = MobileCodeExpansionStoreTests()
        return (t, { t.testRoundTripsPerConversation() })
    }),
    ("code-expansion/cap", {
        let t = MobileCodeExpansionStoreTests()
        return (t, { t.testKeepsABoundedNumberOfBlocks() })
    }),
    ("code-expansion/clear", {
        let t = MobileCodeExpansionStoreTests()
        return (t, { t.testClearingRemovesTheKey() })
    }),
    ("collapse/round-trip", {
        let t = MobileProjectCollapseStoreTests()
        return (t, { t.testRoundTripsPerComputer() })
    }),
    ("collapse/clears", {
        let t = MobileProjectCollapseStoreTests()
        return (t, { t.testEmptySetClearsTheKey() })
    }),
    ("collapse/isolated", {
        let t = MobileProjectCollapseStoreTests()
        return (t, { t.testClearRemovesOnlyOneComputer() })
    }),
    ("process/categories", {
        let t = MobileProcessLabelTests()
        return (t, { t.testMapsToolNamesToCategories() })
    }),
    ("process/running-reasoning", {
        let t = MobileProcessLabelTests()
        return (t, { t.testRunningReasoningUsesTheDSHRunningLabel() })
    }),
    ("process/titles", {
        let t = MobileProcessLabelTests()
        return (t, { t.testBuildsClosedTitlesLikeDSH() })
    }),
    ("process/running", {
        let t = MobileProcessLabelTests()
        return (t, { t.testRunningTitleCarriesTheCommandDetail() })
    }),
    ("expansion/round-trip", {
        let t = MobileExpansionStoreTests()
        return (t, { t.testRoundTripsPerStep() })
    }),
    ("expansion/cap", {
        let t = MobileExpansionStoreTests()
        return (t, { t.testKeepsOnlyTheNewestSteps() })
    }),
    ("expansion/clear", {
        let t = MobileExpansionStoreTests()
        return (t, { t.testIgnoresLegacyTurnOnlyEntriesAndClears() })
    }),
    ("order/merge-process", {
        let t = MobileTranscriptOrderTests()
        return (t, { t.testMergesOnlyAdjacentProcessRowsInTheSameTurn() })
    }),
    ("order/live-text", {
        let t = MobileTranscriptOrderTests()
        return (t, { t.testLiveTextSitsAboveTheProcessRow() })
    }),
    ("order/inserts", {
        let t = MobileTranscriptOrderTests()
        return (t, { t.testInsertsAfterTheLastEarlierRow() })
    }),
    ("order/fallback", {
        let t = MobileTranscriptOrderTests()
        return (t, { t.testFallsBackToTheTopAndSkipsSynthesizedRows() })
    }),
    ("multipart/parts", {
        let t = MobileMultipartTests()
        return (t, { try t.testParsesMetadataAndBinaryParts() })
    }),
    ("multipart/boundary", {
        let t = MobileMultipartTests()
        return (t, { try t.testParsesQuotedBoundary() })
    }),
    ("multipart/rejects", {
        let t = MobileMultipartTests()
        return (t, { t.testRejectsMissingBoundaryOrFraming() })
    }),
    ("multipart/name", {
        let t = MobileMultipartTests()
        return (t, { t.testDerivesPreviewNames() })
    }),
    ("multipart/size", {
        let t = MobileMultipartTests()
        return (t, { t.testFormatsSizes() })
    }),
    ("reading/round-trip", {
        let t = MobileReadingPositionTests()
        return (t, { t.testRoundTripsOneAnchorPerConversation() })
    }),
    ("reading/clears", {
        let t = MobileReadingPositionTests()
        return (t, { t.testClearingAndEmptyAnchorsRemoveTheKey() })
    }),
    ("reading/isolated", {
        let t = MobileReadingPositionTests()
        return (t, { t.testComputersAndSessionsDoNotShareAnchors() })
    }),
    ("draft/round-trip", {
        let t = MobileDraftStoreTests()
        return (t, { t.testRoundTripsTextAndModePerConversation() })
    }),
    ("draft/truncates", {
        let t = MobileDraftStoreTests()
        return (t, { t.testLongDraftsAreTruncated() })
    }),
    ("draft/clears-empty", {
        let t = MobileDraftStoreTests()
        return (t, { t.testEmptyMessageDraftClearsTheKey() })
    }),
    ("draft/isolated", {
        let t = MobileDraftStoreTests()
        return (t, { t.testComputersSessionsAndNewConversationsDoNotShareDrafts() })
    }),
    ("draft/mode-only", {
        let t = MobileDraftStoreTests()
        return (t, { t.testModeWithoutTextSurvivesAndClearingRemovesIt() })
    }),
    ("activity/live-line", {
        let t = MobileChatActivityTests()
        return (t, { t.testLiveLineNamesTheRunningCommand() })
    }),
    ("saved/legacy-decode", {
        let t = SavedComputerTests()
        return (t, { try t.testLegacyRecordWithoutRoutesStillDecodes() })
    }),
    ("saved/fallback-origin", {
        let t = SavedComputerTests()
        return (t, { t.testFallbackRouteChangesTheDialedOrigin() })
    }),
    ("saved/preferred-port", {
        let t = SavedComputerTests()
        return (t, { t.testPreferredOriginKeepsItsPort() })
    }),
    ("export/file-name", {
        let t = MobileImageExportTests()
        return (t, { t.testNameKeepsTheLeafAndAddsTheMediaExtension() })
    }),
    ("export/write", {
        let t = MobileImageExportTests()
        return (t, { try t.testWritePlacesTheBytesUnderThatName() })
    }),
    ("queue/edit-wire", {
        let t = MobileQueueStateTests()
        return (t, { t.testEditActionCarriesTextOnlyContent() })
    }),
    ("queue/remove-steer-wire", {
        let t = MobileQueueStateTests()
        return (t, { t.testRemoveAndSteerActionsCarryOnlyTheirKind() })
    }),
    ("queue/refusals", {
        let t = MobileQueueStateTests()
        return (t, { t.testHostRefusalCodesMapToReadableMessages() })
    }),
    ("queue/decodes", {
        let t = MobileQueueStateTests()
        return (t, { t.testDecodesQueuedAndSteeringItems() })
    }),
    ("queue/image-item", {
        let t = MobileQueueStateTests()
        return (t, { t.testImageOnlyQueuedItemIsVisibleButNotEditable() })
    }),
    ("queue/malformed", {
        let t = MobileQueueStateTests()
        return (t, { t.testMalformedStateIsRejectedInsteadOfInventingAnEmptyQueue() })
    }),
    ("format/units", {
        let t = MobileAttachmentFormatTests()
        return (t, { t.testBytesUseTheLargestSmallUnit() })
    }),
    ("format/negative", {
        let t = MobileAttachmentFormatTests()
        return (t, { t.testNegativeBytesClampToZero() })
    }),
    ("silence/short", {
        let t = MobileSilenceLabelTests()
        return (t, { t.testShortWaitsStayInSeconds() })
    }),
    ("silence/minutes", {
        let t = MobileSilenceLabelTests()
        return (t, { t.testLongerWaitsReadAsMinutesAndSeconds() })
    }),
    ("silence/hours", {
        let t = MobileSilenceLabelTests()
        return (t, { t.testHourlyWaitsDropTheSeconds() })
    }),
    ("silence/clamped", {
        let t = MobileSilenceLabelTests()
        return (t, { t.testNegativeInputClampsToZero() })
    }),
]

for (name, make) in cases {
    let (test, run) = make()
    let checksBefore = harnessChecks
    let failuresBefore = harnessFailures
    test.setUp()
    do { try run() } catch { XCTFail("threw \(error)") }
    test.tearDown()
    let ran = harnessChecks - checksBefore
    let failed = harnessFailures - failuresBefore
    print("\(failed == 0 ? "ok  " : "FAIL") \(name) (\(ran) checks)")
}

print("checks=\(harnessChecks) failures=\(harnessFailures)")
exit(harnessFailures == 0 ? 0 : 1)

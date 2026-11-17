#!/bin/sh
# Runs the pure-logic iOS unit tests without Xcode (Command Line Tools only).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
cd "$HERE"
swiftc -parse-as-library -emit-module -emit-object -module-name XCTest -o XCTest.o XCTest.swift
cd "$REPO/mobile/ios"
swiftc -I "$HERE" "$HERE/XCTest.o" \
  Sources/MobileModelCatalog.swift Sources/MobileModelPreference.swift Sources/MobileSilenceLabel.swift \
  Sources/MobileImageThumbnail.swift Sources/MobileImageExport.swift Sources/MobileConnectionAddress.swift \
  Sources/MobileFailover.swift Sources/SavedComputer.swift \
  Sources/MobileDraftStore.swift Sources/MobileReadingPosition.swift Sources/MobileMultipart.swift \
  Sources/MobileTranscriptOrder.swift Sources/MobileChangesFilter.swift Sources/MobileStreamPreview.swift Sources/MobileCodePreview.swift Sources/MobileExpansionStore.swift Sources/MobileCodeExpansionStore.swift Sources/MobileFileBrowser.swift Sources/MobileProcessLabel.swift Sources/MobileProjectCollapseStore.swift Sources/MobileDeliverables.swift \
  Sources/MobileReplyMetadata.swift \
  Sources/MobileChatAttachment.swift \
  Sources/MobileChatActivity.swift \
  Sources/MobileQueueState.swift Sources/MobileComposerSubmission.swift Sources/MobileComposerState.swift \
  Sources/MobileVoicePunctuation.swift Sources/MobileDuration.swift Sources/MobileNotificationText.swift \
  Sources/MobileNextPrompts.swift \
  UnitTests/MobileModelCatalogTests.swift UnitTests/MobileModelPreferenceTests.swift \
  UnitTests/MobileSilenceLabelTests.swift UnitTests/MobileImageThumbnailTests.swift \
  UnitTests/MobileImageExportTests.swift UnitTests/MobileConnectionAddressTests.swift \
  UnitTests/MobileFailoverTests.swift UnitTests/SavedComputerTests.swift \
  UnitTests/MobileAttachmentFormatTests.swift UnitTests/MobileChatAttachmentTests.swift \
  UnitTests/MobileChatActivityTests.swift UnitTests/MobileDraftStoreTests.swift \
  UnitTests/MobileReadingPositionTests.swift UnitTests/MobileMultipartTests.swift UnitTests/MobileTranscriptOrderTests.swift UnitTests/MobileChangesFilterTests.swift UnitTests/MobileStreamPreviewTests.swift UnitTests/MobileCodePreviewTests.swift UnitTests/MobileExpansionStoreTests.swift UnitTests/MobileCodeExpansionStoreTests.swift UnitTests/MobileFileBrowserTests.swift \
  UnitTests/MobileProcessLabelTests.swift UnitTests/MobileProjectCollapseStoreTests.swift UnitTests/MobileDeliverablesTests.swift UnitTests/MobileVoicePunctuationTests.swift UnitTests/MobileDurationTests.swift UnitTests/MobileNotificationTextTests.swift \
  UnitTests/MobileComposerStateTests.swift UnitTests/MobileNextPromptsTests.swift \
  UnitTests/MobileQueueStateTests.swift UnitTests/MobilePendingSubmissionTests.swift \
  "$HERE/main.swift" -o "$HERE/run"
"$HERE/run"

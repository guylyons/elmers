import Foundation

var failures = 0
func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    if !value() { failures += 1; print("FAIL \(file):\(line): expected true") }
}
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) rethrows {
    if try a() != b() { failures += 1; print("FAIL \(file):\(line): values differ") }
}
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #file, line: UInt = #line) rethrows {
    if try value() != nil { failures += 1; print("FAIL \(file):\(line): expected nil") }
}
func XCTAssertNotNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #file, line: UInt = #line) rethrows {
    if try value() == nil { failures += 1; print("FAIL \(file):\(line): expected a value") }
}
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try value(); failures += 1; print("FAIL \(file):\(line): expected error") } catch {}
}
if CommandLine.arguments.contains("--live-capture") {
    do { try verifyLiveCapture() } catch { failures += 1; print("FAIL live capture: \(error)") }
    exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--storage-report") { reportStorage(); exit(0) }
if CommandLine.arguments.contains("--storage-benchmark") {
    do { try benchmarkStorage() } catch { print("FAIL storage benchmark: \(error)"); exit(1) }
    exit(0)
}
let interaction = InteractionModelTests()
let history = HistoryTests()
let pasteboard = PasteboardTests()
let screenshots = ScreenshotTests()
let store = HistoryStoreTests()
let checks: [(String, () throws -> Void)] = [
    ("store creates a private empty database", store.testNewDirectoryGetsPrivateEmptyDatabase),
    ("store rejects damaged or newer databases", store.testDamagedOrNewerDatabaseIsRejectedAndLeftUntouched),
    ("store round trip preserves every field", store.testRoundTripPreservesEveryField),
    ("store saves only what changed", store.testSavesWriteOnlyWhatChanged),
    ("store keeps undo restores across reload", store.testUndoRestoresSurviveReload),
    ("plist archive converts once and is kept", store.testLegacyArchiveIsConvertedOnceAndKept),
    ("unreadable plist archive is not converted", store.testUnreadableLegacyArchiveIsNotConverted),
    ("interrupted conversion starts over", store.testInterruptedConversionStartsOver),
    ("screenshot classification and legacy decode", screenshots.testScreenshotClassificationAndLegacyDecode),
    ("Images includes screenshots", screenshots.testImageFilterIncludesScreenshots),
    ("screenshot duplicate arrival orders and persistence", screenshots.testScreenshotDuplicatesInEitherOrderPreservePins),
    ("screenshot stable file observation", screenshots.testScannerIgnoresOldFilesAndWaitsForStableMarkedBytes),
    ("screenshot retry and original file identity", screenshots.testRejectedFilesCanFinishLaterAndOriginalIdentityIsChecked),
    ("screenshot invalid and oversized files", screenshots.testOversizedUnmarkedAndNonImageFilesDoNotCapture),
    ("custom shortcut persistence, routing, and conflicts", interaction.testCustomShortcutsRoundTripAndConflicts),
    ("Paste default shortcuts", interaction.testPasteDefaultGlobalAndModifierBindings),
    ("Paste keyboard command routing", interaction.testPasteKeyboardMap),
    ("search and editor keyboard boundaries", interaction.testSearchReturnPastesAndTextEditingKeepsItsKeys),
    ("range and toggle selection", interaction.testRangeSelectionCanExpandAndContract),
    ("metadata edit and reload", interaction.testCachedMetadataRefreshesWhenEditingAndReloading),
    ("cached rich-text metadata", history.testRepeatedRichTextMetadataReadsAvoidRepeatedParsing),
    ("allowed source transitions", history.testAllowedAppTransitionRetainsClipboardGeneration),
    ("excluded source attribution", history.testSourceTransitionDoesNotAttributeExcludedContentToNextApp),
    ("duplicate promotion preserves pinboards", history.testDuplicateMovesToFrontAndKeepsPinboardMembership),
    ("search and type filters", history.testSearchMatchesTextAndSourceCaseInsensitivelyAndFiltersType),
    ("category keywords in search", history.testTypingCategoryKeywordsFiltersByKind),
    ("retention protects pins", history.testRetentionPreservesPinnedItems),
    ("board deletion preserves history", history.testDeletingBoardPreservesClipboardItem),
    ("binary archive round trip", history.testArchiveRoundTripPreservesBinaryFormatsAndBoards),
    ("corrupt archive protection", history.testCorruptArchiveIsRejectedAndNeverOverwrittenByLoad),
    ("multi-item format round trip", pasteboard.testMultiItemRoundTripPreservesEveryRepresentation),
    ("plain-text transformation", pasteboard.testPlainTextDeliveryStripsRichRepresentations),
    ("confidential content exclusion", pasteboard.testConfidentialMarkerPreventsCapture)
]
for (name, check) in checks {
    let before = failures
    do { try check() } catch { failures += 1; print("FAIL \(name): \(error)") }
    if before == failures { print("PASS \(name)") }
}
print("\(checks.count) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)

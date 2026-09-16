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
let interaction = InteractionModelTests()
let history = HistoryTests()
let pasteboard = PasteboardTests()
let checks: [(String, () throws -> Void)] = [
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

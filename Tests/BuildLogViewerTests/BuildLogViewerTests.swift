import Foundation
import Testing
@testable import BuildLogViewer

@Test func parserStripsBuildkiteAndANSIControlSequences() {
    let input = "\u{001B}_bk;t=1778846887783\u{0007}[05:16:07]: \u{001B}[31m🚨 Error: The command exited with status 1\u{001B}[0m\r\n"
    let document = LogParser.parse(text: input)

    #expect(document.lines.first?.text == "[05:16:07]: 🚨 Error: The command exited with status 1")
    #expect(document.findings.contains { $0.kind == .error })
}

@Test func parserFindsBuildFailureWarningAndFastlaneSignals() {
    let input = """
    [05:16:07]: ▸ ⚠️ warning: deprecated API
    [05:16:07]: ▸ ** TEST BUILD FAILED **
    [05:16:07]: ▸ The following build commands failed:
    [05:16:07]: ▸ SwiftCompile normal arm64 /tmp/SampleDataService.swift
    [05:16:07]: Exit status: 65
    [05:16:09]: fastlane finished with errors
    """

    let document = LogParser.parse(text: input)

    #expect(document.findings.contains { $0.kind == .warning })
    #expect(document.findings.contains { $0.kind == .buildFailure && $0.summary.contains("TEST BUILD FAILED") })
    #expect(document.findings.contains { $0.kind == .buildFailure && $0.summary.contains("SwiftCompile") })
    #expect(document.findings.contains { $0.kind == .fastlane && $0.summary.contains("Exit status: 65") })
    #expect(document.findings.contains { $0.kind == .error && $0.summary.contains("TEST BUILD FAILED") })
    #expect(document.findings.contains { $0.kind == .error && $0.summary.contains("SwiftCompile") })
    #expect(document.findings.contains { $0.kind == .error && $0.summary.contains("Exit status: 65") })
}

@Test func parserTreatsXcodeFailureSummaryAsRealErrors() {
    let input = """
    [05:16:07]: ▸ ** TEST BUILD FAILED **
    [05:16:07]: ▸ The following build commands failed:

    [05:16:07]: ▸ ⚠️ 'ExampleFeature' is missing a dependency on 'ExampleNetworking'

    [05:16:07]: ▸ \tSwiftCompile normal arm64 Compiling\\ ExampleViewModelTests.swift,\\ SampleDataService.swift /ci/builds/example-app/App/Sources/SampleDataService.swift (in target 'ExampleTests' from project 'ExampleApp')

    [05:16:07]: ▸ \tSwiftCompile normal arm64 /ci/builds/example-app/App/Sources/SampleDataService.swift (in target 'ExampleTests' from project 'ExampleApp')
    [05:16:07]: ▸ \tBuilding workspace ExampleApp for testing with scheme ExampleApp
    [05:16:07]: ▸ (3 failures)
    [05:16:07]: Exit status: 65
    """

    let document = LogParser.parse(text: input)
    let errors = document.findings(of: .error, deduplicateWarnings: true)

    #expect(errors.count == 7)
    #expect(errors.map(\.firstLineNumber) == [1, 2, 6, 8, 9, 10, 11])
    #expect(!errors.contains { $0.summary.isEmpty })
    #expect(!errors.contains { $0.summary.contains("⚠") })
    #expect(document.findings(of: .warning, deduplicateWarnings: true).contains { $0.summary.contains("ExampleFeature") })
    #expect(errors.contains { $0.summary.contains("Building workspace ExampleApp") })
}

@Test func parserDoesNotTreatErrorIdentifiersAsDiagnostics() {
    let input = """
    [05:14:47]: ▸ extension PointOfSaleBarcodeScanError: @retroactive Equatable {
    [05:15:06]: ▸                 POSListErrorView(error: errorState) {
    [05:15:06]: ▸                 POSListErrorView(error: error) {
    [05:14:38]: ▸         analytics?.track(event.statName.rawValue, properties: event.properties, error: event.error)
    """

    let document = LogParser.parse(text: input)

    #expect(!document.findings.contains { $0.kind == .error })
}

@Test func parserTreatsCompilerErrorMarkersAsDiagnostics() {
    let input = """
    error: emit-module command failed
    [05:16:07]: ▸ error: failed to compile module
    /tmp/File.swift:10:4: error: cannot find 'value' in scope
    /tmp/File.swift:10: error: expected declaration
    """

    let document = LogParser.parse(text: input)

    #expect(document.findings.filter { $0.kind == .error }.count == 4)
}

@Test func documentSearchFindsLinesAndRanges() {
    let document = LogParser.parse(text: "alpha\nSampleDataService.swift\nrun_tests\n")

    let matches = document.search("sampledataservice")

    #expect(matches.count == 1)
    #expect(matches.first?.lineNumber == 2)
    #expect(document.rangeForLine(2)?.location == 6)
}

@Test func parserRemovesEmptyDisplayLinesButPreservesOriginalLineNumbers() {
    let document = LogParser.parse(text: "first\n\nthird\n   \nerror: fifth\n")

    #expect(document.lines.map(\.number) == [1, 3, 5])
    #expect(document.text == "first\nthird\nerror: fifth")
    #expect(document.rangeForLine(3)?.location == 6)
    #expect(document.rangeForLine(5)?.location == 12)
    #expect(document.findings.first?.firstLineNumber == 5)

    let matches = document.search("fifth")
    #expect(matches.first?.lineNumber == 5)
}

@Test func warningDeduplicationCollapsesRepeatedMessages() {
    let input = """
    file.swift:1:1: warning: repeated warning
    file.swift:2:1: warning: repeated warning
    file.swift:3:1: warning: another warning
    """
    let document = LogParser.parse(text: input)

    let deduplicated = document.findings(of: .warning, deduplicateWarnings: true)
    let raw = document.findings(of: .warning, deduplicateWarnings: false)

    #expect(raw.count == 3)
    #expect(deduplicated.count == 2)
    #expect(deduplicated.first?.occurrenceCount == 2)
}

@MainActor
@Test func errorNavigationMovesBetweenErrorFindings() {
    let viewModel = LogViewModel()
    viewModel.document = LogParser.parse(text: """
    error: first
    warning: ignore
    error: second
    error: third
    """)

    viewModel.nextError()
    #expect(viewModel.selectedFinding?.firstLineNumber == 1)
    #expect(viewModel.errorNavigationDescription == "1 of 3")

    viewModel.nextError()
    #expect(viewModel.selectedFinding?.firstLineNumber == 3)
    #expect(viewModel.errorNavigationDescription == "2 of 3")

    viewModel.previousError()
    #expect(viewModel.selectedFinding?.firstLineNumber == 1)

    viewModel.previousError()
    #expect(viewModel.selectedFinding?.firstLineNumber == 4)
}

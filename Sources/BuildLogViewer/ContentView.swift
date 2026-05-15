import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: LogViewModel

    var body: some View {
        NavigationSplitView {
            FindingsSidebar(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 520)
        } detail: {
            VStack(spacing: 0) {
                HeaderBar(viewModel: viewModel)
                Divider()
                DetailContent(viewModel: viewModel)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else {
                return false
            }
            viewModel.open(url: url)
            return true
        }
    }
}

private struct HeaderBar: View {
    @Bindable var viewModel: LogViewModel

    var body: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.presentOpenPanel()
            } label: {
                Label("Open", systemImage: "folder")
            }
            .help("Open log")

            Divider()
                .frame(height: 22)

            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 260)
                .onSubmit {
                    viewModel.nextMatch()
                }
                .onChange(of: viewModel.searchQuery) {
                    viewModel.updateSearch()
                }

            Button {
                viewModel.previousMatch()
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(viewModel.searchMatches.isEmpty)
            .help("Previous match")

            Button {
                viewModel.nextMatch()
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(viewModel.searchMatches.isEmpty)
            .help("Next match")

            Text(viewModel.activeSearchDescription)
                .foregroundStyle(.secondary)
                .font(.caption.monospacedDigit())
                .frame(minWidth: 64, alignment: .leading)

            Divider()
                .frame(height: 22)

            Button {
                viewModel.previousError()
            } label: {
                Image(systemName: "xmark.octagon.fill")
                    .overlay(alignment: .topLeading) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 7, weight: .bold))
                            .offset(x: -6, y: -4)
                    }
            }
            .disabled(!viewModel.hasErrorFindings)
            .help("Previous error")

            Button {
                viewModel.nextError()
            } label: {
                Image(systemName: "xmark.octagon.fill")
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .offset(x: 6, y: 4)
                    }
            }
            .disabled(!viewModel.hasErrorFindings)
            .help("Next error")

            Text(viewModel.errorNavigationDescription)
                .foregroundStyle(.secondary)
                .font(.caption.monospacedDigit())
                .frame(minWidth: 64, alignment: .leading)

            Spacer()
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct DetailContent: View {
    @Bindable var viewModel: LogViewModel

    var body: some View {
        if viewModel.isLoading {
            ProgressView("Loading log...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView("Could not open log", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let document = viewModel.document {
            VStack(spacing: 0) {
                if let finding = viewModel.selectedFinding {
                    ContextPreview(document: document, finding: finding)
                    Divider()
                }

                LogTextView(
                    text: document.text,
                    lineNumbers: document.lines.map(\.number),
                    lineStartOffsets: document.lineStartOffsets,
                    highlightedRanges: viewModel.highlightedSearchRanges,
                    navigationRange: viewModel.navigationRange,
                    navigationToken: viewModel.navigationToken
                )

                Divider()
                StatusBar(document: document, viewModel: viewModel)
            }
        } else {
            ContentUnavailableView {
                Label("Open a log", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Drop a .log file here or open one from disk.")
            } actions: {
                Button {
                    viewModel.presentOpenPanel()
                } label: {
                    Label("Open Log", systemImage: "folder")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ContextPreview: View {
    let document: LogDocument
    let finding: LogFinding

    private var contextLines: [LogLine] {
        document.contextLines(around: finding.firstLineNumber)
    }

    private var lineNumberColumnWidth: CGFloat {
        let maxDigits = contextLines.map { String($0.number).count }.max() ?? 1
        return CGFloat(max(maxDigits, 3)) * 8 + 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: finding.kind.symbolName)
                    .foregroundStyle(finding.kind.tint)
                Text(verbatim: "Line \(finding.firstLineNumber)")
                    .font(.headline)
                Text(finding.summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(contextLines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "\(line.number)")
                            .frame(width: lineNumberColumnWidth, alignment: .trailing)
                            .foregroundStyle(.secondary)

                        Text(verbatim: line.text)
                            .foregroundStyle(line.number == finding.firstLineNumber ? finding.kind.tint : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35))
    }
}

private struct StatusBar: View {
    let document: LogDocument
    @Bindable var viewModel: LogViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text(document.url?.lastPathComponent ?? "Untitled")
                .lineLimit(1)
                .truncationMode(.middle)

            Text("\(document.lineCount.formatted()) lines")
            Text(ByteCountFormatter.string(fromByteCount: Int64(document.rawByteCount), countStyle: .file))
            Text("\(document.findings.count.formatted()) findings")

            Spacer()

            if viewModel.highlightedSearchRanges.count == 1_000 {
                Text("Showing first 1,000 highlights")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

extension FindingKind {
    var tint: Color {
        switch self {
        case .error:
            .red
        case .warning:
            .orange
        case .buildFailure:
            .purple
        case .fastlane:
            .blue
        }
    }
}

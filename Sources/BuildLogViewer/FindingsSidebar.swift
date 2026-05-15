import SwiftUI

struct FindingsSidebar: View {
    @Bindable var viewModel: LogViewModel

    var body: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $viewModel.deduplicateWarnings) {
                Label("Deduplicate warnings", systemImage: "line.3.horizontal.decrease.circle")
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List(selection: $viewModel.selectedFindingID) {
                if viewModel.document == nil {
                    Section("Findings") {
                        Text("No log loaded")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(FindingKind.allCases) { kind in
                        let findings = viewModel.displayedFindings(for: kind)
                        Section("\(kind.title) (\(findings.count))") {
                            if findings.isEmpty {
                                Text("None")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(findings) { finding in
                                    FindingRow(finding: finding)
                                        .tag(finding.id)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: viewModel.selectedFindingID) {
                viewModel.selectFinding(id: viewModel.selectedFindingID)
            }
        }
    }
}

private struct FindingRow: View {
    let finding: LogFinding

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: finding.kind.symbolName)
                .foregroundStyle(finding.kind.tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: "Line \(finding.firstLineNumber)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if finding.occurrenceCount > 1 {
                        Text(verbatim: "x\(finding.occurrenceCount)")
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.14), in: Capsule())
                    }
                }

                Text(finding.summary)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 3)
    }
}

import SwiftUI

@main
struct BuildLogViewerApp: App {
    @State private var viewModel = LogViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 980, minHeight: 640)
                .onOpenURL { url in
                    viewModel.open(url: url)
                }
                .task {
                    viewModel.openInitialArgumentIfNeeded()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button {
                    viewModel.presentOpenPanel()
                } label: {
                    Label("Open Log...", systemImage: "folder")
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

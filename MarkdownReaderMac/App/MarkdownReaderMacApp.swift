import SwiftUI

@main
struct MarkdownReaderMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("MarkGo", id: "library") {
            LibraryWindow()
                .frame(minWidth: 880, minHeight: 580)
                .preferredColorScheme(.light)
                .background(WindowAccessor { window in
                    window.appearance = NSAppearance(named: .aqua)
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden
                    window.isMovableByWindowBackground = true
                    window.tabbingMode = .disallowed
                })
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            AppCommands()
        }

        DocumentGroup(viewing: MarkdownDocument.self) { file in
            DocumentReaderRoot(document: file.$document, fileURL: file.fileURL)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.light)
                .background(WindowAccessor { window in
                    window.appearance = NSAppearance(named: .aqua)
                    window.titlebarAppearsTransparent = true
                    window.tabbingMode = .preferred
                })
        }
        .commands {
            DocumentCommands()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.appearance = NSAppearance(named: .aqua)
    }
}

/// Bridges to the underlying NSWindow so we can refine chrome behavior beyond
/// what SwiftUI exposes directly.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            configure(window)
        }
    }
}

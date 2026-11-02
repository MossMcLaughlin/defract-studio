import SwiftUI
import AppKit

@MainActor
final class EditorApplicationDelegate: NSObject, NSApplicationDelegate {
    static var quitPending = false
    static var windows: [WindowCloseObserver.Coordinator] = []

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let dirty = Self.windows.first(where: { $0.model.hasUnexportedEdits }) else {
            Self.quitPending = false
            return .terminateNow
        }
        Self.quitPending = true
        dirty.window?.makeKeyAndOrderFront(nil)
        dirty.window?.performClose(nil)
        return .terminateCancel
    }
}

struct WindowCloseObserver: NSViewRepresentable {
    @ObservedObject var model: EditorModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> InstallingView {
        let view = InstallingView()
        view.install = { [weak coordinator = context.coordinator] window in coordinator?.attach(to: window) }
        return view
    }

    func updateNSView(_ view: InstallingView, context: Context) {
        context.coordinator.model = model
    }

    final class InstallingView: NSView {
        var install: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { install?(window) }
        }
    }

    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        var model: EditorModel
        weak var window: NSWindow?
        var previousDelegate: NSWindowDelegate?
        private var allowClose = false
        private var prompting = false

        init(model: EditorModel) { self.model = model }

        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            previousDelegate = window.delegate
            self.window = window
            window.delegate = self
            EditorApplicationDelegate.windows.append(self)
            model.closeWindowAfterExport = { [weak self] in self?.window?.performClose(nil) }
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if allowClose || !model.hasUnexportedEdits {
                return previousDelegate?.windowShouldClose?(sender) ?? true
            }
            guard !prompting else { return false }
            prompting = true
            let alert = NSAlert()
            alert.messageText = "Close with edits that have not been exported?"
            alert.informativeText = model.autosaveFailed
                ? "Autosave failed. Export or cancel and resolve the save error before closing."
                : "Your edits are saved and will return when you reopen the app."
            alert.addButton(withTitle: "Export…")
            alert.addButton(withTitle: "Close & Keep Edits").isEnabled = !model.autosaveFailed
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: sender) { [weak self] response in
                guard let self else { return }
                self.prompting = false
                switch response {
                case .alertFirstButtonReturn:
                    self.model.closeAfterExport = true
                    self.model.exportSheetRequested = true
                case .alertSecondButtonReturn:
                    self.close()
                default: EditorApplicationDelegate.quitPending = false
                }
            }
            return false
        }

        private func close() {
            allowClose = true
            window?.performClose(nil)
            allowClose = false
        }

        func windowWillClose(_ notification: Notification) {
            model.closeWindowAfterExport = nil
            if let window, window.delegate === self { window.delegate = previousDelegate }
            previousDelegate = nil
            EditorApplicationDelegate.windows.removeAll { $0 === self }
            if EditorApplicationDelegate.quitPending {
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }
}

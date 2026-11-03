import SwiftUI
import AppKit
import EditorCore

struct ExportSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var options: ExportOptions
    @State private var showReplace = false
    @State private var validationError: String?

    init(model: EditorModel) {
        self.model = model
        let recipe = model.draft ?? EditRecipe(sourcePath: "Untitled", kind: .photo)
        var initial = ExportOptions(recipe: recipe, sourceSize: model.sourceSize)
        let key = recipe.kind == .photo ? "photoExportFolder" : "videoExportFolder"
        if let saved = UserDefaults.standard.string(forKey: key) { initial.folder = URL(fileURLWithPath: saved) }
        _options = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Selected File").font(.title2.bold())
            Text("The preview shows the chosen frame. Fit adds neutral padding; Fill crops to the frame.")
                .font(.caption).foregroundStyle(.secondary)
            Form {
                Picker("Preset", selection: $options.preset) {
                    ForEach(ExportPreset.allCases) { preset in Text(preset.rawValue).tag(preset) }
                }
                Picker("Frame", selection: $options.aspect) {
                    ForEach(ExportAspect.allCases) { aspect in Text(aspect.rawValue).tag(aspect) }
                }
                Picker("Framing", selection: $options.mode) {
                    Text("Fit · keep all content").tag(FrameMode.fit)
                    Text("Fill · crop to frame").tag(FrameMode.fill)
                }
                HStack {
                    TextField("Width", value: $options.width, format: .number)
                    Text("×")
                    TextField("Height", value: $options.height, format: .number)
                    Text("pixels")
                }
                if model.kind == .photo {
                    Picker("Format", selection: $options.photoFormat) {
                        ForEach(PhotoFormat.allCases) { format in Text(format.rawValue).tag(format) }
                    }
                } else {
                    Picker("Codec", selection: $options.videoCodec) {
                        Text("H.264 · compatible").tag(VideoCodec.h264)
                        Text("HEVC · smaller file").tag(VideoCodec.hevc)
                    }
                }
                TextField("File name", text: $options.name)
                HStack {
                    Text(options.folder.path).lineLimit(1).truncationMode(.middle)
                        .font(.caption).textSelection(.enabled)
                    Spacer()
                    Button("Choose Folder…", action: chooseFolder)
                }
            }
            if let validationError { Text(validationError).foregroundStyle(.red).font(.caption) }
            if let output = model.lastExportURL {
                HStack {
                    Text("Export complete: \(output.lastPathComponent)")
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                }.font(.caption)
            }
            if model.busy {
                ProgressView(value: model.exportProgress)
                HStack { Text("\(Int(model.exportProgress * 100))%") ; Spacer(); Button("Cancel Export") { model.cancelExport() } }
            } else {
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                    Button("Export") { startExport() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.draft == nil)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { if !model.busy { model.lastExportURL = nil }; model.previewExport(options.outputFrame) }
        .onDisappear {
            model.clearExportPreview()
            if !model.busy && model.closeAfterExport {
                model.closeAfterExport = false
                EditorApplicationDelegate.quitPending = false
            }
        }
        .onChange(of: options.preset) { _, _ in updateSize() }
        .onChange(of: options.aspect) { _, _ in updateSize() }
        .onChange(of: options.outputFrame) { _, frame in model.previewExport(frame) }
        .confirmationDialog("Replace the existing export?", isPresented: $showReplace) {
            Button("Replace", role: .destructive) { startExport(overwrite: true) }
        } message: { Text("The existing output will be replaced only after the new export succeeds.") }
    }

    private func updateSize() {
        guard let recipe = model.draft else { return }
        options.updateSuggestedSize(sourceSize: recipe.geometry.outputSize(for: model.sourceSize), kind: recipe.kind)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.fileExists(atPath: options.folder.path)
            ? options.folder : FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK, let url = panel.url { options.folder = url }
    }

    private func startExport(overwrite: Bool = false) {
        guard let kind = model.kind else { return }
        do {
            let destination = try options.destination(kind: kind)
            guard destination.standardizedFileURL != URL(fileURLWithPath: model.draft?.sourcePath ?? "").standardizedFileURL else {
                throw NSError(domain: "Editor", code: 9, userInfo: [NSLocalizedDescriptionKey: "Choose a destination other than the original file."])
            }
            if FileManager.default.fileExists(atPath: destination.path) && !overwrite {
                showReplace = true
                return
            }
            try model.startExport(options, overwrite: overwrite)
            let key = kind == .photo ? "photoExportFolder" : "videoExportFolder"
            UserDefaults.standard.set(options.folder.path, forKey: key)
            validationError = nil
        } catch { validationError = error.localizedDescription }
    }
}

import SwiftUI
import AppKit
import AVKit
import CoreImage
import EditorCore

@main
struct EditorApp: App {
    var body: some Scene {
        WindowGroup("Photo & Video Editor") {
            EditorView()
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

struct EditorView: View {
    @State private var sourceURL: URL?
    @State private var grade = BasicGrade()
    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var error: String?
    @State private var busy = false

    private var isVideo: Bool { sourceURL.map { ["mp4", "mov"].contains($0.pathExtension.lowercased()) } ?? false }

    var body: some View {
        HStack(spacing: 0) {
            VStack {
                HStack {
                    Button("Open…", action: open)
                    Button("Export…", action: export).disabled(sourceURL == nil || busy)
                }
                Text(sourceURL?.lastPathComponent ?? "Open a photo or video")
                    .lineLimit(1)
                Spacer()
                if let player { PlayerView(player: player) }
                else if let image { Image(nsImage: image).resizable().scaledToFit() }
                Spacer()
                if isVideo {
                    HStack {
                        Button("Play") { player?.play() }
                        Button("Pause") { player?.pause() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(Color(red: 0.08, green: 0.09, blue: 0.09))
            VStack(alignment: .leading, spacing: 12) {
                Text("Color").font(.title2)
                Text("Exposure \(grade.exposure, specifier: "%.2f")")
                Slider(value: $grade.exposure, in: -3...3)
                Text("Saturation \(Int(grade.saturation))")
                Slider(value: $grade.saturation, in: -100...100)
                Spacer()
            }
            .frame(width: 280)
            .padding()
            .onChange(of: grade) { _, _ in refresh() }
        }
        .preferredColorScheme(.dark)
        .alert("Media error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .mpeg4Movie, .quickTimeMovie]
        if panel.runModal() == .OK, let url = panel.url {
            sourceURL = url
            grade = BasicGrade()
            refresh()
        }
    }

    private func refresh() {
        guard let url = sourceURL else { return }
        if isVideo {
            let wasPlaying = player?.rate ?? 0 > 0
            let time = player?.currentTime() ?? .zero
            Task {
                do {
                    let item = try await MediaIO.videoItem(url: url, grade: grade)
                    await MainActor.run {
                        image = nil
                        player = AVPlayer(playerItem: item)
                        player?.seek(to: time)
                        if wasPlaying { player?.play() }
                    }
                } catch { await MainActor.run { self.error = error.localizedDescription } }
            }
        } else {
            do {
                image = try MediaIO.photoPreview(url: url, grade: grade)
                player = nil
            } catch { self.error = error.localizedDescription }
        }
    }

    private func export() {
        guard let url = sourceURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + "-edited." + (isVideo ? "mp4" : "jpg")
        if panel.runModal() != .OK { return }
        guard let destination = panel.url else { return }
        busy = true
        Task {
            do {
                if isVideo { try await MediaIO.exportVideo(url: url, to: destination, grade: grade) }
                else { try MediaIO.exportPhoto(url: url, to: destination, grade: grade) }
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView { AVPlayerView() }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player; view.controlsStyle = .none }
}

import SwiftUI
import AppKit

struct MenuContentView: View {
    @Environment(XcodeController.self) private var controller

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { controller.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "hammer.fill").foregroundStyle(.secondary)
            Text("XcodeMini").font(.headline)
            Spacer()
            Button(action: controller.refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("更新")
        }
    }

    // MARK: - Content (depends on access / preconditions)

    @ViewBuilder
    private var content: some View {
        switch controller.access {
        case .ok:
            if controller.workspaceName == nil {
                notice("Xcodeでworkspaceが開かれていません", systemImage: "folder.badge.questionmark")
            } else {
                controls
            }
        case .notDetermined:
            VStack(alignment: .leading, spacing: 8) {
                notice("XcodeMiniにXcodeの操作を許可してください", systemImage: "lock.shield")
                Button("アクセスを許可") { controller.requestAccess() }
            }
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                notice("Xcodeの操作が許可されていません", systemImage: "lock.slash")
                Button("システム設定を開く") { controller.openAutomationSettings() }
            }
        case .xcodeNotRunning:
            notice("Xcodeが起動していません", systemImage: "xmark.circle")
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "macwindow").foregroundStyle(.secondary)
                Text(controller.workspaceName ?? "")
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            schemePicker
            destinationPicker

            HStack(spacing: 8) {
                Button(action: controller.run) {
                    Label("実行", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.canRun)

                Button(action: controller.stop) {
                    Label("停止", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!controller.canStop)
            }
        }
    }

    private var schemePicker: some View {
        Picker("Scheme", selection: Binding(
            get: { controller.selectedSchemeIndex },
            set: { controller.selectScheme($0) }
        )) {
            Text("—").tag(Int?.none)
            ForEach(Array(controller.schemes.enumerated()), id: \.offset) { idx, scheme in
                Text(scheme.name ?? "(no name)").tag(Int?(idx))
            }
        }
        .pickerStyle(.menu)
    }

    private var destinationPicker: some View {
        Picker("Destination", selection: Binding(
            get: { controller.selectedDestinationIndex },
            set: { controller.selectDestination($0) }
        )) {
            Text("—").tag(Int?.none)
            ForEach(Array(controller.destinations.enumerated()), id: \.offset) { idx, dest in
                Text(destinationLabel(dest)).tag(Int?(idx))
            }
        }
        .pickerStyle(.menu)
        .disabled(controller.selectedSchemeIndex == nil)
    }

    private func destinationLabel(_ dest: XcodeRunDestination) -> String {
        let name = dest.name ?? "(no name)"
        if let platform = dest.platform, !platform.isEmpty {
            return "\(name) — \(platform)"
        }
        return name
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("終了") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

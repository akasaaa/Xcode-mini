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
            if controller.isLoading {
                ProgressView().controlSize(.small)
            }
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
        if !controller.hasLoadedOnce {
            // 初回のみ。以降は前回の値を保ったまま裏で更新する。
            notice("読み込み中…", systemImage: "hourglass")
        } else {
            statusContent
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch controller.access {
        case .ok:
            if controller.workspaces.isEmpty {
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
            workspacePicker
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

    private var workspacePicker: some View {
        Picker("Workspace", selection: Binding(
            get: { controller.selectedWorkspaceIndex },
            set: { controller.selectWorkspace($0) }
        )) {
            Text("—").tag(Int?.none)
            ForEach(Array(controller.workspaces.enumerated()), id: \.offset) { idx, ws in
                Text(ws.name).tag(Int?(idx))
            }
        }
        .pickerStyle(.menu)
    }

    private var schemePicker: some View {
        Picker("Scheme", selection: Binding(
            get: { controller.selectedSchemeIndex },
            set: { controller.selectScheme($0) }
        )) {
            Text("—").tag(Int?.none)
            ForEach(Array(controller.schemes.enumerated()), id: \.offset) { idx, scheme in
                Text(scheme.name).tag(Int?(idx))
            }
        }
        .pickerStyle(.menu)
        .disabled(controller.selectedWorkspaceIndex == nil)
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
        .disabled(controller.selectedSchemeIndex == nil || controller.isLoading)
    }

    private func destinationLabel(_ dest: DestinationInfo) -> String {
        dest.platform.isEmpty ? dest.name : "\(dest.name) — \(dest.platform)"
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

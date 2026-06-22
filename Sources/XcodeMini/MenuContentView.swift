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
            .help("Refresh")
        }
    }

    // MARK: - Content (depends on access / preconditions)

    @ViewBuilder
    private var content: some View {
        if !controller.hasLoadedOnce {
            // First open only; afterwards the previous values stay while we refresh.
            notice("Loading…", systemImage: "hourglass")
        } else {
            statusContent
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch controller.access {
        case .ok:
            if controller.workspaces.isEmpty {
                notice("No workspace open in Xcode", systemImage: "folder.badge.questionmark")
            } else {
                controls
            }
        case .notDetermined:
            VStack(alignment: .leading, spacing: 8) {
                notice("Allow XcodeMini to control Xcode", systemImage: "lock.shield")
                Button("Allow Access") { controller.requestAccess() }
            }
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                notice("XcodeMini isn’t allowed to control Xcode", systemImage: "lock.slash")
                Button("Open Settings") { controller.openAutomationSettings() }
            }
        case .xcodeNotRunning:
            notice("Xcode isn’t running", systemImage: "xmark.circle")
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
                    Label("Run", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.canRun)

                Button(action: controller.stop) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!controller.canStop)
            }
        }
    }

    /// Fixed label width so all three pickers line up at the same left edge.
    private static let pickerLabelWidth: CGFloat = 80

    private func pickerLabel(_ text: String) -> some View {
        Text(text)
            .frame(width: Self.pickerLabelWidth, alignment: .trailing)
            .foregroundStyle(.secondary)
    }

    private var workspacePicker: some View {
        HStack(spacing: 8) {
            pickerLabel("Workspace")
            Picker("Workspace", selection: Binding(
                get: { controller.selectedWorkspaceIndex },
                set: { controller.selectWorkspace($0) }
            )) {
                Text("—").tag(Int?.none)
                ForEach(Array(controller.workspaces.enumerated()), id: \.offset) { idx, ws in
                    Text(ws.name).tag(Int?(idx))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var schemePicker: some View {
        HStack(spacing: 8) {
            pickerLabel("Scheme")
            Picker("Scheme", selection: Binding(
                get: { controller.selectedSchemeIndex },
                set: { controller.selectScheme($0) }
            )) {
                Text("—").tag(Int?.none)
                ForEach(Array(controller.schemes.enumerated()), id: \.offset) { idx, scheme in
                    Text(scheme.name).tag(Int?(idx))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .disabled(controller.selectedWorkspaceIndex == nil)
    }

    private var destinationPicker: some View {
        HStack(spacing: 8) {
            pickerLabel("Destination")
            Picker("Destination", selection: Binding(
                get: { controller.selectedDestinationIndex },
                set: { controller.selectDestination($0) }
            )) {
                Text("—").tag(Int?.none)
                ForEach(Array(controller.destinations.enumerated()), id: \.offset) { idx, dest in
                    Text(destinationLabel(dest)).tag(Int?(idx))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .disabled(controller.selectedSchemeIndex == nil || controller.isLoading)
    }

    private func destinationLabel(_ dest: DestinationInfo) -> String {
        dest.platform.isEmpty ? dest.name : "\(dest.name) — \(dest.platform)"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
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

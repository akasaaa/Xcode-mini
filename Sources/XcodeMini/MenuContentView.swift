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
        .onAppear {
            controller.refresh()
            controller.startPolling()
        }
        .onDisappear { controller.stopPolling() }
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
            statusRow

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
                // Placeholder only when there is nothing to choose; hidden once
                // real options exist.
                if controller.workspaces.isEmpty {
                    Text("—").tag(Int?.none)
                }
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
                if controller.schemes.isEmpty {
                    Text("—").tag(Int?.none)
                }
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
                if controller.destinations.isEmpty {
                    Text("—").tag(Int?.none)
                }
                // Group by platform so simulators, devices and Mac are separated
                // under section headers in the dropdown.
                ForEach(destinationGroups) { group in
                    Section(group.category) {
                        ForEach(group.items) { item in
                            Text(item.info.name).tag(Int?(item.index))
                        }
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .disabled(controller.selectedSchemeIndex == nil || controller.isLoading)
    }

    private struct DestinationItem: Identifiable {
        let index: Int          // index into controller.destinations (the tag)
        let info: DestinationInfo
        var id: Int { index }
    }

    private struct DestinationGroup: Identifiable {
        let category: String
        let items: [DestinationItem]
        var id: String { category }
    }

    /// Destinations grouped by platform category, in first-appearance order
    /// (Xcode already returns Mac/device first, then simulators).
    private var destinationGroups: [DestinationGroup] {
        var order: [String] = []
        var byCategory: [String: [DestinationItem]] = [:]
        for (index, info) in controller.destinations.enumerated() {
            let category = destinationCategory(info.platform)
            if byCategory[category] == nil { order.append(category) }
            byCategory[category, default: []].append(DestinationItem(index: index, info: info))
        }
        return order.map { DestinationGroup(category: $0, items: byCategory[$0]!) }
    }

    /// Friendly section title for a run destination's `platform` identifier.
    private func destinationCategory(_ platform: String) -> String {
        switch platform {
        case "macosx": return "macOS"
        case "iphoneos": return "iOS"
        case "iphonesimulator": return "iOS Simulator"
        case "appletvos": return "tvOS"
        case "appletvsimulator": return "tvOS Simulator"
        case "watchos": return "watchOS"
        case "watchsimulator": return "watchOS Simulator"
        case "xros": return "visionOS"
        case "xrsimulator": return "visionOS Simulator"
        case "": return "Other"
        default: return platform
        }
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack(spacing: 8) {
            pickerLabel("Status")
            statusIndicator
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch controller.runStatus {
        case .running, .notStarted:
            ProgressView().controlSize(.small)
        default:
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
    }

    private var statusText: String {
        switch controller.runStatus {
        case .none: return "—"
        case .notStarted: return "Starting…"
        case .running: return "Running"
        case .cancelled: return "Stopped"
        case .failed: return "Failed"
        case .error: return "Error"
        case .succeeded: return "Succeeded"
        }
    }

    private var statusColor: Color {
        switch controller.runStatus {
        case .running, .notStarted: return .accentColor
        case .succeeded: return .green
        case .failed, .error: return .red
        case .cancelled: return .orange
        case .none: return .secondary
        }
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

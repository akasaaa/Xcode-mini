import Foundation
import AppKit
import CoreServices
import ScriptingBridge

/// Drives Xcode through ScriptingBridge: lists schemes / run destinations,
/// applies the active selection, and sends the run / stop scheme actions.
///
/// Design: fire-and-forget. Commands are sent without polling the resulting
/// `scheme action result`, so there is no build progress / failure feedback.
/// The one exception is the up-front automation-permission and precondition
/// check (`Access`), which is the only place a command can fail silently.
@MainActor
@Observable
final class XcodeController {

    enum Access: Equatable {
        case ok
        case denied
        case notDetermined
        case xcodeNotRunning
    }

    private static let bundleID = "com.apple.dt.Xcode"

    private(set) var access: Access = .notDetermined
    /// nil when no workspace document is open in Xcode.
    private(set) var workspaceName: String?
    private(set) var schemes: [XcodeScheme] = []
    private(set) var destinations: [XcodeRunDestination] = []
    private(set) var selectedSchemeIndex: Int?
    private(set) var selectedDestinationIndex: Int?

    @ObservationIgnored
    private lazy var app: XcodeApplication? =
        SBApplication(bundleIdentifier: XcodeController.bundleID)

    private var document: XcodeWorkspaceDocument? { app?.activeWorkspaceDocument }

    private var isXcodeRunning: Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: XcodeController.bundleID)
            .isEmpty
    }

    // MARK: - Refresh (called every time the menu popover opens)

    func refresh() {
        guard isXcodeRunning else {
            reset(access: .xcodeNotRunning)
            return
        }
        let permission = checkPermission(prompt: false)
        guard permission == .ok else {
            reset(access: permission)
            return
        }
        access = .ok
        loadLists()
    }

    private func reset(access: Access) {
        self.access = access
        workspaceName = nil
        schemes = []
        destinations = []
        selectedSchemeIndex = nil
        selectedDestinationIndex = nil
    }

    private func loadLists() {
        guard let doc = document else {
            workspaceName = nil
            schemes = []
            destinations = []
            selectedSchemeIndex = nil
            selectedDestinationIndex = nil
            return
        }
        workspaceName = doc.name ?? "(workspace)"
        schemes = doc.schemes?() ?? []
        selectedSchemeIndex = indexOfActiveScheme(in: doc)
        if selectedSchemeIndex == nil {
            // scheme 未選択なら実行先も未選択に（実行先は scheme 依存）
            destinations = []
            selectedDestinationIndex = nil
        } else {
            destinations = doc.runDestinations?() ?? []
            selectedDestinationIndex = indexOfActiveDestination(in: doc)
        }
    }

    private func indexOfActiveScheme(in doc: XcodeWorkspaceDocument) -> Int? {
        let activeName = doc.activeScheme?.name
        return schemes.firstIndex { $0.name == activeName }
    }

    private func indexOfActiveDestination(in doc: XcodeWorkspaceDocument) -> Int? {
        let active = doc.activeRunDestination
        return destinations.firstIndex {
            $0.name == active?.name && $0.platform == active?.platform
        }
    }

    // MARK: - Selection

    func selectScheme(_ index: Int?) {
        selectedSchemeIndex = index
        guard let i = index, let doc = document, schemes.indices.contains(i) else {
            // scheme 未選択なら実行先も未選択に（実行先は scheme 依存）
            destinations = []
            selectedDestinationIndex = nil
            return
        }
        doc.setActiveScheme?(schemes[i])
        // Run destinations are scheme-dependent, so reload them after switching.
        destinations = doc.runDestinations?() ?? []
        selectedDestinationIndex = indexOfActiveDestination(in: doc)
    }

    func selectDestination(_ index: Int?) {
        selectedDestinationIndex = index
        guard let i = index, let doc = document, destinations.indices.contains(i) else { return }
        doc.setActiveRunDestination?(destinations[i])
    }

    // MARK: - Scheme actions (fire-and-forget)

    /// 実行: scheme と実行先の両方が選択されているときだけ可能。
    var canRun: Bool {
        access == .ok && selectedSchemeIndex != nil && selectedDestinationIndex != nil
    }

    /// 停止: scheme が選択されているときだけ可能。
    var canStop: Bool {
        access == .ok && selectedSchemeIndex != nil
    }

    func run() {
        guard canRun, let doc = document else { return }
        _ = doc.runWithCommandLineArguments?(nil, withEnvironmentVariables: nil)
    }

    func stop() {
        guard canStop, let doc = document else { return }
        doc.stop?()
    }

    // MARK: - Automation permission

    /// Asks the system to (optionally) prompt for automation access, then refreshes.
    func requestAccess() {
        _ = checkPermission(prompt: true)
        refresh()
    }

    func openAutomationSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    private func checkPermission(prompt: Bool) -> Access {
        let target = NSAppleEventDescriptor(bundleIdentifier: XcodeController.bundleID)
        guard let desc = target.aeDesc else { return .denied }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, prompt)
        switch status {
        case noErr:
            return .ok
        case OSStatus(-1743): // errAEEventNotPermitted
            return .denied
        case OSStatus(-1744): // errAEEventWouldRequireUserConsent
            return .notDetermined
        case OSStatus(-600):  // procNotFound
            return .xcodeNotRunning
        default:
            return .denied
        }
    }
}

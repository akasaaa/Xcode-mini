import Foundation
import AppKit
import Observation

/// Main-actor, observable view state for the menu UI.
///
/// All ScriptingBridge work is delegated to `XcodeService` on a background
/// queue; this type only holds plain value snapshots and applies them when
/// they arrive. During a load the previous values are kept (no clearing), so
/// reopening the popover never blocks the main thread or flickers.
@MainActor
@Observable
final class XcodeController {

    private(set) var access: XcodeAccess = .notDetermined
    private(set) var workspaces: [WorkspaceInfo] = []
    private(set) var schemes: [SchemeInfo] = []
    private(set) var destinations: [DestinationInfo] = []
    private(set) var selectedWorkspaceIndex: Int?
    private(set) var selectedSchemeIndex: Int?
    private(set) var selectedDestinationIndex: Int?

    /// Live status of the selected workspace's most recent scheme action,
    /// refreshed by `startPolling()` while the menu is open.
    private(set) var runStatus: RunStatus = .none

    /// A background read is in flight.
    private(set) var isLoading = false
    /// False until the first snapshot arrives, so the UI can show a placeholder
    /// instead of empty pickers on the very first open.
    private(set) var hasLoadedOnce = false

    @ObservationIgnored private let service = XcodeService()
    /// Identifies the latest request so stale snapshots are discarded.
    @ObservationIgnored private var loadToken = 0
    /// Repeating status poll; runs only while the menu is open.
    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    // MARK: - Loads (non-blocking)

    func refresh() {
        let token = beginLoad()
        Task {
            let snapshot = await service.refresh()
            apply(snapshot, token: token)
        }
    }

    func requestAccess() {
        let token = beginLoad()
        Task {
            let snapshot = await service.requestAccess()
            apply(snapshot, token: token)
        }
    }

    // MARK: - Status polling (active only while the menu is open)

    /// Starts polling the run status every half second. Idempotent.
    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                self.runStatus = await self.service.runStatus()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Selection

    func selectWorkspace(_ index: Int?) {
        // Re-selecting the same value must not trigger a re-fetch.
        guard index != selectedWorkspaceIndex else { return }
        // Optimistic update; schemes/destinations belong to the previous workspace.
        selectedWorkspaceIndex = index
        schemes = []
        destinations = []
        selectedSchemeIndex = nil
        selectedDestinationIndex = nil
        let token = beginLoad()
        Task {
            let snapshot = await service.selectWorkspace(index: index)
            apply(snapshot, token: token)
        }
    }

    func selectScheme(_ index: Int?) {
        // Re-selecting the same value must not trigger a re-fetch.
        guard index != selectedSchemeIndex else { return }
        // Optimistic update so the picker responds instantly.
        selectedSchemeIndex = index
        guard let index else {
            // scheme 未選択なら実行先も未選択（実行先は scheme 依存）
            destinations = []
            selectedDestinationIndex = nil
            return
        }
        let token = beginLoad()
        Task {
            let snapshot = await service.selectScheme(index: index)
            apply(snapshot, token: token)
        }
    }

    func selectDestination(_ index: Int?) {
        // Re-selecting the same value must not re-apply.
        guard index != selectedDestinationIndex else { return }
        selectedDestinationIndex = index
        if let index { service.selectDestination(index: index) }
    }

    // MARK: - Scheme actions (fire-and-forget)

    var canRun: Bool {
        access == .ok
            && selectedWorkspaceIndex != nil
            && selectedSchemeIndex != nil
            && selectedDestinationIndex != nil
    }

    /// Stop is enabled only while an action is actually in progress.
    var canStop: Bool {
        access == .ok && runStatus.isStoppable
    }

    func run() {
        guard canRun else { return }
        service.run()
    }

    func stop() {
        guard canStop else { return }
        service.stop()
    }

    func openAutomationSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    private func beginLoad() -> Int {
        loadToken += 1
        isLoading = true
        return loadToken
    }

    private func apply(_ snapshot: WorkspaceSnapshot, token: Int) {
        // Discard if a newer request superseded this one.
        guard token == loadToken else { return }
        access = snapshot.access
        workspaces = snapshot.workspaces
        schemes = snapshot.schemes
        destinations = snapshot.destinations
        selectedWorkspaceIndex = snapshot.selectedWorkspaceIndex
        selectedSchemeIndex = snapshot.selectedSchemeIndex
        selectedDestinationIndex = snapshot.selectedDestinationIndex
        hasLoadedOnce = true
        isLoading = false
    }
}

import Foundation
import AppKit
import CoreServices
import ScriptingBridge

enum XcodeAccess: Sendable {
    case ok
    case denied
    case notDetermined
    case xcodeNotRunning
}

/// State of the selected workspace's most recent scheme action (run/build/test).
/// Mirrors Xcode's `scheme action result status`, plus `.none` for "no action
/// has run yet / unknown".
enum RunStatus: Sendable {
    case none
    case notStarted
    case running
    case cancelled
    case failed
    case error
    case succeeded

    /// True while an action is in progress and therefore stoppable.
    var isStoppable: Bool { self == .running || self == .notStarted }
}

/// Plain, Sendable value types handed to the main actor for display.
/// SBObjects never cross the actor boundary.
struct WorkspaceInfo: Sendable {
    let name: String
}

struct SchemeInfo: Sendable {
    let name: String
}

struct DestinationInfo: Sendable {
    let name: String
    let platform: String
}

struct WorkspaceSnapshot: Sendable {
    var access: XcodeAccess
    var workspaces: [WorkspaceInfo]
    var schemes: [SchemeInfo]
    var destinations: [DestinationInfo]
    var selectedWorkspaceIndex: Int?
    var selectedSchemeIndex: Int?
    var selectedDestinationIndex: Int?

    static func empty(_ access: XcodeAccess) -> WorkspaceSnapshot {
        WorkspaceSnapshot(access: access, workspaces: [], schemes: [], destinations: [],
                          selectedWorkspaceIndex: nil, selectedSchemeIndex: nil,
                          selectedDestinationIndex: nil)
    }
}

/// Performs all ScriptingBridge (Apple Events) work on a private serial queue,
/// off the main thread, and returns Sendable snapshots. Apple Events are
/// synchronous IPC round trips, so running them on the main thread janks the
/// menu popover while it is opening.
///
/// All operations target the *selected* workspace document (chosen in the UI),
/// not necessarily Xcode's frontmost one.
///
/// `@unchecked Sendable`: this holds non-Sendable SBObjects, but every access
/// to them is confined to `queue`, which serializes all work.
final class XcodeService: @unchecked Sendable {

    private let bundleID = "com.apple.dt.Xcode"
    private let queue = DispatchQueue(label: "co.ascendlogi.XcodeMini.bridge", qos: .userInitiated)

    private lazy var app: XcodeApplication? = SBApplication(bundleIdentifier: bundleID)

    // Touched only on `queue`.
    private var cachedWorkspaces: [XcodeWorkspaceDocument] = []
    private var cachedSchemes: [XcodeScheme] = []
    private var cachedDestinations: [XcodeRunDestination] = []
    /// Identity (path, falling back to name) of the selected workspace, so the
    /// choice survives list reordering across refreshes.
    private var selectedWorkspaceKey: String?
    private var didInitSelection = false
    /// Last-used run destination (name|platform) keyed by (workspace, scheme),
    /// persisted to UserDefaults so it survives app restarts. Xcode reports
    /// `activeRunDestination` as `missing value` over ScriptingBridge, so we
    /// remember the choice to restore it across refreshes.
    private static let destinationsDefaultsKey = "lastDestinationByContext"
    private lazy var lastDestinationByContext: [String: String] =
        (UserDefaults.standard.dictionary(forKey: Self.destinationsDefaultsKey) as? [String: String]) ?? [:]

    // MARK: - Async reads (return a snapshot)

    func refresh() async -> WorkspaceSnapshot {
        await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: self.loadSnapshot()) }
        }
    }

    func requestAccess() async -> WorkspaceSnapshot {
        await withCheckedContinuation { cont in
            queue.async {
                _ = self.checkPermission(prompt: true)
                cont.resume(returning: self.loadSnapshot())
            }
        }
    }

    /// Cheap, poll-friendly read of the selected document's current run status.
    /// Only touches `lastSchemeActionResult.status` (one property), so it can run
    /// on a short interval without the cost of a full snapshot reload.
    func runStatus() async -> RunStatus {
        await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: self.currentRunStatus()) }
        }
    }

    func selectWorkspace(index: Int?) async -> WorkspaceSnapshot {
        await withCheckedContinuation { cont in
            queue.async {
                if let index, self.cachedWorkspaces.indices.contains(index) {
                    self.selectedWorkspaceKey = self.key(self.cachedWorkspaces[index])
                } else {
                    self.selectedWorkspaceKey = nil
                }
                self.didInitSelection = true
                cont.resume(returning: self.loadSnapshot())
            }
        }
    }

    func selectScheme(index: Int) async -> WorkspaceSnapshot {
        await withCheckedContinuation { cont in
            queue.async {
                if let doc = self.selectedDocument(), self.cachedSchemes.indices.contains(index) {
                    doc.setActiveScheme?(self.cachedSchemes[index])
                }
                cont.resume(returning: self.loadSnapshot())
            }
        }
    }

    // MARK: - Fire-and-forget (no snapshot needed)

    func selectDestination(index: Int) {
        queue.async {
            guard self.cachedDestinations.indices.contains(index),
                  let doc = self.selectedDocument() else { return }
            let chosen = self.cachedDestinations[index]
            let context = self.destinationContextKey(workspaceKey: self.key(doc),
                                                     schemeName: doc.activeScheme?.name)
            self.remember(destinationKey: self.destKey(chosen), for: context)
            doc.setActiveRunDestination?(chosen)
        }
    }

    func run() {
        queue.async {
            _ = self.selectedDocument()?
                .runWithCommandLineArguments?(nil, withEnvironmentVariables: nil)
        }
    }

    func stop() {
        queue.async {
            self.selectedDocument()?.stop?()
        }
    }

    // MARK: - Queue-confined implementation

    private func loadSnapshot() -> WorkspaceSnapshot {
        guard isXcodeRunning else { resetCaches(); return .empty(.xcodeNotRunning) }

        let permission = checkPermission(prompt: false)
        guard permission == .ok else { resetCaches(); return .empty(permission) }

        cachedWorkspaces = listWorkspaces()
        let workspaceInfos = cachedWorkspaces.map { WorkspaceInfo(name: $0.name ?? "(workspace)") }

        // Default to the active workspace on first load; afterwards respect the
        // user's choice (including an explicit deselection or a closed workspace).
        if !didInitSelection {
            selectedWorkspaceKey = key(app?.activeWorkspaceDocument)
            didInitSelection = true
        }

        guard let wsIndex = indexOfSelectedWorkspace() else {
            cachedSchemes = []
            cachedDestinations = []
            return WorkspaceSnapshot(access: .ok, workspaces: workspaceInfos,
                                     schemes: [], destinations: [],
                                     selectedWorkspaceIndex: nil,
                                     selectedSchemeIndex: nil, selectedDestinationIndex: nil)
        }

        let doc = cachedWorkspaces[wsIndex]
        let activeSchemeName = doc.activeScheme?.name

        // `schemes` includes the auto-generated dependency schemes (CocoaPods /
        // SwiftPM) the toolbar hides. Filter to the ones marked shown in
        // xcschememanagement.plist (the active scheme is always kept).
        let hidden = hiddenSchemeNames(workspacePath: doc.path)
        cachedSchemes = (doc.schemes?() ?? []).filter { scheme in
            let n = scheme.name ?? ""
            return !hidden.contains(n) || n == activeSchemeName
        }
        let schemeInfos = cachedSchemes.map { SchemeInfo(name: $0.name ?? "(no name)") }
        let schemeIndex = cachedSchemes.firstIndex { $0.name == activeSchemeName }

        // Run destinations are scheme-dependent: only meaningful with an active scheme.
        guard schemeIndex != nil else {
            cachedDestinations = []
            return WorkspaceSnapshot(access: .ok, workspaces: workspaceInfos,
                                     schemes: schemeInfos, destinations: [],
                                     selectedWorkspaceIndex: wsIndex,
                                     selectedSchemeIndex: nil, selectedDestinationIndex: nil)
        }

        cachedDestinations = doc.runDestinations?() ?? []
        let destInfos = cachedDestinations.map {
            DestinationInfo(name: $0.name ?? "(no name)", platform: $0.platform ?? "")
        }
        // Pick the destination last used for this (workspace, scheme); if there
        // is none, or it no longer exists, fall back to the first candidate.
        // `activeRunDestination` can't help here — it comes back as
        // `missing value` over ScriptingBridge. The chosen destination is pushed
        // to Xcode so a run uses what the UI shows.
        let destContext = destinationContextKey(workspaceKey: key(doc), schemeName: activeSchemeName)
        var destIndex = lastDestinationByContext[destContext].flatMap { lastKey in
            cachedDestinations.firstIndex { destKey($0) == lastKey }
        }
        if destIndex == nil, !cachedDestinations.isEmpty {
            destIndex = 0
        }
        if let destIndex {
            remember(destinationKey: destKey(cachedDestinations[destIndex]), for: destContext)
            doc.setActiveRunDestination?(cachedDestinations[destIndex])
        }

        return WorkspaceSnapshot(access: .ok, workspaces: workspaceInfos,
                                 schemes: schemeInfos, destinations: destInfos,
                                 selectedWorkspaceIndex: wsIndex,
                                 selectedSchemeIndex: schemeIndex, selectedDestinationIndex: destIndex)
    }

    private func resetCaches() {
        cachedWorkspaces = []
        cachedSchemes = []
        cachedDestinations = []
    }

    /// Reads the selected document's last scheme action status. Returns `.none`
    /// when Xcode is unavailable, access is missing, no workspace is selected,
    /// or no action has run yet. Relies on the cache populated by `loadSnapshot`.
    private func currentRunStatus() -> RunStatus {
        guard isXcodeRunning,
              checkPermission(prompt: false) == .ok,
              let doc = selectedDocument(),
              let result = doc.lastSchemeActionResult else { return .none }
        return mapRunStatus(result.status ?? 0)
    }

    /// Maps Xcode's `scheme action result status` four-char code to `RunStatus`.
    private func mapRunStatus(_ code: AEKeyword) -> RunStatus {
        switch fourCharString(code) {
        case "srsn": return .notStarted
        case "srsr": return .running
        case "srsc": return .cancelled
        case "srsf": return .failed
        case "srse": return .error
        case "srss": return .succeeded
        default: return .none
        }
    }

    private func fourCharString(_ code: AEKeyword) -> String {
        let bytes = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
                     UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
        return String(bytes: bytes, encoding: .macOSRoman) ?? ""
    }

    /// Open workspace documents: every document whose name ends with
    /// `.xcworkspace` / `.xcodeproj`, plus the active workspace (deduped).
    private func listWorkspaces() -> [XcodeWorkspaceDocument] {
        var result: [XcodeWorkspaceDocument] = []
        var seen = Set<String>()
        for doc in app?.documents?() ?? [] {
            guard let name = doc.name,
                  name.hasSuffix(".xcworkspace") || name.hasSuffix(".xcodeproj") else { continue }
            let k = key(doc) ?? name
            if seen.insert(k).inserted { result.append(doc) }
        }
        if let active = app?.activeWorkspaceDocument, let ak = key(active), seen.insert(ak).inserted {
            result.insert(active, at: 0)
        }
        return result
    }

    private func indexOfSelectedWorkspace() -> Int? {
        guard let selectedWorkspaceKey else { return nil }
        return cachedWorkspaces.firstIndex { key($0) == selectedWorkspaceKey }
    }

    private func selectedDocument() -> XcodeWorkspaceDocument? {
        guard let index = indexOfSelectedWorkspace() else { return nil }
        return cachedWorkspaces[index]
    }

    private func key(_ doc: XcodeWorkspaceDocument?) -> String? {
        guard let doc else { return nil }
        return doc.path ?? doc.name
    }

    private func destKey(_ destination: XcodeRunDestination?) -> String? {
        guard let destination, let name = destination.name else { return nil }
        return "\(name)|\(destination.platform ?? "")"
    }

    private func destinationContextKey(workspaceKey: String?, schemeName: String?) -> String {
        "\(workspaceKey ?? "")\u{1}\(schemeName ?? "")"
    }

    private func remember(destinationKey: String?, for context: String) {
        guard let destinationKey, lastDestinationByContext[context] != destinationKey else { return }
        lastDestinationByContext[context] = destinationKey
        UserDefaults.standard.set(lastDestinationByContext, forKey: Self.destinationsDefaultsKey)
    }

    /// Scheme names the toolbar hides (`isShown = false` in any
    /// xcschememanagement.plist under the workspace container). An absent entry
    /// means shown, so only explicitly-hidden schemes end up here.
    private func hiddenSchemeNames(workspacePath: String?) -> Set<String> {
        guard let workspacePath else { return [] }
        let fm = FileManager.default
        let container = (workspacePath as NSString).deletingLastPathComponent

        // Bundles that may carry xcuserdata: the workspace itself plus every
        // .xcodeproj at depth 1-2 (covers Pods/Pods.xcodeproj).
        var bundles: [String] = [workspacePath]
        for entry in (try? fm.contentsOfDirectory(atPath: container)) ?? [] {
            let path = (container as NSString).appendingPathComponent(entry)
            if entry.hasSuffix(".xcodeproj") {
                bundles.append(path)
            } else {
                for sub in (try? fm.contentsOfDirectory(atPath: path)) ?? []
                where sub.hasSuffix(".xcodeproj") {
                    bundles.append((path as NSString).appendingPathComponent(sub))
                }
            }
        }

        var hidden = Set<String>()
        for bundle in bundles {
            let userdata = (bundle as NSString).appendingPathComponent("xcuserdata")
            for user in (try? fm.contentsOfDirectory(atPath: userdata)) ?? []
            where user.hasSuffix(".xcuserdatad") {
                let plist = "\(userdata)/\(user)/xcschemes/xcschememanagement.plist"
                guard let dict = NSDictionary(contentsOfFile: plist),
                      let states = dict["SchemeUserState"] as? [String: Any] else { continue }
                for (key, value) in states {
                    let state = value as? [String: Any]
                    let isShown = (state?["isShown"] as? Bool) ?? true
                    if !isShown { hidden.insert(schemeBaseName(key)) }
                }
            }
        }
        return hidden
    }

    /// "EXConstants.xcscheme_^#shared#^_" -> "EXConstants"
    private func schemeBaseName(_ key: String) -> String {
        guard let range = key.range(of: ".xcscheme") else { return key }
        return String(key[..<range.lowerBound])
    }

    private var isXcodeRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func checkPermission(prompt: Bool) -> XcodeAccess {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
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

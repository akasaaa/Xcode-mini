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

/// Plain, Sendable value types handed to the main actor for display.
/// SBObjects never cross the actor boundary.
struct SchemeInfo: Sendable {
    let name: String
}

struct DestinationInfo: Sendable {
    let name: String
    let platform: String
}

struct WorkspaceSnapshot: Sendable {
    var access: XcodeAccess
    var workspaceName: String?
    var schemes: [SchemeInfo]
    var destinations: [DestinationInfo]
    var selectedSchemeIndex: Int?
    var selectedDestinationIndex: Int?
}

/// Performs all ScriptingBridge (Apple Events) work on a private serial queue,
/// off the main thread, and returns Sendable snapshots. Apple Events are
/// synchronous IPC round trips, so running them on the main thread janks the
/// menu popover while it is opening. Keeping them here keeps the UI smooth.
///
/// `@unchecked Sendable`: this holds non-Sendable SBObjects, but every access
/// to them is confined to `queue`, which serializes all work.
final class XcodeService: @unchecked Sendable {

    private let bundleID = "com.apple.dt.Xcode"
    private let queue = DispatchQueue(label: "co.ascendlogi.XcodeMini.bridge", qos: .userInitiated)

    private lazy var app: XcodeApplication? = SBApplication(bundleIdentifier: bundleID)

    // Touched only on `queue`. Used to resolve a picker selection (by index)
    // back to the concrete SBObject needed for setActive… / run.
    private var cachedSchemes: [XcodeScheme] = []
    private var cachedDestinations: [XcodeRunDestination] = []

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

    func selectScheme(index: Int) async -> WorkspaceSnapshot {
        await withCheckedContinuation { cont in
            queue.async {
                if self.cachedSchemes.indices.contains(index),
                   let doc = self.app?.activeWorkspaceDocument {
                    doc.setActiveScheme?(self.cachedSchemes[index])
                }
                cont.resume(returning: self.loadSnapshot())
            }
        }
    }

    // MARK: - Fire-and-forget (no snapshot needed)

    func selectDestination(index: Int) {
        queue.async {
            if self.cachedDestinations.indices.contains(index),
               let doc = self.app?.activeWorkspaceDocument {
                doc.setActiveRunDestination?(self.cachedDestinations[index])
            }
        }
    }

    func run() {
        queue.async {
            _ = self.app?.activeWorkspaceDocument?
                .runWithCommandLineArguments?(nil, withEnvironmentVariables: nil)
        }
    }

    func stop() {
        queue.async {
            self.app?.activeWorkspaceDocument?.stop?()
        }
    }

    // MARK: - Queue-confined implementation

    private func loadSnapshot() -> WorkspaceSnapshot {
        guard isXcodeRunning else {
            cachedSchemes = []
            cachedDestinations = []
            return WorkspaceSnapshot(access: .xcodeNotRunning, workspaceName: nil,
                                     schemes: [], destinations: [],
                                     selectedSchemeIndex: nil, selectedDestinationIndex: nil)
        }

        let permission = checkPermission(prompt: false)
        guard permission == .ok else {
            cachedSchemes = []
            cachedDestinations = []
            return WorkspaceSnapshot(access: permission, workspaceName: nil,
                                     schemes: [], destinations: [],
                                     selectedSchemeIndex: nil, selectedDestinationIndex: nil)
        }

        guard let doc = app?.activeWorkspaceDocument else {
            cachedSchemes = []
            cachedDestinations = []
            return WorkspaceSnapshot(access: .ok, workspaceName: nil,
                                     schemes: [], destinations: [],
                                     selectedSchemeIndex: nil, selectedDestinationIndex: nil)
        }

        let name = doc.name ?? "(workspace)"
        let activeSchemeName = doc.activeScheme?.name

        // `schemes` returns every scheme Xcode knows about, including the
        // auto-generated dependency schemes (CocoaPods / SwiftPM) that the
        // toolbar hides. Filter to the ones marked shown in
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
            return WorkspaceSnapshot(access: .ok, workspaceName: name,
                                     schemes: schemeInfos, destinations: [],
                                     selectedSchemeIndex: nil, selectedDestinationIndex: nil)
        }

        cachedDestinations = doc.runDestinations?() ?? []
        let destInfos = cachedDestinations.map {
            DestinationInfo(name: $0.name ?? "(no name)", platform: $0.platform ?? "")
        }
        let activeDest = doc.activeRunDestination
        let destIndex = cachedDestinations.firstIndex {
            $0.name == activeDest?.name && $0.platform == activeDest?.platform
        }

        return WorkspaceSnapshot(access: .ok, workspaceName: name,
                                 schemes: schemeInfos, destinations: destInfos,
                                 selectedSchemeIndex: schemeIndex, selectedDestinationIndex: destIndex)
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

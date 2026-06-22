import Foundation
import ScriptingBridge

// MARK: - ScriptingBridge interface to Xcode
//
// These are hand-written @objc protocols mirroring the subset of Xcode's
// scripting dictionary (sdef) that XcodeMini uses. The full reference can be
// regenerated with:
//
//     sdef /Applications/Xcode.app | sdp -fh --basename Xcode
//
// The empty `extension SBObject: ...` / `extension SBApplication: ...` below
// declare formal protocol conformance so that `as?` casts and NSArray bridging
// succeed. The members are all `@objc optional`, so no implementation is
// required — ScriptingBridge dispatches the selectors dynamically at runtime.

@objc protocol XcodeScheme {
    @objc optional var name: String { get }
    @objc optional var id: String { get }
}

@objc protocol XcodeRunDestination {
    @objc optional var name: String { get }
    @objc optional var architecture: String { get }
    @objc optional var platform: String { get }
}

@objc protocol XcodeSchemeActionResult {
    @objc optional var id: String { get }
    @objc optional var completed: Bool { get }
    // `scheme action result status` enum. ScriptingBridge returns the value as
    // its raw four-char code (e.g. 'srsr' = running, 'srss' = succeeded).
    @objc optional var status: AEKeyword { get }
}

@objc protocol XcodeWorkspaceDocument {
    // inherited from `document`
    @objc optional var name: String { get }
    @objc optional var path: String { get }

    // elements (SBElementArray bridges to Swift Array)
    @objc optional func schemes() -> [XcodeScheme]
    @objc optional func runDestinations() -> [XcodeRunDestination]

    // active selections used by scheme actions.
    // Setters are declared as explicit methods because assigning to an
    // `@objc optional` property is not allowed (the setter may be absent).
    @objc optional var activeScheme: XcodeScheme { get }
    @objc optional func setActiveScheme(_ scheme: XcodeScheme)
    @objc optional var activeRunDestination: XcodeRunDestination { get }
    @objc optional func setActiveRunDestination(_ destination: XcodeRunDestination)

    // commands (sent to the workspace document).
    // Selector must be exactly `runWithCommandLineArguments:withEnvironmentVariables:`
    // (note the `with` prefix on the second piece) to match Xcode's sdef.
    @objc optional func runWithCommandLineArguments(_ commandLineArguments: [Any]?,
                                                    withEnvironmentVariables environmentVariables: [Any]?) -> XcodeSchemeActionResult
    @objc optional func stop()

    // Tracks the most recent scheme action (run/build/test, started from our UI
    // or Xcode's). `missing value` until an action has run.
    @objc optional var lastSchemeActionResult: XcodeSchemeActionResult { get }
}

@objc protocol XcodeApplication {
    @objc optional var activeWorkspaceDocument: XcodeWorkspaceDocument { get }
    // Returns every open document (workspaces, text documents, …); callers
    // filter to workspace documents by name suffix.
    @objc optional func documents() -> [XcodeWorkspaceDocument]
}

// Declare conformance so dynamic ScriptingBridge objects satisfy `as?` casts.
extension SBApplication: XcodeApplication {}
extension SBObject: XcodeWorkspaceDocument, XcodeScheme, XcodeRunDestination, XcodeSchemeActionResult {}

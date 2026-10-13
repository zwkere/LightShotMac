import AppKit

MainActor.assumeIsolated {
    let app=NSApplication.shared
    if CommandLine.arguments.contains("--self-test") { exit(SelfTest.run()) }
    let delegate=AppDelegate()
    app.delegate=delegate
    withExtendedLifetime(delegate) { app.run() }
}

import AppKit

if CommandLine.arguments.contains("--self-test") {
    exit(SelfTest.run())
}

let application = NSApplication.shared

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    application.setActivationPolicy(.regular)
    application.delegate = delegate
    application.run()
}

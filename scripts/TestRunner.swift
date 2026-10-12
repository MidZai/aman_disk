// Test runner for the Command Line Tools alone (without Xcode).
// SwiftPM's helper is signed by Apple with library validation: since macOS 26,
// it refuses to load the locally signed test bundle. This runner does the same thing
// (dlopen of the bundle, then the Swift Testing entry point), without that restriction.
import Darwin
import Foundation
import Testing

@main
struct TestRunner {
    static func main() async {
        var args = CommandLine.arguments.dropFirst()
        guard let bundle = args.popFirst() else {
            fputs("usage: TestRunner <test bundle> [swift-testing arguments]\n", stderr)
            exit(2)
        }
        // The tests expect English. Setting it here, before any test runs, means the
        // interface language starts as English and no test needs to change it while
        // other tests run in parallel (Localization.language is a global).
        UserDefaults.standard.setVolatileDomain(["appLanguage": "en"], forName: UserDefaults.argumentDomain)
        guard dlopen(bundle, RTLD_NOW) != nil else {
            fputs("Couldn't load \(bundle): \(String(cString: dlerror()))\n", stderr)
            exit(1)
        }
        exit(await Testing.__swiftPMEntryPoint(passing: nil))
    }
}

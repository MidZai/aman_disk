// Lanceur de tests pour les Command Line Tools seuls (sans Xcode).
// L'assistant de SwiftPM est signé par Apple avec la validation des bibliothèques : depuis macOS 26,
// il refuse de charger le paquet de tests signé localement. Ce lanceur fait la même chose
// (dlopen du paquet, puis point d'entrée de Swift Testing), sans cette restriction.
import Darwin
import Testing

@main
struct TestRunner {
    static func main() async {
        var args = CommandLine.arguments.dropFirst()
        guard let bundle = args.popFirst() else {
            fputs("usage: TestRunner <paquet de tests> [arguments de swift-testing]\n", stderr)
            exit(2)
        }
        guard dlopen(bundle, RTLD_NOW) != nil else {
            fputs("Impossible de charger \(bundle) : \(String(cString: dlerror()))\n", stderr)
            exit(1)
        }
        exit(await Testing.__swiftPMEntryPoint(passing: nil))
    }
}

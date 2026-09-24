import Foundation

public enum AppInfo {
    public static let name = "Aman Disk"
    /// Lue dans le bundle ; valeur de repli pour `swift run`.
    public static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.9.1"
    /// Identique à `CFBundleIdentifier` (build_app.sh) : sert de nom de dossier dans Application Support,
    /// y compris sous `swift run` où le bundle n'a pas d'identifiant.
    public static let bundleIdentifier = "io.github.aman-disk.AmanDisk"
    public static let repositoryURL = URL(string: "https://github.com/MidZai/aman_disk")!
    /// Ouverte dans le navigateur : l'app ne vérifie jamais elle-même les mises à jour.
    public static let releasesURL = repositoryURL.appendingPathComponent("releases")
    public static let supportURL = URL(string: "https://ko-fi.com/midzai")!
}

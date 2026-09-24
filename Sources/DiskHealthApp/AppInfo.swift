import Foundation

public enum AppInfo {
    public static let name = "Aman Disk"
    /// Read from the bundle; fallback value for `swift run`.
    public static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.9.2"
    /// Same as `CFBundleIdentifier` (build_app.sh): used as the folder name in Application Support,
    /// including under `swift run`, where the bundle has no identifier.
    public static let bundleIdentifier = "io.github.aman-disk.AmanDisk"
    public static let repositoryURL = URL(string: "https://github.com/MidZai/aman_disk")!
    /// Opened in the browser: the app itself never checks for updates.
    public static let releasesURL = repositoryURL.appendingPathComponent("releases")
    public static let supportURL = URL(string: "https://ko-fi.com/midzai")!
}

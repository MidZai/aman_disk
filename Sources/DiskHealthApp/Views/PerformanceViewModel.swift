import SwiftUI
import DiskHealthCore
import BenchmarkCore

enum BenchUnit: String {
    case mbps, iops
}

/// Settings and history of the Performance tab for one drive. The test itself is owned
/// by `BenchmarkController` (in AppManager) and outlives the view.
@MainActor
final class PerformanceViewModel: ObservableObject {
    static let sizes: [UInt64] = [1 << 30, 4 << 30, 16 << 30]

    @Published var selectedTargetId: String = ""
    @Published private(set) var targets: [BenchTarget] = []
    @Published private(set) var isResolvingTargets = true
    @Published var selectedProfile: BenchProfile = .standard
    @Published var selectedSize: UInt64 = 1 << 30
    @Published var selectedUnit: BenchUnit = .mbps
    @Published var showConfirm = false
    @Published private(set) var history: [BenchmarkResult] = []
    /// History result picked by the user; nil = latest result.
    @Published var viewedResult: BenchmarkResult?

    let disk: RealDisk
    private unowned let appManager: AppManager
    private var resolveTask: Task<Void, Never>?

    init(disk: RealDisk, appManager: AppManager) {
        self.disk = disk
        self.appManager = appManager
    }

    var selectedTarget: BenchTarget? { targets.first { $0.id == selectedTargetId } }
    var canRun: Bool { selectedTarget != nil && selectedTarget?.rejectionReason == nil }

    var estimatedMaxWritten: UInt64 {
        BenchMath.maxBytesWritten(fileSize: selectedSize, profile: selectedProfile)
    }

    var estimatedDurationText: String {
        let seconds = BenchMath.estimatedMaxDuration(fileSize: selectedSize, profile: selectedProfile)
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes <= 1 ? L("about 1 min", "environ 1 min") : L("about \(minutes) min", "environ \(minutes) min")
    }

    func onAppear() {
        resolveTargets()
        Task { await loadHistory() }
    }

    /// Off the main thread: the check writes a small file on each volume.
    func resolveTargets() {
        resolveTask?.cancel()
        isResolvingTargets = true
        let volumes = appManager.volumes(on: disk)
            // “/” (sealed system volume) and “/System/Volumes/Data” share the same
            // test folder: only the second is offered if both are present.
            .sorted { $0.mountPoint.count > $1.mountPoint.count }
        let physical = appManager.disks.map(\.physical)
        let size = selectedSize
        resolveTask = Task {
            let resolved = await Task.detached(priority: .userInitiated) {
                BenchTargetResolver.resolveTargets(volumes: volumes, disks: physical, fileSize: size)
            }.value
            guard !Task.isCancelled else { return }
            var seenDirectories = Set<String>()
            targets = resolved
                .filter { seenDirectories.insert($0.testDirectoryURL.path).inserted }
                .sorted { $0.volume.name < $1.volume.name }
            if let requested = appManager.requestedVolumeToTest, targets.contains(where: { $0.id == requested }) {
                selectedTargetId = requested
                appManager.requestedVolumeToTest = nil
            } else if selectedTarget == nil || selectedTarget?.rejectionReason != nil {
                selectedTargetId = (targets.first { $0.rejectionReason == nil } ?? targets.first)?.id ?? ""
            }
            isResolvingTargets = false
        }
    }

    func loadHistory() async {
        history = await BenchmarkHistoryManager.shared.loadResults(for: disk)
    }

    func start() {
        guard let target = selectedTarget, target.rejectionReason == nil else { return }
        viewedResult = nil
        appManager.benchmark.start(target: target, profile: selectedProfile, fileSize: selectedSize, disk: disk)
    }
}

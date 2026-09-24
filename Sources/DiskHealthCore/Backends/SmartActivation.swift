import Foundation

/// Accès à un disque ATA pour l'activation de S.M.A.R.T. (simulé dans les tests).
public protocol ATASmartDevice {
    func read(bsdName: String) throws -> DiskHealthSnapshot
    /// Numéro de série lu dans Identify, disponible même quand S.M.A.R.T. est désactivé.
    func serialNumber(bsdName: String) -> String?
    func enableSmart(bsdName: String) throws
}

public struct IOKitATADevice: ATASmartDevice {
    public init() {}

    public func read(bsdName: String) throws -> DiskHealthSnapshot {
        try ATABackend.read(bsdName: bsdName)
    }

    public func serialNumber(bsdName: String) -> String? {
        guard let identify = try? ATAReader.readIdentify(bsdName: bsdName) else { return nil }
        let serial = ATASmartParser.parseString(data: identify, range: 20..<40)
        return serial.isEmpty ? nil : serial
    }

    public func enableSmart(bsdName: String) throws {
        try ATAReader.enableSmart(bsdName: bsdName)
    }
}

/// Disques pour lesquels Aman a déjà tenté l'activation, par numéro de série, avec le résultat
/// (0 : réussie, sinon le code d'erreur). Survit aux relancements : une seule tentative automatique.
public protocol SmartActivationMemory: AnyObject {
    func attempt(for serial: String) -> Int32?
    func record(_ code: Int32, for serial: String)
}

public final class UserDefaultsActivationMemory: SmartActivationMemory, @unchecked Sendable {
    public static let defaultsKey = "smartActivationAttempts"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func attempt(for serial: String) -> Int32? {
        lock.lock(); defer { lock.unlock() }
        let attempts = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int] ?? [:]
        return attempts[serial].map { Int32(truncatingIfNeeded: $0) }
    }

    public func record(_ code: Int32, for serial: String) {
        lock.lock(); defer { lock.unlock() }
        var attempts = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int] ?? [:]
        attempts[serial] = Int(code)
        defaults.set(attempts, forKey: Self.defaultsKey)
    }
}

public enum SmartActivationResult: Equatable {
    /// S.M.A.R.T. était déjà actif.
    case read(DiskHealthSnapshot)
    /// Aman vient de l'activer, puis a relu le disque.
    case enabled(DiskHealthSnapshot)
    /// Désactivé, sans tentative : réglage coupé, ou activation déjà réussie une fois
    /// (quelqu'un l'a désactivé depuis ; on ne la refait pas d'office).
    case disabled
    /// Activation refusée par le disque ou le pilote, maintenant ou lors d'un lancement précédent.
    case enableFailed(code: Int32)
}

/// Lecture d'un disque ATA avec activation de S.M.A.R.T. s'il est désactivé :
/// une seule tentative automatique par disque, jamais de nouvelle tentative sans l'utilisateur.
public struct SmartActivator {
    private let device: ATASmartDevice
    private let memory: SmartActivationMemory

    public init(device: ATASmartDevice = IOKitATADevice(), memory: SmartActivationMemory) {
        self.device = device
        self.memory = memory
    }

    public func read(bsdName: String, autoEnable: Bool) throws -> SmartActivationResult {
        do {
            return .read(try device.read(bsdName: bsdName))
        } catch ATAReadError.smartDisabled {
            let serial = memoryKey(bsdName: bsdName)
            if let previous = memory.attempt(for: serial) {
                return previous == 0 ? .disabled : .enableFailed(code: previous)
            }
            guard autoEnable else { return .disabled }
            return try enable(bsdName: bsdName, serial: serial)
        }
    }

    /// Activation demandée par l'utilisateur (bouton « Activer » ou « Réessayer »).
    public func enable(bsdName: String) throws -> SmartActivationResult {
        try enable(bsdName: bsdName, serial: memoryKey(bsdName: bsdName))
    }

    private func enable(bsdName: String, serial: String) throws -> SmartActivationResult {
        do {
            try device.enableSmart(bsdName: bsdName)
        } catch {
            let code = Self.code(of: error)
            memory.record(code, for: serial)
            return .enableFailed(code: code)
        }
        memory.record(0, for: serial)
        return .enabled(try device.read(bsdName: bsdName))
    }

    /// Sans numéro de série lisible, le nom BSD sert de repli.
    private func memoryKey(bsdName: String) -> String {
        device.serialNumber(bsdName: bsdName) ?? "bsd:\(bsdName)"
    }

    static func code(of error: Error) -> Int32 {
        switch error as? ATAReadError {
        case .invalidArguments: return -1
        case .diskNotFound: return -2
        case .mediaNotFound: return -3
        case .smartServiceNotFound: return -4
        case .pluginCreationFailed: return -5
        case .smartDisabled: return -6
        case .ioError(let code), .unknown(let code): return code
        case .parseFailed, nil: return -7
        }
    }
}

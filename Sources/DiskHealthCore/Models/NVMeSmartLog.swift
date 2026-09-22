import Foundation

public struct NVMeSmartLog: Codable, Equatable {
    public let criticalWarning: UInt8
    public let compositeTemperatureKelvin: UInt16
    public let availableSpare: UInt8
    public let availableSpareThreshold: UInt8
    public let percentageUsed: UInt8
    public let dataUnitsRead: UInt64
    public let dataUnitsWritten: UInt64
    public let hostReadCommands: UInt64
    public let hostWriteCommands: UInt64
    public let controllerBusyTimeMinutes: UInt64
    public let powerCycles: UInt64
    public let powerOnHours: UInt64
    public let unsafeShutdowns: UInt64
    public let mediaErrors: UInt64
    public let errorLogEntries: UInt64
    
    public var temperatureCelsius: Int? {
        if compositeTemperatureKelvin == 0 { return nil }
        return Int(compositeTemperatureKelvin) - 273
    }
}

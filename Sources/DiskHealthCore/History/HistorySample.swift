import Foundation

public struct HistorySample: Codable, Hashable {
    public let date: Date
    public let temperatureC: Int?
    public let percentageUsed: UInt8
    public let dataUnitsWritten: UInt64
    public let dataUnitsRead: UInt64
    public let powerOnHours: UInt64
    public let mediaErrors: UInt64
    public let availableSpare: UInt8
    
    public init(date: Date, temperatureC: Int?, percentageUsed: UInt8, dataUnitsWritten: UInt64, dataUnitsRead: UInt64, powerOnHours: UInt64, mediaErrors: UInt64, availableSpare: UInt8) {
        self.date = date
        self.temperatureC = temperatureC
        self.percentageUsed = percentageUsed
        self.dataUnitsWritten = dataUnitsWritten
        self.dataUnitsRead = dataUnitsRead
        self.powerOnHours = powerOnHours
        self.mediaErrors = mediaErrors
        self.availableSpare = availableSpare
    }
}

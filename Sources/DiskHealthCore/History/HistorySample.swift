import Foundation

public struct HistorySample: Codable, Hashable {
    public let date: Date
    public let temperatureC: Int?
    public let percentageUsed: Int?
    public let dataUnitsWritten: UInt64?
    public let dataUnitsRead: UInt64?
    public let powerOnHours: UInt64?
    public let mediaErrors: UInt64?
    public let availableSpare: Int?
    
    public init(date: Date, temperatureC: Int?, percentageUsed: Int?, dataUnitsWritten: UInt64?, dataUnitsRead: UInt64?, powerOnHours: UInt64?, mediaErrors: UInt64?, availableSpare: Int?) {
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

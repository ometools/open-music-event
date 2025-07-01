import Foundation
import FileTree
import CoreModels

// INPUT

//// OUTPUT
//struct TimelessStagelessPerformance: Equatable, Sendable {
//    var startTime: ScheduleTime
//    var endTime: ScheduleTime?
//    var customTitle: String?
//    var artistNames: OrderedSet<String>
//}
//
//extension ScheduleConversion {
//    struct PerformanceConversion: Conversion {
//        typealias Input = Performance.YamlRepresentation
//        typealias Output = TimelessStagelessPerformance
//        typealias PerformanceError = Validation.ScheduleError.StageDayScheduleError.PerformanceError
//        func apply(_ input: Performance.YamlRepresentation) throws -> TimelessStagelessPerformance {
//            let startTime = try ScheduleTimeConversion().apply(input.time)
//            let endTime = try input.endTime.map(ScheduleTimeConversion().apply(_:))
//            let artistNames = try getArtists(artist: input.artist, artists: input.artists)
//
//            guard !(input.title == nil && artistNames.isEmpty)
//            else { throw PerformanceError.noArtistsOrTitle }
//
//            return TimelessStagelessPerformance(
//                startTime: startTime,
//                endTime: endTime,
//                customTitle: input.title,
//                artistNames: artistNames
//            )
//        }
//
//        func unapply(_ output: TimelessStagelessPerformance) throws -> Performance.YamlRepresentation {
//            return Performance.YamlRepresentation(
//                title: output.customTitle,
//                artist: output.artistNames.count == 1 ? output.artistNames.first : nil,
//                artists: output.artistNames.count > 1 ? Array(output.artistNames) : nil,
//                time: try ScheduleTimeConversion().unapply(output.startTime),
//                endTime: try output.endTime.map(ScheduleTimeConversion().unapply(_:))
//            )
//        }
//

//    }
//}

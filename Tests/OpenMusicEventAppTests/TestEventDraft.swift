import Foundation
import OpenMusicEventLexicon

typealias TestOMERecord = OpenMusicEventLexicon.OpenMusicEvent

func testEventDraft(
    id: TestOMERecord.Event.ID,
    name: String,
    startDate: LocalDate? = nil,
    endDate: LocalDate? = nil,
    timeZone: TimeZone = .current
) -> TestOMERecord.Event.Draft {
    TestOMERecord.Event.Draft(
        id: id,
        name: name,
        description: nil,
        startDate: startDate,
        endDate: endDate,
        status: nil,
        mode: nil,
        locations: nil,
        uris: nil,
        timeZone: timeZone,
        images: nil,
        contactNumbers: nil,
        categoryConfigs: nil,
        policies: nil,
        reportingLinks: nil
    )
}

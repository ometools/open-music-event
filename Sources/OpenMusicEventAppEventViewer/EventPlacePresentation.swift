import OpenMusicEventLexicon
import Foundation

extension EventPlace {
    var kindLabel: String {
        switch kind {
        case .some(.known(.stage)): "Stage"
        case .some(.known(.entrance)): "Entrance"
        case .some(.known(.camping)): "Camping"
        case .some(.known(.info)): "Information"
        case .some(.unknown), .none: "Place"
        }
    }

    var hasDisplayDetails: Bool {
        description != nil || stageUse?.category != nil || stageUse?.sortIndex != nil
    }
}

func eventPlaceDivisionTitle(_ value: String) -> String {
    value.split { $0 == "-" || $0 == "_" || $0 == " " }
        .map { $0.capitalized }
        .joined(separator: " ")
}

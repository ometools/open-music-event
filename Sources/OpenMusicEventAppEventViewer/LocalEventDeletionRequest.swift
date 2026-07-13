import ComposableArchitecture2
import OpenMusicEventDatabase

public struct LocalEventDeletionRequested: FeatureEventKey {
    public init() {}
    public typealias Value = OMERecord.Event.ID
}

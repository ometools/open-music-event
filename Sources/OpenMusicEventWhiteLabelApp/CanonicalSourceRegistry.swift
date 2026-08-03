import Dependencies
import OpenMusicEventApp

public enum OpenMusicEvent {
    public enum WhiteLabel {
        /// White-label applications use the same browse, authentication, authoring, and Workspace
        /// stack as the generic OME application. Branding does not install source dependencies.
        public static func prepareDependencies(
            _ dependencies: inout DependencyValues
        ) throws {
            try OME.prepareDependencies(&dependencies)
        }
    }
}

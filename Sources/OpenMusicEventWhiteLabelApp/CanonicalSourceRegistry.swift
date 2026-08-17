import Dependencies
import OpenMusicEventApp
import SQLiteData

public enum OpenMusicEvent {
    public enum WhiteLabel {
        /// White-label applications use the same browse, authentication, authoring, and Workspace
        /// stack as the generic OME application. Branding does not install source dependencies.
        public static func prepareDependencies(
            _ dependencies: inout DependencyValues
        ) throws {
            try OME.preparePersistedServiceEnvironmentDependencies(&dependencies)
        }

        /// Installs the ordinary OME application dependencies around an existing application
        /// database. This is the test and embedding seam for preserving database identity; it does
        /// not change the white-label application's source or authorization behavior.
        public static func prepareDependencies(
            _ dependencies: inout DependencyValues,
            database: any DatabaseWriter
        ) {
            OME.prepareDependencies(&dependencies, database: database)
        }
    }
}

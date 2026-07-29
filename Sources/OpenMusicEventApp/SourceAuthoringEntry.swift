import Dependencies
import OpenMusicEventAuthentication
import OpenMusicEventSourceEditing
import SQLiteData

extension OpenMusicEventSourceEditing.AuthoringPolicyClient {
    static var openMusicEvent: Self {
        Self { workspaceID in
            @Dependency(\.defaultDatabase) var database

            let workspace = try await database.read { db in
                try EditingWorkspaceRecord
                    .where { $0.id.eq(workspaceID) }
                    .fetchOne(db)
            }
            guard let workspace else {
                throw WorkspacePreparationError.workspaceNotFound(workspaceID)
            }

            switch workspace.kind {
            case .local:
                return [.editContent]

            case .team:
                @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
                try await authorizationBroker.authorize(
                    OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement
                )
                return [.editContent]
            }
        }
    }
}

import OpenMusicEventSourceEditing
import SQLiteData

/// Durable proof that the user explicitly exited authoring and authorized the local workspace
/// checkout to be rebuilt from its canonical branch on the next authoring entry.
///
/// This marker is intentionally separate from the presence or absence of an installation record:
/// a missing installation can also mean that first-time preparation was interrupted, which is not
/// permission to delete local files.
@Table("sourceWorkspaceCanonicalResets")
struct SourceWorkspaceCanonicalResetRecord: Equatable, Sendable, Identifiable {
    var id: SourceWorkspace.ID
}

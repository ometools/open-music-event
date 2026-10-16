import OpenMusicEventLexicon
import SQLiteData

public enum ContributorArtworkQuery {
    public static func image(media: QueryFragment) -> some QueryExpression<OME.Image.JSONRepresentation?> {
        #sql(
            """
            (SELECT value FROM json_each(\(media))
             WHERE json_extract(value, '$.$type') = 'events.openmusic.defs#image'
               AND json_extract(value, '$.role.$type') IN
                   ('events.openmusic.defs#photoImage', 'events.openmusic.defs#logoImage')
               AND json_extract(value, '$.source.$type') IN
                   ('events.openmusic.defs#imageURL', 'events.openmusic.defs#imageBlob')
             ORDER BY CASE json_extract(value, '$.role.$type')
                          WHEN 'events.openmusic.defs#photoImage' THEN 0 ELSE 1 END, CAST(key AS INTEGER)
             LIMIT 1)
            """,
            as: OME.Image.JSONRepresentation?.self
        )
    }
}

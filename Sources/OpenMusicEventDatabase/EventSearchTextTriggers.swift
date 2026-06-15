import SQLiteData

public enum EventSearchTextTriggers {
    public static func install(in db: Database) throws {
        try EventSearchDocument
            .createTemporaryTrigger(
                "eventSearchDocuments_eventSearchText_insert",
                ifNotExists: true,
                after: .insert { new in
                    EventSearchText.insert {
                        ($0.rowid, $0.title, $0.keywords, $0.subtitle, $0.body)
                    } values: {
                        (
                            new.id,
                            new.title,
                            new.keywords,
                            new.subtitle ?? "",
                            new.body ?? ""
                        )
                    }
                }
            )
            .execute(db)

        try EventSearchDocument
            .createTemporaryTrigger(
                "eventSearchDocuments_eventSearchText_update",
                ifNotExists: true,
                after: .update { _, new in
                    EventSearchText
                        .find(new.id)
                        .update {
                            $0.title = new.title
                            $0.keywords = new.keywords
                            $0.subtitle = new.subtitle ?? ""
                            $0.body = new.body ?? ""
                        }
                }
            )
            .execute(db)

        try EventSearchDocument
            .createTemporaryTrigger(
                "eventSearchDocuments_eventSearchText_delete",
                ifNotExists: true,
                after: .delete { old in
                    EventSearchText
                        .find(old.id)
                        .delete()
                }
            )
            .execute(db)
    }
}

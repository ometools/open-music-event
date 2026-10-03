# Canonical record form coverage — iOS Phase 1

This is the current app-side coverage map for the public records. A List, Detail, or Form name describes an actual screen or feature; a record does not gain an empty Detail screen solely to complete a naming triplet. The old OME domain models remain available to source import, while active app viewing and local editing use the canonical records. PDS publication and Android validation are later phases.

| Record | Browsing and detail | Editing and field reachability |
| --- | --- | --- |
| `Event` | Event browser/search and `EventDetail` | `EventForm`: name, description, start/end precision, time zone, status, mode, RSVP expectation, links, and media. `LocationViewer`/`EditLocation`: ordered locations, all locator variants, and location links. `ProgramList`, `ScheduleList`, `SocialCategoryList`, and `EditSiteMap`: ordered record references and embedded map styles/default. `PostersViewer` remains the focused poster editor. |
| `EventPlace` | `EventPlaceList` and `EventPlaceDetail` | `EventPlaceForm`: name, description, kind, locators, links, media, and stage use. Stage color/category, icon/short label, persistent Stage link, and lineup are available in the ordinary form. Stage ordering is available in the list. |
| `Stage` | `StageList` and `StageDetail` | `StageForm`: persistent name, description, links, logo/hero/poster images, external media, and record media. |
| `Contributor` | `ContributorList` and `ContributorDetail` | `ContributorForm`: name, bio, linked subject account, ordered roles, links, photos/logos, external media, and record media. The optional pinned `source` strong reference is provenance, not a free-text profile field; changing the linked subject clears it. No UI creates a new pinned source reference yet. |
| `Program` | `ProgramList` opens the editor directly | `ProgramForm`: title, description, icon, and ordered EventPlace lanes. The Event owns program tab order; `ProgramList` exposes move/delete menus. |
| `Schedule` | `ScheduleList` opens the editor directly | `ScheduleForm`: festival date and optional title. The Event owns day order; `ScheduleList` exposes reorder/delete actions. |
| `ProgramItem` | Schedule list/detail and `ProgramItemDetail` | `ProgramItemForm`: title, description, program, optional schedule/place/time, ordered credits with billing and role, and media. Untimed and unplaced items remain editable. |
| `Social.Category` | `SocialCategoryList` and `SocialCategoryDetail` | `SocialCategoryForm`: name, description, media, default subscription state, and required-notification policy. Post pin/unpin/reorder actions live in the category detail/list. The Event owns category order. |
| `Social.Post` | `SocialPostList` and `SocialPostDetail` | `SocialPostForm`: title, Markdown text, category, delivery, image/link/record embed, and ordered syndication references. Text facets are preserved on an unchanged body but are not authored by a dedicated facet UI. Created/updated timestamps are operation-managed. |

Array rows use their owning form or list's Edit, Move, and Delete/Remove actions. Image metadata, including role, alt text, appearance, and focus, is edited through `ImageInfo`; map style image metadata uses the same editor. Record identity, CID, `createdAt`, and reference ownership are allocated or checked by record operations rather than editable text fields.

Native tests cover canonical database create/update/delete and the Event and Contributor media row save/reopen paths. The owner iOS Maestro lane exercises Event, EventPlace, Stage, ProgramItem credit, SocialPost, and Contributor media flows with five screenshot comparisons. This is local authoring proof: it does not claim PDS write/readback, anonymous reader convergence, Android parity, or complete rich-text facet authoring.

The generated-schema field inventory in `LexiconFieldCoverage.csv` remains the exhaustive publication checklist. Its older `unverified` entries must not be read as a current failure of the screens listed above or as publication proof; the final field-by-field PDS readback gate still needs to update that inventory.

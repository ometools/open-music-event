# OME AppView domain rule

The OME AppView persists domain data using OME lexicon types and semantics.
Records from other lexicons are projected into that domain model. Source identity
and provenance remain explicit local metadata; raw ingestion records and
rebuildable query indexes remain supporting infrastructure. Views may select or
omit information, but must not invent meaning or erase semantic distinctions.

- Use the existing lexicon-backed domain types, not a second normalized event model.
- Preserve day versus instant, event locations versus internal places, link roles,
  media roles/rendering, ordered arrays, unknown unions, and absent information.
- Imported rows retain their source URI and CID. They are not published OME records.
- Keep provenance on the domain row as non-lexicon metadata. Do not manufacture
  OME identities or automatically merge records from different sources.
- Native record APIs return original indexed payloads with their source CIDs;
  they must exclude externally projected rows. Publication validation stays strict.
- Enrichment is explicitly derived, not authored content. No fabricated time zones,
  organizer relationships, location names, or event boundaries.
- Search, temporal, spatial, and clustering indexes are rebuildable derivatives.
  Compact responses must retain the semantics of every field they expose.
- Rebuild external projections from raw indexed records, not previous lossy views.
  Preserve raw records and report adapter failures rather than silently dropping them.
- Prove upgrades preserve existing data before migrating the local sandbox.
  Never reset an installed database or republish records as a migration shortcut.

This rule governs AppView storage and projections, not every database in OME.

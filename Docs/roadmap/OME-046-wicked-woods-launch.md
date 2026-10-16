---
id: OME-046
type: roadmap-card
area: release
kind: milestone
priority: high
created: "2026-06-09"
---

# Wicked Woods Launch

## Summary

Track the release milestone for launching the Wicked Woods white-label app.

## Why

The Wicked Woods launch depends on app packaging, organizer-owned operational setup, real event content validation, tester rollout, and store-ready release assets. Keeping this as a blocked milestone makes the remaining launch dependencies visible without turning every prerequisite into release-status noise.


```base
filters:
  and:
    - type == "roadmap-card"
    - launch == "wicked-woods"
views:
  - type: table
    name: wicked-woods-launch
    groupBy:
      property: file.tags
      direction: ASC
    order:
      - id
      - file.name
      - tags
      - area
      - kind
      - priority
    sort:
      - property: tags
        direction: ASC
      - property: id
        direction: ASC
    columnSize:
      note.id: 111
      file.name: 367
```

## Open Questions

- Which Wicked Woods account and store ownership tasks must be done before tester rollout versus public release?

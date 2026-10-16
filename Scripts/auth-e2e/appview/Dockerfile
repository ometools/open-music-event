# Official Swift 6.3.3 on Ubuntu 24.04, pinned for both supported architectures.
FROM swift:6.3.3-noble@sha256:8de8ea332a61e961ead4ef41029c2552b18e1a70dd5942d25ecf7d8de2eec5b5 AS base
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-dev curl && \
    rm -rf /var/lib/apt/lists/*

FROM base AS build
WORKDIR /src
ENV OME_APPVIEW=1
ARG SWIFT_BUILD_JOBS=2
COPY --from=ome-atmosphere . /Users/woody/Developer/swift-packages/swift-composable-atmosphere-reorg-auth
COPY --from=ome-userinput . /Users/woody/Developer/ometools/worktrees/composable-atmosphere-userinput-reorg
COPY --from=ome-workspace . /Users/woody/Developer/ometools/worktrees/swift-composable-workspace-atmosphere-reorg
COPY --from=ome-constellation . /Users/woody/Developer/ometools/worktrees/composable-atmosphere-constellation-reorg
COPY --from=ome-tangled . /Users/woody/Developer/ometools/worktrees/composable-atmosphere-tangled-reorg
COPY --from=ome-calendar . /Users/woody/Developer/ometools/worktrees/composable-calendar-events-reorg
COPY --from=ome-notifications . /Users/woody/Developer/ometools/worktrees/swift-composable-notifications-atmosphere-reorg
COPY --from=ome-forms . /Users/woody/Developer/ometools/worktrees/swift-composable-forms-atmosphere-reorg
COPY --from=ome-hero-images . /Users/woody/Developer/ometools/swift-hero-image-list
COPY Package.swift Package.resolved ./
COPY Sources ./Sources
COPY Tests ./Tests
RUN --mount=type=secret,id=github_netrc,target=/root/.netrc,required=true \
    --mount=type=cache,id=ome-appview-v3,target=/src/.build swift build --jobs "$SWIFT_BUILD_JOBS" -c release --product OpenMusicEventAppView && \
    mkdir /output && cp .build/release/OpenMusicEventAppView /output/ && \
    find .build/release/ -maxdepth 1 -name '*.resources' -exec cp -R {} /output/ \;

FROM base
WORKDIR /app
COPY --from=build /output/ /app/
ENV OME_APPVIEW_HOST=0.0.0.0 OME_APPVIEW_PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/OpenMusicEventAppView"]

# Official Swift 6.3.3 on Ubuntu 24.04, pinned for both supported architectures.
FROM swift:6.3.3-noble@sha256:8de8ea332a61e961ead4ef41029c2552b18e1a70dd5942d25ecf7d8de2eec5b5 AS base
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-dev curl && \
    rm -rf /var/lib/apt/lists/*

FROM base AS build
WORKDIR /src
ENV OME_APPVIEW=1
ARG SWIFT_BUILD_JOBS=2
COPY Package.swift Package.resolved ./
COPY Sources ./Sources
COPY Tests ./Tests
RUN --mount=type=secret,id=github_netrc,target=/root/.netrc,required=true \
    --mount=type=cache,target=/src/.build swift build --jobs "$SWIFT_BUILD_JOBS" -c release --product OpenMusicEventAppView && \
    mkdir /output && cp .build/release/OpenMusicEventAppView /output/ && \
    find .build/release/ -maxdepth 1 -name '*.resources' -exec cp -R {} /output/ \;

FROM base
WORKDIR /app
COPY --from=build /output/ /app/
ENV OME_APPVIEW_HOST=0.0.0.0 OME_APPVIEW_PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/OpenMusicEventAppView"]

FROM swift:6.3.3-noble@sha256:8de8ea332a61e961ead4ef41029c2552b18e1a70dd5942d25ecf7d8de2eec5b5 AS build
RUN apt-get update && apt-get install -y --no-install-recommends libgit2-dev libsqlite3-dev pkg-config python3 curl && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY Package.swift Package.resolved ./
COPY Sources ./Sources
COPY Tests ./Tests
COPY Lexicons ./Lexicons
COPY Scripts/web-release ./Scripts/web-release
ARG OME_RELEASE_REVISION
ENV OME_RELEASE_REVISION=$OME_RELEASE_REVISION
ENV OME_TOOLCHAIN_IMAGE=swift:6.3.3-noble@sha256:8de8ea332a61e961ead4ef41029c2552b18e1a70dd5942d25ecf7d8de2eec5b5
RUN --mount=type=secret,id=github_netrc,target=/root/.netrc,required=true bash Scripts/web-release/build.sh

FROM scratch AS artifact
COPY --from=build /output/passed/ /

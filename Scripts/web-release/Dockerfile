FROM swift:6.3.3-noble@sha256:8de8ea332a61e961ead4ef41029c2552b18e1a70dd5942d25ecf7d8de2eec5b5 AS toolchain
RUN apt-get update && apt-get install -y --no-install-recommends libgit2-dev libsqlite3-dev pkg-config python3 curl time && rm -rf /var/lib/apt/lists/*
ENV OME_TOOLCHAIN_IMAGE=swift:6.3.3-noble@sha256:8de8ea332a61e961ead4ef41029c2552b18e1a70dd5942d25ecf7d8de2eec5b5
WORKDIR /src

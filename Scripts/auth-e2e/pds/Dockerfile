FROM ghcr.io/bluesky-social/pds@sha256:05e164855fa1a3cf251c002210c46f8c86e7ae27bddc7a96045da25483840826
COPY shorten-token.cjs /tmp/shorten-token.cjs
RUN node /tmp/shorten-token.cjs && rm /tmp/shorten-token.cjs

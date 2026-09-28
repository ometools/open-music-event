FROM ghcr.io/bluesky-social/pds@sha256:05e164855fa1a3cf251c002210c46f8c86e7ae27bddc7a96045da25483840826
COPY shorten-token.cjs /tmp/shorten-token.cjs
RUN node /tmp/shorten-token.cjs && rm /tmp/shorten-token.cjs
COPY allow-private-client.cjs /tmp/allow-private-client.cjs
COPY validate-private-client.cjs /usr/local/lib/validate-private-client.cjs
RUN node /tmp/allow-private-client.cjs && rm /tmp/allow-private-client.cjs && \
    node /usr/local/lib/validate-private-client.cjs

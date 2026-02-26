ARG FRAISEQL_V2=false

FROM ghcr.io/fraiseql/fraiseql:latest AS builder
ARG FRAISEQL_V2
WORKDIR /build
COPY schema.py fraiseql.toml ./
RUN if [ "$FRAISEQL_V2" = "true" ]; then \
      python schema.py && fraiseql compile; \
    else touch schema.compiled.json; fi

FROM ghcr.io/fraiseql/fraiseql:latest AS runtime
WORKDIR /app
COPY fraiseql.toml ./
COPY --from=builder /build/schema.compiled.json ./schema.compiled.json
ENV DATABASE_URL=""
ENV NATS_URL=""
EXPOSE 8080
CMD ["fraiseql", "run"]

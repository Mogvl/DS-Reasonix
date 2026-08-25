# syntax=docker/dockerfile:1

###############################################################################
# Stage 1: build the reasonix server binary
# CGO_ENABLED=0 → fully static binary, runs on alpine, amd64 + arm64
###############################################################################
FROM golang:1.26-alpine AS builder

# git + ca-certificates for module download; GOPROXY is overridable so
# mainland-China users can point at goproxy.cn via a compose build arg.
ARG GOPROXY=https://proxy.golang.org,direct
ENV GOPROXY=${GOPROXY} \
    CGO_ENABLED=0 \
    GOOS=linux

RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /src

# Cache module downloads first (layer stays valid while sources change)
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Version metadata is best-effort; the container image tag carries the real version.
ARG VERSION=container
ARG GIT_COMMIT=unknown
ARG BUILD_TIME_UTC=unknown

RUN go build \
    -trimpath \
    -ldflags "-s -w \
      -X main.version=${VERSION} \
      -X main.gitCommit=${GIT_COMMIT} \
      -X main.buildTimeUTC=${BUILD_TIME_UTC}" \
    -o /out/reasonix ./cmd/reasonix

###############################################################################
# Stage 2: minimal runtime image
###############################################################################
FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata curl su-exec \
    && addgroup -g 1000 -S reasonix \
    && adduser -u 1000 -G reasonix -S -h /home/reasonix reasonix \
    && mkdir -p /workspace /config \
    && chown 1000:1000 /workspace

# Runtime data lives under REASONIX_HOME (sessions, config, credentials, memory)
ENV REASONIX_HOME=/home/reasonix \
    REASONIX_STATE_HOME=/home/reasonix \
    TZ=Asia/Shanghai

WORKDIR /workspace

COPY --from=builder /out/reasonix /usr/local/bin/reasonix
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# The entrypoint prepares data dirs / seeds config as root, then drops to uid
# 1000 via su-exec before running reasonix serve.
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 7552

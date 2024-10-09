ARG DEV_IMAGE=registry.redhat.io/ubi8/go-toolset:1.21

FROM registry.redhat.io/ubi9/go-toolset@sha256:fd41c001abc243076cc28b63c409ae6d9cbcad401c8124fb67d20fe57a2aa63a AS build
# https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope
# don't provide "default" values (e.g. 'ARG TARGETARCH=amd64') for non-buildx environments,
# see https://github.com/docker/buildx/issues/510
ARG TARGETOS=linux
ARG TARGETARCH=amd64

LABEL image="build"

# Copy the go sources
COPY main.go main.go
COPY apis/ apis/
COPY controllers/ controllers/
COPY generated/ generated/
COPY pkg/ pkg/
COPY version /etc/modelmesh-version

USER root

COPY go.mod go.mod
COPY go.sum go.sum
RUN go mod download

# Build using native go compiler from BUILDPLATFORM but compiled output for TARGETPLATFORM
RUN GOOS=${TARGETOS:-linux} \
    GOARCH=${TARGETARCH:-amd64} \
    CGO_ENABLED=0 \
    GO111MODULE=on \
    go build -a -o /workspace/manager main.go

###############################################################################
# Stage 2: Copy build assets to create the smallest final runtime image
###############################################################################
FROM registry.redhat.io/ubi8/ubi-minimal:latest AS runtime

ARG USER=2000
ARG IMAGE_VERSION
ARG COMMIT_SHA

LABEL name="modelmesh-serving-controller" \
      version="${IMAGE_VERSION}" \
      release="${COMMIT_SHA}" \
      summary="Kubernetes controller for ModelMesh Serving components" \
      description="Manages lifecycle of ModelMesh Serving Custom Resources and associated Kubernetes resources"
      
## Install additional packages
RUN microdnf install -y shadow-utils &&\
    microdnf clean all

USER ${USER}

WORKDIR /
COPY --from=0 /workspace/manager .

COPY config/internal config/internal

ENTRYPOINT ["/manager"]

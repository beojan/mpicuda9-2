#!/bin/bash
# Copyright (C) 2002-2026 CERN for the benefit of the ATLAS collaboration

# Build one of the MPI container images in this directory.
#
# Each image is tagged with a fixed name. Before the new image replaces the
# previous one, the old image is removed so the tag does not accumulate
# stale layers. The CUDA-aware OpenMPI build reads the host CUDA toolkit from
# CUDA_HOST_DIR (default /opt/cuda) and does not install CUDA in the image.

set -euo pipefail

cd "$(dirname "$0")"

CUDA_HOST_DIR=${CUDA_HOST_DIR:-/opt/cuda}

# The mpich + CUDA image takes its CUDA version from its base image tag.
# The tag uses major.minor only, matching the existing beojan/mpicuda13:13.4.
cuda_version=$(rg -or '$1' '^FROM nvidia/cuda:([0-9.]+)-' Dockerfile)
cuda_tag=${cuda_version%.*}

# Build the image described by a Dockerfile and tag it.
# Usage: build_image <Dockerfile> <tag> [extra docker buildx arguments...]
build_image() {
    local dockerfile=$1
    local tag=$2
    shift 2

    local old_id
    old_id=$(docker image inspect --format '{{.Id}}' "$tag" 2>/dev/null || true)

    # Host networking avoids "failed to create endpoint" errors from the default
    # bridge on this host during RUN steps.
    docker buildx build --network=host --load -f "$dockerfile" -t "$tag" "$@" .

    # Docker moves the tag to the new image, so the old image is now untagged.
    # Remove it, and only warn if it is still in use or has other tags.
    local new_id
    new_id=$(docker image inspect --format '{{.Id}}' "$tag")
    if [[ -n $old_id && $old_id != "$new_id" ]]; then
        docker image rm "$old_id" || echo "warning: could not remove old image $old_id" >&2
    fi
    echo "Built $tag ($new_id)"
}

build_mpich() {
    build_image Dockerfile-no-nv mpialma9-2:latest
}

build_ompi() {
    if [[ ! -f "$CUDA_HOST_DIR/include/cuda_runtime.h" ]]; then
        echo "error: CUDA headers not found under $CUDA_HOST_DIR" >&2
        echo "Set CUDA_HOST_DIR to the host CUDA toolkit directory." >&2
        exit 1
    fi
    build_image Dockerfile-ompi openmpialma9:latest \
        --build-context "cuda=$CUDA_HOST_DIR"
}

build_mpich_cuda() {
    # The previous image was built under the beojan/ prefix. Remove that tag
    # once the new image exists, so the new build replaces it.
    local legacy_tag=beojan/mpicuda13:$cuda_tag
    local legacy_id
    legacy_id=$(docker image inspect --format '{{.Id}}' "$legacy_tag" 2>/dev/null || true)

    build_image Dockerfile "mpicuda13:$cuda_tag"

    if [[ -n $legacy_id ]]; then
        docker image rm "$legacy_tag" >/dev/null
        echo "Removed previous image $legacy_tag"
    fi
}

echo "Choose a container to build:"
echo
echo "  1) mpich"
echo "     MPICH on the ATLAS AlmaLinux 9 base image, with no CUDA."
echo "     Use it for CPU-only MPI jobs. Tag: mpialma9-2:latest"
echo
echo "  2) ompi"
echo "     CUDA-aware OpenMPI 5 with ULFM fault tolerance, on the ATLAS"
echo "     AlmaLinux 9 base image. CUDA headers come from the host at"
echo "     $CUDA_HOST_DIR during the build, so CUDA is not installed in the image."
echo "     Tag: openmpialma9:latest"
echo
echo "  3) mpich + cuda"
echo "     MPICH built with CUDA support, on NVIDIA's Rocky 9 CUDA devel image"
echo "     (CUDA $cuda_version). Use it for GPU MPI jobs with MPICH."
echo "     Tag: mpicuda13:$cuda_tag (replaces beojan/mpicuda13:$cuda_tag)"
echo

PS3="Enter a number (1-3): "
select choice in "mpich" "ompi" "mpich + cuda"; do
    case $REPLY in
        1) build_mpich ;;
        2) build_ompi ;;
        3) build_mpich_cuda ;;
        *) echo "Invalid choice: $REPLY" >&2; continue ;;
    esac
    break
done

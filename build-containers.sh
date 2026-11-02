#!/bin/bash
# Copyright (C) 2002-2026 CERN for the benefit of the ATLAS collaboration

# Build one of the MPI container images. Each image has its own directory with a
# Dockerfile, and common/ holds the files they share. The build context is this
# directory, so Dockerfiles refer to files as common/<file> or <image>/<file>.
#
# Each image is tagged with a fixed name. Before the new image replaces the
# previous one, the old image is removed so the tag does not accumulate
# stale layers. The CUDA-aware OpenMPI build reads the host CUDA toolkit from
# CUDA_HOST_DIR and does not install CUDA in the image. The MPICH build does
# the same. When CUDA_HOST_DIR is
# not set, the script looks for the toolkit from CUDA_HOME, CUDA_PATH, nvcc on
# PATH, /usr/local/cuda and /opt/cuda.
#
# Usage: build-containers.sh [-h|--help] [mpich|ompi|mpich-cuda]
# Without an argument the script shows a menu.

set -euo pipefail

cd "$(dirname "$0")"
source common/ui.sh
trap ui_show_cursor EXIT

# Print the first directory that looks like a CUDA toolkit, or nothing.
find_cuda_dir() {
    local candidate nvcc_path
    local -a candidates=("${CUDA_HOME:-}" "${CUDA_PATH:-}")
    if nvcc_path=$(command -v nvcc 2>/dev/null); then
        candidates+=("$(dirname -- "$(dirname -- "$(readlink -f -- "$nvcc_path")")")")
    fi
    candidates+=(/usr/local/cuda /opt/cuda)
    for candidate in "${candidates[@]}"; do
        if [[ -n $candidate && -f $candidate/include/cuda_runtime.h ]]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
}

CUDA_HOST_DIR=${CUDA_HOST_DIR:-$(find_cuda_dir)}

# Network mode for RUN steps. Host networking avoids "failed to create
# endpoint" errors from the default bridge on some hosts. Set BUILD_NETWORK to
# default to use Docker's normal networking.
BUILD_NETWORK=${BUILD_NETWORK:-host}

# Print an error with an optional hint on the next line, then exit.
# Usage: die <message> [hint]
die() {
    printf '%serror:%s %s\n' "$UI_RED" "$UI_RESET" "$1" >&2
    if [[ -n ${2:-} ]]; then
        printf '%shint:%s  %s\n' "$UI_YELLOW" "$UI_RESET" "$2" >&2
    fi
    exit 1
}

usage() {
    cat <<EOF
${UI_BOLD}Usage:${UI_RESET} $(basename -- "$0") [-h|--help] [mpich|ompi|mpich-cuda]

Build one of the MPI container images with Docker. Without an argument, a
menu lets you choose. The new image replaces the one with the same tag.

${UI_BOLD}Images:${UI_RESET}
  mpich        CUDA-aware MPICH, on the ATLAS AlmaLinux 9 image
  ompi         CUDA-aware OpenMPI 5 with ULFM, on the ATLAS AlmaLinux 9 image
  mpich-cuda   MPICH with CUDA, on NVIDIA's Rocky 9 CUDA devel image

${UI_BOLD}Environment:${UI_RESET}
  CUDA_HOST_DIR  Host CUDA toolkit used by the mpich and ompi builds. It must contain
                 include/cuda_runtime.h. Default: the first of CUDA_HOME,
                 CUDA_PATH, the nvcc location, /usr/local/cuda and /opt/cuda
                 that has it.
  BUILD_NETWORK  Docker network mode for build steps. Default: host.
  NO_COLOR       Set to turn off colours.

The full build output goes to a log file. Its path is shown if the build fails.
After a build, convert the image for Apptainer with build-img.sh.
EOF
}

case ${1:-} in
    -h|--help) usage; exit 0 ;;
    mpich|ompi|mpich-cuda|"") ;;
    *) usage >&2; die "unknown argument: $1" ;;
esac
(($# <= 1)) || { usage >&2; die "expected at most one argument, got $#"; }

command -v docker >/dev/null ||
    die "docker is not on PATH." "This script builds with docker buildx."
docker buildx version >/dev/null 2>&1 ||
    die "docker buildx is not available." "Install the buildx plugin, or check that the Docker daemon is running."

# The mpich + CUDA image takes its CUDA version from its base image tag.
# The tag uses major.minor only, for example mpicuda13:13.4.
cuda_version=$(sed -nE 's/^FROM nvidia\/cuda:([0-9.]+)-.*/\1/p' mpich-cuda/Dockerfile | head -n 1)
[[ -n $cuda_version ]] || die "Could not read the CUDA version from mpich-cuda/Dockerfile."
cuda_tag=${cuda_version%.*}

# Read the plain-text output of docker buildx and print "<percent>|<label>".
# Every Dockerfile step is logged as "#N [stage-S i/n] INSTRUCTION". The
# Dockerfiles have two stages, and the second one is a single COPY step.
# Steps before the one in progress count as done.
buildx_progress() {
    awk '
    /^#[0-9]+ \[/ && match($0, /\[[^]]*[0-9]+\/[0-9]+\]/) {
        n = split(substr($0, RSTART + 1, RLENGTH - 2), a, " ")
        split(a[n], f, "/")
        stage = (n > 1) ? a[1] : "stage-0"
        total[stage] = f[2]
        if (f[1] > reached[stage]) reached[stage] = f[1] + 0
        label = substr($0, RSTART + RLENGTH + 1)
        sub(/^RUN /, "Running: ", label)
        sub(/^COPY /, "Copying: ", label)
        sub(/^FROM /, "Fetching base image: ", label)
    }
    END {
        t0 = total["stage-0"]; t1 = ("stage-1" in total) ? total["stage-1"] : 1
        if (t0 == 0) { print "|Preparing the build"; exit }
        if (reached["stage-1"] > 0) done = t0 + reached["stage-1"] - 1
        else done = reached["stage-0"] - 1
        pct = int(100 * done / (t0 + t1))
        if (pct > 99) pct = 99
        printf "%d|%s\n", pct, label
    }' "$1"
}

# Build the image described by a Dockerfile and tag it.
# Usage: build_image <image dir>/Dockerfile <tag> [extra docker buildx arguments...]
build_image() {
    local dockerfile=$1
    local tag=$2
    shift 2

    local old_id
    old_id=$(docker image inspect --format '{{.Id}}' "$tag" 2>/dev/null || true)

    local log
    log=$(mktemp -t "build-${tag//[^A-Za-z0-9._-]/_}.XXXXXX.log")
    ui_run "Building $tag" "$log" buildx_progress \
        docker buildx build --progress=plain --network="$BUILD_NETWORK" --load \
        -f "$dockerfile" -t "$tag" "$@" .

    # Docker moves the tag to the new image, so the old image is now untagged.
    # Remove it, and only warn if it is still in use or has other tags.
    local new_id
    new_id=$(docker image inspect --format '{{.Id}}' "$tag")
    if [[ -n $old_id && $old_id != "$new_id" ]]; then
        docker image rm "$old_id" || echo "warning: could not remove old image $old_id" >&2
    fi
    printf 'Image %s%s%s is ready (%s)\n' "$UI_BOLD" "$tag" "$UI_RESET" "${new_id#sha256:}"
}

# Stop unless CUDA_HOST_DIR holds a CUDA toolkit.
require_cuda_host_dir() {
    if [[ -z $CUDA_HOST_DIR || ! -f $CUDA_HOST_DIR/include/cuda_runtime.h ]]; then
        die "CUDA headers not found${CUDA_HOST_DIR:+ under $CUDA_HOST_DIR} (no include/cuda_runtime.h)." \
            "Set CUDA_HOST_DIR to the host CUDA toolkit directory."
    fi
}

build_mpich() {
    require_cuda_host_dir
    build_image mpich/Dockerfile mpialma9-2:latest \
        --build-context "cuda=$CUDA_HOST_DIR"
}

build_ompi() {
    require_cuda_host_dir
    build_image ompi/Dockerfile openmpialma9:latest \
        --build-context "cuda=$CUDA_HOST_DIR"
}

build_mpich_cuda() {
    build_image mpich-cuda/Dockerfile "mpicuda13:$cuda_tag"
}

# Print one menu entry: a number, a name, then description lines and a tag line.
# Usage: menu_item <number> <name> <tag> <description line>...
menu_item() {
    local number=$1 name=$2 tag=$3
    shift 3
    printf '  %s%s)%s %s%s%s\n' "$UI_CYAN" "$number" "$UI_RESET" "$UI_BOLD" "$name" "$UI_RESET"
    printf '     %s\n' "$@"
    printf '     %sTag:%s %s\n\n' "$UI_YELLOW" "$UI_RESET" "$tag"
}

case ${1:-} in
    mpich) build_mpich; exit 0 ;;
    ompi) build_ompi; exit 0 ;;
    mpich-cuda) build_mpich_cuda; exit 0 ;;
esac

printf '%sChoose a container to build:%s\n\n' "$UI_BOLD" "$UI_RESET"
menu_item 1 "mpich" "mpialma9-2:latest" \
    "MPICH built with CUDA support, on the ATLAS AlmaLinux 9 base image." \
    "CUDA headers come from the host at" \
    "${CUDA_HOST_DIR:-<CUDA_HOST_DIR not found>} during the build, so CUDA is not" \
    "installed in the image."
menu_item 2 "ompi" "openmpialma9:latest" \
    "CUDA-aware OpenMPI 5 with ULFM fault tolerance, on the ATLAS" \
    "AlmaLinux 9 base image. CUDA headers come from the host at" \
    "${CUDA_HOST_DIR:-<CUDA_HOST_DIR not found>} during the build, so CUDA is not" \
    "installed in the image."
menu_item 3 "mpich + cuda" "mpicuda13:$cuda_tag" \
    "MPICH built with CUDA support, on NVIDIA's Rocky 9 CUDA devel image" \
    "(CUDA $cuda_version). Use it for GPU MPI jobs with MPICH."

while true; do
    read -r -p "${UI_BOLD}Enter a number (1-3):${UI_RESET} " choice
    case $choice in
        1) build_mpich ;;
        2) build_ompi ;;
        3) build_mpich_cuda ;;
        *) printf '%sInvalid choice: %s%s\n' "$UI_RED" "$choice" "$UI_RESET" >&2; continue ;;
    esac
    break
done

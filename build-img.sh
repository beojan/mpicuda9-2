#!/usr/bin/env bash
# Copyright (C) 2002-2026 CERN for the benefit of the ATLAS collaboration

# Convert a Docker image into an Apptainer SIF image (mpi.img).
#
# Usage: build-img.sh [image]
#   image  Docker image to convert, default mpicuda13:13.4. The image must be
#          in the local Docker daemon, for example one built by build-containers.sh.
#
# Environment:
#   OUTPUT_IMG  Output path, default ./mpi.img in the directory you run from.
#   WORK_ROOT   Directory for the build's temporary and cache files, default
#               the directory that holds OUTPUT_IMG. Keep it on disk, not
#               tmpfs (/tmp and /dev/shm), so the squashfs build does not use RAM.
#
# The build writes to a temporary directory under WORK_ROOT and moves the
# finished image to OUTPUT_IMG. The temporary directory is removed on exit.

set -Eeuo pipefail

readonly image_ref=${1:-mpicuda13:13.4}
readonly output_img=${OUTPUT_IMG:-"$(pwd)/mpi.img"}
readonly work_root=${WORK_ROOT:-"$(dirname -- "${output_img}")"}

if [[ ! -d ${work_root} ]]; then
    printf 'Work directory does not exist: %s\n' "${work_root}" >&2
    exit 1
fi

readonly work_dir="$(mktemp -d "${work_root}/.img-build.XXXXXXXX")"

cleanup() {
    local status=$?
    rm -rf -- "${work_dir}"
    exit "${status}"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "${work_dir}/apptainer-cache" "${work_dir}/apptainer-tmp"

TMPDIR="${work_dir}" \
APPTAINER_CACHEDIR="${work_dir}/apptainer-cache" \
APPTAINER_TMPDIR="${work_dir}/apptainer-tmp" \
    apptainer build \
        --mksquashfs-args "-comp xz -b 1M -Xbcj x86" \
        "${work_dir}/mpi.img" \
        "docker-daemon://${image_ref}"

mv -fT -- "${work_dir}/mpi.img" "${output_img}"
printf 'Built %s from Docker image %s\n' "${output_img}" "${image_ref}"

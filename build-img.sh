#!/usr/bin/env bash
# Copyright (C) 2002-2026 CERN for the benefit of the ATLAS collaboration

# Convert a Docker image into an Apptainer SIF image (mpi.img).
#
# Usage: build-img.sh [-h|--help] [image]
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

source "$(dirname -- "${BASH_SOURCE[0]}")/common/ui.sh"

usage() {
    cat <<EOF
${UI_BOLD}Usage:${UI_RESET} $(basename -- "$0") [-h|--help] [image]

Convert a Docker image from the local Docker daemon into an Apptainer image.

${UI_BOLD}Arguments:${UI_RESET}
  image         Docker image to convert, as name:tag. Default: mpicuda13:13.4.
                Build one first with build-containers.sh. List the images
                you have with: docker image ls

${UI_BOLD}Environment:${UI_RESET}
  OUTPUT_IMG    Output path. Default: ./mpi.img in the current directory.
  WORK_ROOT     Directory for temporary and cache files. Default: the
                directory that holds OUTPUT_IMG. Keep it on disk, not on
                tmpfs (/tmp and /dev/shm), so the squashfs build does not
                use RAM. It needs room for the whole image and its cache.
  NO_COLOR      Set to turn off colours.

The finished image is written to OUTPUT_IMG. Temporary files are removed on exit.
EOF
}

# Print an error with an optional hint on the next line, then exit.
# Usage: die <message> [hint]
die() {
    printf '%serror:%s %s\n' "${UI_RED}" "${UI_RESET}" "$1" >&2
    if [[ -n ${2:-} ]]; then
        printf '%shint:%s  %s\n' "${UI_YELLOW}" "${UI_RESET}" "$2" >&2
    fi
    exit 1
}

case ${1:-} in
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; die "unknown option: $1" ;;
esac
(($# <= 1)) || { usage >&2; die "expected at most one image argument, got $#"; }

readonly image_ref=${1:-mpicuda13:13.4}
readonly output_img=${OUTPUT_IMG:-"$(pwd)/mpi.img"}
readonly work_root=${WORK_ROOT:-"$(dirname -- "${output_img}")"}

command -v apptainer >/dev/null ||
    die "apptainer is not on PATH." "Install Apptainer or load it, then run this script again."
command -v docker >/dev/null ||
    die "docker is not on PATH." "This script reads the image from the local Docker daemon."
docker image inspect "${image_ref}" >/dev/null 2>&1 ||
    die "Docker image '${image_ref}' was not found in the local daemon." \
        "Build it with build-containers.sh, or pass another image. Available images: docker image ls"
[[ -d ${work_root} ]] ||
    die "Work directory does not exist: ${work_root}" "Create it, or set WORK_ROOT to a directory on disk."
[[ -w ${work_root} ]] ||
    die "Work directory is not writable: ${work_root}" "Set WORK_ROOT to a directory you can write to."
[[ -d $(dirname -- "${output_img}") && -w $(dirname -- "${output_img}") ]] ||
    die "Cannot write the output image to: ${output_img}" "Set OUTPUT_IMG to a path in a writable directory."

readonly work_dir="$(mktemp -d "${work_root}/.img-build.XXXXXXXX")"

cleanup() {
    local status=$?
    ui_show_cursor
    rm -rf -- "${work_dir}"
    exit "${status}"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "${work_dir}/apptainer-cache" "${work_dir}/apptainer-tmp"

# Read the apptainer log and print "<percent>|<label>". The percentage comes
# from the progress line that mksquashfs prints while it compresses the image.
# Before that stage, and whenever mksquashfs prints no progress, the percentage
# is empty and the label is the latest INFO message.
apptainer_progress() {
    local text pct label
    text=$(tr '\r' '\n' <"$1" | tail -n 40)
    pct=$(rg -o -r '$1' '\]\s+\d+/\d+\s+(\d+)%' <<<"$text" | tail -n 1 || true)
    if [[ -n $pct ]]; then
        printf '%s|Compressing the filesystem\n' "$pct"
        return
    fi
    label=$(rg -o -r '$1' '^(?:INFO|WARNING):\s+(.*)' <<<"$text" | tail -n 1 || true)
    printf '|%s\n' "${label:-Starting apptainer}"
}

export TMPDIR="${work_dir}"
export APPTAINER_CACHEDIR="${work_dir}/apptainer-cache"
export APPTAINER_TMPDIR="${work_dir}/apptainer-tmp"

log="$(mktemp -t apptainer-build.XXXXXXXX.log)"
if ! ui_run "Converting ${image_ref} to an Apptainer image" "${log}" apptainer_progress \
    apptainer build \
        --mksquashfs-args "-comp xz -b 1M -Xbcj x86" \
        "${work_dir}/mpi.img" \
        "docker-daemon://${image_ref}"; then
    printf '\n%sThe conversion did not finish.%s Common causes:\n' "${UI_BOLD}" "${UI_RESET}" >&2
    printf '  - No space left in %s (free space: %s)\n' "${work_root}" \
        "$(df -h --output=avail -- "${work_root}" | tail -n 1 | tr -d ' ')" >&2
    printf '  - The Docker daemon is not running or not reachable\n' >&2
    printf '  - Apptainer needs extra privileges (try --fakeroot or check its setup)\n' >&2
    exit 1
fi

mv -fT -- "${work_dir}/mpi.img" "${output_img}"
printf 'Wrote %s%s%s\n' "${UI_BOLD}" "${output_img}" "${UI_RESET}"

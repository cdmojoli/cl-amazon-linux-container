#!/usr/bin/env bash
#
# build-al2023-lisp-oci-image.sh — build an Amazon Linux 2023 container image with
# a Common Lisp implementation.
#
#   ./build-al2023-lisp-oci-image.sh --impl sbcl-bin/2.3.7        # overrides CL_IMPLEMENTATION
#   DOCKER_BUILDKIT=1 ./build-al2023-lisp-oci-image.sh --impl ... # enable BuildKit
#   ./build-al2023-lisp-oci-image.sh -q --impl ...                # quiet docker build output
#   ./build-al2023-lisp-oci-image.sh -h                           # help
#
#   ./build-al2023-lisp-oci-image.sh --impl ecl/24.5.10 -- \
#       --no-cache                                  # pass extra args to docker
#
# BuildKit is disabled by default to accommodate for users who use
# plain docker without it. If you have it installed and want its
# better performance and features, set DOCKER_BUILDKIT=1 in the
# environment.

set -euo pipefail

################################################################################
# Configuration defaults
################################################################################
DEFAULT_IMPL="sbcl-bin"
IMAGE_NAME="cl-amazon-linux"
TAG=""
TAG_GIVEN=0
DOCKER_EXTRA_ARGS=()
QUIET=0
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

################################################################################
# Helper functions
################################################################################
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] --impl IMPLEMENTATION [-- [DOCKER_BUILD_ARGS...]]

Build an Amazon Linux 2023 container image with a Common Lisp implementation.

Options:
  -n, --name NAME           Docker image name            (default: ${IMAGE_NAME})
  -t, --tag TAG             Docker image tag             (default: auto)
  --impl IMPLEMENTATION     Common Lisp implementation   (required)
  -q, --quiet               Reduce verbosity
  -h, --help                Show this help text and exit

Environment:
  DOCKER_BUILDKIT           Default is 0 for the legacy builder.
                            Set to 1 to enable BuildKit (if you have it).

Examples:
  $(basename "$0") --impl sbcl-bin                     # use latest SBCL binary
  $(basename "$0") --impl sbcl/2.5.9                   # build SBCL 2.5.9 from source
  DOCKER_BUILDKIT=1 $(basename "$0") --impl sbcl-bin   # enable BuildKit
  $(basename "$0") -n myname -t v2 --impl ecl/24.5.10
  $(basename "$0") --impl ccl-bin -- --no-cache        # extra docker args
  $(basename "$0") -q --impl sbcl-bin/2.3.7            # quiet docker build

EOF
}

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

################################################################################
# Argument parsing
################################################################################
# Print usage when invoked with no arguments
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

CL_IMPLEMENTATION="$DEFAULT_IMPL"
IMPL_GIVEN=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            [[ $# -lt 2 ]] && die "Missing value for $1"
            IMAGE_NAME=$2
            shift 2
            ;;
        -t|--tag)
            [[ $# -lt 2 ]] && die "Missing value for $1"
            TAG=$2
            TAG_GIVEN=1
            shift 2
            ;;
        --impl)
            [[ $# -lt 2 ]] && die "Missing value for $1"
            CL_IMPLEMENTATION=$2
            IMPL_GIVEN=1
            shift 2
            ;;
        -q|--quiet)
            QUIET=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "Unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

# Remaining parameters (if any) are passed verbatim to docker build
DOCKER_EXTRA_ARGS=("$@")

# Ensure --impl was provided
if [[ ${IMPL_GIVEN} -eq 0 ]]; then
    usage
    die "--impl is mandatory"
fi

################################################################################
# Environment defaults
################################################################################
: "${DOCKER_BUILDKIT:=0}"   # disable BuildKit unless caller overrides
export DOCKER_BUILDKIT

################################################################################
# Pre-flight checks
################################################################################
command -v docker >/dev/null 2>&1 || die "Docker is not installed or not on PATH"
docker info >/dev/null 2>&1       || die "Docker daemon not reachable (is it running?)"

log "Docker found: $(docker --version)"
if [[ ${TAG_GIVEN} -eq 1 ]]; then
    log "Building image ${IMAGE_NAME}:${TAG}"
else
    log "Building image ${IMAGE_NAME} (tag will be determined after build)"
fi
log "Using CL_IMPLEMENTATION=${CL_IMPLEMENTATION}"
if [[ ${DOCKER_BUILDKIT} == 1 ]]; then
    log "BuildKit is ENABLED (export DOCKER_BUILDKIT=0 to disable)"
else
    log "BuildKit is DISABLED"
fi
if [[ ${QUIET} -eq 1 ]]; then
    log "Docker build quiet mode ENABLED (-q)"
fi
if [[ ${#DOCKER_EXTRA_ARGS[@]} -gt 0 ]]; then
    log "Forwarding extra docker build args: ${DOCKER_EXTRA_ARGS[*]}"
fi

################################################################################
# Build
################################################################################
START_TIME=$(date +%s)

log "Starting actual build. Uncached builds may take a couple minutes..."
DOCKER_QUIET_ARGS=()
if [[ ${QUIET} -eq 1 ]]; then
    DOCKER_QUIET_ARGS+=(-q)
elif [[ -n "${INSIDE_EMACS+x}" ]]; then
    log "WARNING: Verbose builds inside Emacs may hang."
    # Perhaps due terminal escape codes in verbose progress bars?
fi

if [[ ${TAG_GIVEN} -eq 1 ]]; then
    docker build \
           "${DOCKER_QUIET_ARGS[@]}" \
           --build-arg "CL_IMPLEMENTATION=${CL_IMPLEMENTATION}" \
           -t "${IMAGE_NAME}:${TAG}" \
           "${DOCKER_EXTRA_ARGS[@]}" \
           "${SCRIPT_DIR}"
else
    IID_FILE=$(mktemp)
    trap '[[ -n ${IID_FILE:-} && -f "$IID_FILE" ]] && rm -f -- "$IID_FILE"' EXIT INT TERM
    docker build \
           "${DOCKER_QUIET_ARGS[@]}" \
           --build-arg "CL_IMPLEMENTATION=${CL_IMPLEMENTATION}" \
           --iidfile "${IID_FILE}" \
           "${DOCKER_EXTRA_ARGS[@]}" \
           "${SCRIPT_DIR}"
    IMAGE_ID=$(cat "${IID_FILE}")
    rm -f "${IID_FILE}"
    trap - EXIT INT TERM
    unset IID_FILE
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
log "Build finished successfully in ${ELAPSED} seconds."

################################################################################
# Tag image if no tag was provided
################################################################################
if [[ ${TAG_GIVEN} -eq 0 ]]; then
    impl_name=${CL_IMPLEMENTATION%%/*}
    if [[ ${CL_IMPLEMENTATION} == */* ]]; then
        release=${CL_IMPLEMENTATION#*/}
    else
        release=$(docker run --rm "${IMAGE_ID}" ros run --eval "(format t \"~A\" (lisp-implementation-version))" -q)
        release=${release//[[:space:]]/}
    fi
    # Sanitize release string for Docker tag compatibility
    release=${release//[[:space:]]/}
    release=${release//[^a-zA-Z0-9_.-]/-}
    TAG="${impl_name}-${release}"
    docker tag "${IMAGE_ID}" "${IMAGE_NAME}:${TAG}"
    log "Tagged image as ${IMAGE_NAME}:${TAG}"
fi

log "You can now test run your image: docker run --rm ${IMAGE_NAME}:${TAG} ros run --eval '(format t \"Image with ~A/~A ready for use!~%\" (lisp-implementation-type) (lisp-implementation-version))' -q"

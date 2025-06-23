#!/usr/bin/env bash
#
# build-image.sh  — build the Amazon Linux 2023 Common Lisp container image
#
#   ./build-image.sh --impl sbcl-bin/2.3.7          # overrides CL_IMPLEMENTATION
#   DOCKER_BUILDKIT=0 ./build-image.sh --impl ...   # disable BuildKit
#   ./build-image.sh -h                             # help
#
#   ./build-image.sh --impl ecl/24.5.10 -- \
#       --no-cache                                  # pass extra args to docker
#
# BuildKit is enabled by default for better performance and features.
# Users on old Docker releases or who hit a problem can disable it by
# setting DOCKER_BUILDKIT=0 in the environment.

set -euo pipefail

################################################################################
# Configuration defaults
################################################################################
DEFAULT_IMPL="sbcl-bin"
IMAGE_NAME="cl-amazon-linux"
TAG=""
TAG_GIVEN=0
DOCKER_EXTRA_ARGS=()

################################################################################
# Helper functions
################################################################################
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] --impl IMPLEMENTATION [-- [DOCKER_BUILD_ARGS...]]

Build a Common Lisp container image from ./Dockerfile.

Options:
  -n, --name NAME           Docker image name            (default: ${IMAGE_NAME})
  -t, --tag TAG             Docker image tag             (default: auto)
  --impl IMPLEMENTATION     Common Lisp implementation   (required)
  -h, --help                Show this help text and exit

Environment:
  DOCKER_BUILDKIT           Set to 0 to fall back to the legacy builder.
                            Defaults to 1 (BuildKit enabled).

Examples:
  $(basename "$0") --impl sbcl-bin                     # build with latest SBCL
  DOCKER_BUILDKIT=0 $(basename "$0") --impl sbcl-bin   # disable BuildKit
  $(basename "$0") -n myname -t v2 --impl ecl/24.5.10
  $(basename "$0") --impl ccl-bin -- --no-cache        # extra docker args
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
: "${DOCKER_BUILDKIT:=1}"   # enable BuildKit unless caller overrides

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
if [[ ${#DOCKER_EXTRA_ARGS[@]} -gt 0 ]]; then
    log "Forwarding extra docker build args: ${DOCKER_EXTRA_ARGS[*]}"
fi

################################################################################
# Build
################################################################################
START_TIME=$(date +%s)

if [[ ${TAG_GIVEN} -eq 1 ]]; then
    docker build \
           --build-arg "CL_IMPLEMENTATION=${CL_IMPLEMENTATION}" \
           -t "${IMAGE_NAME}:${TAG}" \
           "${DOCKER_EXTRA_ARGS[@]}" \
           .
else
    IMAGE_ID=$(docker build -q \
                      --build-arg "CL_IMPLEMENTATION=${CL_IMPLEMENTATION}" \
                      "${DOCKER_EXTRA_ARGS[@]}" \
                      .)
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

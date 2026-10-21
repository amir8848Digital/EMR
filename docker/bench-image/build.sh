#!/usr/bin/env bash
# Build the ready-to-develop bench image.
#
#   docker/bench-image/build.sh                    # build only
#   docker/bench-image/build.sh --push             # build and push to GHCR
#   BENCH_DIR=../other-bench docker/bench-image/build.sh
#
# Two images are built:
#   emr-bench-base  — OS, Python 3.14, Node, wkhtmltopdf, bench CLI (no app code)
#   emr-bench       — the above plus all nine apps, their node_modules and a
#                     prebuilt virtualenv
# The base is shared with the main stack's `frappe` service, so the runtime is
# defined in exactly one place (docker/frappe/Dockerfile).
#
# ⚠ The result CONTAINS PROPRIETARY CODE (four private 8848digital apps, and
# emr_sso which is licensed Proprietary). Push only to a PRIVATE registry.
set -euo pipefail

cd "$(dirname "$0")/../.."          # repo root
REPO_ROOT="$PWD"

BENCH_DIR="${BENCH_DIR:-$REPO_ROOT/demo-bench}"
IMAGE="${IMAGE:-ghcr.io/amir8848digital/emr-bench}"
TAG="${TAG:-latest}"
BASE_IMAGE="emr-bench-base:latest"

if [ ! -f "$BENCH_DIR/sites/apps.txt" ]; then
  echo "error: $BENCH_DIR does not look like a bench (no sites/apps.txt)" >&2
  exit 1
fi

echo "==> bench:  $BENCH_DIR"
echo "==> apps:   $(tr '\n' ' ' < "$BENCH_DIR/sites/apps.txt")"
echo "==> image:  $IMAGE:$TAG"
echo

echo "==> [1/2] base runtime"
# The main stack's `frappe` service is built from the very same
# docker/frappe/Dockerfile, so if that image is already here, reuse it rather
# than re-pulling the ~212MB python:3.14 base. Set REBUILD_BASE=1 to force.
EXISTING_BASE="emr-stack-frappe:latest"
if [ -z "${REBUILD_BASE:-}" ] && docker image inspect "$EXISTING_BASE" >/dev/null 2>&1; then
  echo "    reusing $EXISTING_BASE (set REBUILD_BASE=1 to rebuild from scratch)"
  BASE_IMAGE="$EXISTING_BASE"
else
  docker build -t "$BASE_IMAGE" \
    --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" \
    "$REPO_ROOT/docker/frappe"
fi

echo "==> [2/2] bench image (copies ~1.5GB of apps, then builds the virtualenv)"
# The main context is the bench itself, trimmed by demo-bench/.dockerignore.
# `cfg` is a second, named context holding this directory's config files,
# because a COPY cannot reach outside the main context.
docker build -t "$IMAGE:$TAG" \
  --build-arg BASE="$BASE_IMAGE" \
  --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" \
  --build-arg HOST_BENCH_PATH="$(cd "$BENCH_DIR" && pwd)" \
  --build-context cfg="$REPO_ROOT/docker/bench-image" \
  -f "$REPO_ROOT/docker/bench-image/Dockerfile" \
  "$BENCH_DIR"

echo
echo "==> built $IMAGE:$TAG  ($(docker image inspect "$IMAGE:$TAG" --format '{{.Size}}' | awk '{printf "%.1fGB", $1/1024/1024/1024}'))"

if [ "${1:-}" = "--push" ]; then
  echo "==> pushing to $IMAGE:$TAG"
  docker push "$IMAGE:$TAG"
  cat <<MSG

Pushed. Confirm the package is PRIVATE before sharing:
  https://github.com/users/amir8848Digital/packages/container/emr-bench/settings
MSG
else
  echo
  echo "Not pushed. Re-run with --push when you are ready."
fi

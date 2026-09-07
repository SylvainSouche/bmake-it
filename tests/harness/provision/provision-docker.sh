#!/bin/sh
# provision-docker.sh <base-image> <platform-or-empty> <install-cmd> <tag>
#
# Builds a provisioned, tagged image via `docker run --platform` + `commit`
# rather than `docker build --platform` -- this Colima setup has no buildx
# plugin installed, and without it `docker build --platform` silently falls
# back to the legacy builder, which ignores --platform entirely and builds
# for the host's native arch (found empirically: requested amd64, got
# arm64 packages). `docker run --platform` has no such problem -- it's been
# reliable all session (qemu-user emulation via binfmt_misc) -- so this
# script uses that same proven mechanism instead of the build path.
set -eu
BASE_IMAGE="${1:?usage: provision-docker.sh <base-image> <platform-or-empty> <install-cmd> <tag>}"
PLATFORM="${2:-}"
INSTALL_CMD="${3:?}"
TAG="${4:?}"

cid=$(docker create ${PLATFORM:+--platform "$PLATFORM"} "$BASE_IMAGE" sleep infinity)
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
docker start "$cid" >/dev/null
docker exec "$cid" sh -c "$INSTALL_CMD"
docker commit "$cid" "$TAG" >/dev/null
echo "provision-docker.sh: tagged $TAG (platform=${PLATFORM:-host})"

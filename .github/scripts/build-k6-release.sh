#!/bin/bash

set -eEuo pipefail

eval "$(go env)"

set -x

export K6_VERSION=${K6_VERSION-v0.43.1}

export OUT_DIR=dist
# To override the latest git tag as the version, pass something else as the second arg.
export VERSION=${1:-$(git describe --tags --always --dirty)}

# To overwrite the version details, pass something as the third arg. Empty string disables it.
export VERSION_DETAILS=${2-"$(date -u +"%FT%T%z")/$(git describe --tags --always --long --dirty)"}
set +x

build() {
    local ALIAS="$1" SUFFIX="${2}"  # Any other arguments are passed to the go build command as env vars
    local NAME="k6-${VERSION}-${ALIAS}"

    local PACKAGE_FORMATS
    IFS="," read -ra PACKAGE_FORMATS <<< "${3}"

    local ENV_VARS
    IFS="," read -ra ENV_VARS <<< "${4}"

    echo "- Building platform: ${ALIAS} (" "${ENV_VARS[@]}" "xk6 build ${K6_VERSION} --with github.com/szkiba/xk6-crypto=." ")"

    mkdir -p "${OUT_DIR}/${NAME}"

    # Subshell to not mess with the current env vars or CWD
    (
        export "${ENV_VARS[@]}"
        # Build a binary
        go mod tidy -compat=1.18
        go generate ./...
        go install go.k6.io/xk6/cmd/xk6@latest
        xk6 build "${K6_VERSION}" --with github.com/szkiba/xk6-crypto=.

        for format in "${PACKAGE_FORMATS[@]}"; do
            package "$format"
        done
    )
}

package() {
    local FMT="$1"
    echo "- Creating ${NAME}.${FMT} package..."
    case $FMT in
    tgz)
        tar -C "${OUT_DIR}" -zcf "${OUT_DIR}/${NAME}.tar.gz" "$NAME"
        ;;
    zip)
        (cd "${OUT_DIR}" && zip -rq9 - "$NAME") > "${OUT_DIR}/${NAME}.zip"
        ;;
    *)
        echo "Unknown format: $FMT"
        return 1
        ;;
    esac
}

cleanup() {
    find "$OUT_DIR" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \;
    echo "--- Cleaned ${OUT_DIR}"
}
trap cleanup EXIT

echo "--- Building Release: ${VERSION}"

mkdir -p "$OUT_DIR"

build linux-amd64    ""    tgz    GOOS=linux,GOARCH=amd64,CGO_ENABLED=0
build linux-arm64    ""    tgz    GOOS=linux,GOARCH=arm64,CGO_ENABLED=0
build darwin-amd64   ""    zip    GOOS=darwin,GOARCH=amd64
build darwin-arm64   ""    zip    GOOS=darwin,GOARCH=arm64

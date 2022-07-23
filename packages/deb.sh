#!/usr/bin/env bash
# Build a deb package

set -e

BUILD_PATH="$1"
DEB_TEMPLATE_PATH="$2"
NIX_RESULT_PATH="$3"
DEB_BUILD_PATH="$BUILD_PATH"/deb-build/$(basename "$DEB_TEMPLATE_PATH")
DEB_INSTALL_PATH="$BUILD_PATH"/deb-install

mkdir -p "$DEB_BUILD_PATH" "$DEB_INSTALL_PATH"
cp -r "$DEB_TEMPLATE_PATH"/* "$DEB_BUILD_PATH"
mkdir "$DEB_BUILD_PATH"/usr
cp -r "$NIX_RESULT_PATH"/* "$DEB_BUILD_PATH"/usr
dpkg-deb --build "$DEB_BUILD_PATH"
cp "$BUILD_PATH"/deb-build/*.deb "$DEB_INSTALL_PATH"
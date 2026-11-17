#!/bin/bash
set -euo pipefail
umask 077

scripts="$(cd "$(dirname "$0")" && pwd -P)"
source "$scripts/upstream.env"
destination="$1"
if [[ -x "$destination/Contents/MacOS/Main" ]]; then
    exit 0
fi

parent="$(dirname "$destination")"
mkdir -p "$parent"
work="$(mktemp -d "$parent/.mu-solo-client.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
trap 'exit 130' INT TERM

download() {
    local url="$1" filename="$2" checksum="$3"
    /usr/bin/curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 \
        "$url/$filename" -o "$work/$filename"
    printf '%s  %s\n' "$checksum" "$work/$filename" | /usr/bin/shasum -a 256 -c -
}

echo "Installing MuMain $MUMAIN_VERSION with its matching game data"
runtime="MuMain-macos-native-arm64-release-editor-off-no-data.tar.gz"
data="MuMain-data-$MUMAIN_DATA_ID.tar.gz"
releases=https://github.com/sven-n/MuMain/releases/download
download "$releases/$MUMAIN_VERSION" "$runtime" "$MUMAIN_RUNTIME_SHA"
download "$releases/data-$MUMAIN_DATA_ID" "$data" "$MUMAIN_DATA_SHA"
/usr/bin/tar -xzf "$work/$runtime" -C "$work"
client="$work/$(basename "$destination")"
mv "$work/Main.app" "$client"
client_bin="$client/Contents/MacOS"
resources="$client/Contents/Resources"
/usr/bin/tar -xzf "$work/$data" -C "$resources"
test -x "$client_bin/Main"
test -d "$resources/Data"
test -d "$resources/fonts"

# MuMain seeds its per-user settings from this template.
/usr/bin/sed -i '' -e 's/^Name=$/Name=MU Solo/' -e 's/^ServerIP=localhost$/ServerIP=127.0.0.1/' \
    "$client_bin/config.ini.template"

# Keep the executable-relative paths while sealing data in Resources.
for resource in MuMainIcon.png config.ini.template release-version.txt shaders; do
    mv "$client_bin/$resource" "$resources/"
done
for resource in Data fonts MuMainIcon.png config.ini.template release-version.txt shaders; do
    ln -s "../Resources/$resource" "$client_bin/$resource"
done

/usr/bin/codesign --force --sign - "$client_bin/MUnique.Client.Library.dylib"
/usr/bin/codesign --force --sign - "$client"
/usr/bin/codesign --verify --deep --strict "$client"
mv "$client" "$parent/"

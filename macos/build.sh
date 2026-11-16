#!/bin/bash
set -euo pipefail

[[ "$(uname -s)-$(uname -m)" == Darwin-arm64 ]] || {
    echo "Build on an Apple Silicon Mac or a macos-26 GitHub runner." >&2
    exit 1
}
root="$(cd "$(dirname "$0")/.." && pwd -P)"
source "$root/macos/upstream.env"
work="$(mktemp -d "${TMPDIR:-/tmp}/mu-solo-build.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$root/dist"
server="$work/MU Server.app"
contents="$server/Contents"
resources="$contents/Resources"
mkdir -p "$contents/MacOS" "$resources"

download() {
    curl --fail --silent --show-error --location --retry 3 "$1" -o "$2"
}

verify() {
    printf '%s  %s\n' "$1" "$2" | shasum -a 256 -c -
}

echo "Building the bundled PostgreSQL server"
pg_name="postgresql-$POSTGRES_VERSION"
pg_url="https://ftp.postgresql.org/pub/source/v$POSTGRES_VERSION/$pg_name.tar.gz"
download "$pg_url" "$work/$pg_name.tar.gz"
download "$pg_url.sha256" "$work/postgres.sha256"
verify "$(awk 'NR == 1 {print $1}' "$work/postgres.sha256")" "$work/$pg_name.tar.gz"
tar -xzf "$work/$pg_name.tar.gz" -C "$work"
pg_prefix=/usr/local/mu-solo-postgresql
(
    cd "$work/$pg_name"
    # Keep the runtime independent of Homebrew libraries.
    LDFLAGS="-Wl,-headerpad_max_install_names" ./configure --prefix="$pg_prefix" \
        --without-icu --without-readline --without-zlib
    make -j"$(sysctl -n hw.ncpu)"
    make install DESTDIR="$work/pg-install"
)
mv "$work/pg-install$pg_prefix" "$resources/PostgreSQL"
cp "$work/$pg_name/COPYRIGHT" "$resources/PostgreSQL/COPYRIGHT"
python3 "$root/macos/relocate-postgres.py" "$resources/PostgreSQL" "$pg_prefix"

echo "Building OpenMU $OPENMU_REF"
git init -q "$work/OpenMU"
git -C "$work/OpenMU" fetch --depth 1 https://github.com/MUnique/OpenMU.git "$OPENMU_REF"
git -C "$work/OpenMU" checkout -q --detach FETCH_HEAD
python3 "$root/macos/prepare-openmu.py" "$work/OpenMU"
dotnet publish "$work/OpenMU/src/Startup/MUnique.OpenMU.Startup.csproj" \
    --configuration Release --runtime osx-arm64 --self-contained true \
    --output "$resources/OpenMU"
cp "$work/OpenMU/LICENSE" "$resources/OpenMU/LICENSE"
test -f "$resources/OpenMU/ConnectionSettings.xml"
sed -i '' 's/Port=5432;/Port=55436;/g' "$resources/OpenMU/ConnectionSettings.xml"
cp "$root/macos/start-server.sh" "$resources/"
cp "$root/macos/ServerInfo.plist" "$contents/Info.plist"
swiftc -swift-version 5 -O "$root/macos/ServerApp.swift" -o "$contents/MacOS/MUServer"

echo "Assembling MuMain $MUMAIN_VERSION with matching game data"
runtime="MuMain-macos-native-arm64-release-editor-off-no-data.tar.gz"
data="MuMain-data-$MUMAIN_DATA_ID.tar.gz"
releases=https://github.com/sven-n/MuMain/releases/download
download "$releases/$MUMAIN_VERSION/$runtime" "$work/$runtime"
verify "$MUMAIN_RUNTIME_SHA" "$work/$runtime"
download "$releases/data-$MUMAIN_DATA_ID/$data" "$work/$data"
verify "$MUMAIN_DATA_SHA" "$work/$data"
tar -xzf "$work/$runtime" -C "$work"
client="$work/MU Client.app"
mv "$work/Main.app" "$client"
client_bin="$client/Contents/MacOS"
tar -xzf "$work/$data" -C "$client_bin"
test -x "$client_bin/Main"
test -d "$client_bin/Data"
test -d "$client_bin/fonts"
cat >"$client_bin/config.ini" <<'EOF'
[CONNECTION SETTINGS]
ServerIP=127.0.0.1
ServerPort=44406
EOF

# Sign the wrappers locally for ARM64. Developer ID distribution is separate.
codesign --force --sign - "$server"
codesign --force --sign - "$client"
codesign --verify "$server"
codesign --verify "$client"
lipo -verify_arch arm64 "$contents/MacOS/MUServer"
lipo -verify_arch arm64 "$resources/OpenMU/MUnique.OpenMU.Startup"
lipo -verify_arch arm64 "$client_bin/Main"
if [[ "${MU_SOLO_SMOKE_TEST:-0}" == 1 ]]; then
    bash "$root/macos/smoke-server.sh" "$resources"
fi

ditto -c -k --sequesterRsrc --keepParent "$server" "$root/dist/MU-Server-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$client" "$root/dist/MU-Client-macOS-arm64.zip"
(cd "$root/dist" && shasum -a 256 MU-*-macOS-arm64.zip > SHA256SUMS.txt)

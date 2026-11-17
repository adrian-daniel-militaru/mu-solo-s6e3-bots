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
# Razor needs a consistent project root and source path when deriving namespaces.
work="$(cd "$work" && pwd -P)"
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
(
    cd "$work/OpenMU"
    dotnet publish src/Startup/MUnique.OpenMU.Startup.csproj \
        --configuration Release --runtime osx-arm64 --self-contained true \
        --output "$resources/OpenMU"
)
cp "$work/OpenMU/LICENSE" "$resources/OpenMU/LICENSE"
test -f "$resources/OpenMU/ConnectionSettings.xml"
sed -i '' 's/Port=5432;/Port=55436;/g' "$resources/OpenMU/ConnectionSettings.xml"
cp "$root/macos/start-server.sh" "$resources/"
cp "$root/macos/ServerInfo.plist" "$contents/Info.plist"
swiftc -swift-version 5 -O "$root/macos/ServerApp.swift" -o "$contents/MacOS/MUServer"
codesign --force --sign - "$server"
codesign --verify --deep --strict "$server"
lipo -verify_arch arm64 "$contents/MacOS/MUServer"
lipo -verify_arch arm64 "$resources/OpenMU/MUnique.OpenMU.Startup"
if [[ "${MU_SOLO_SMOKE_TEST:-0}" == 1 ]]; then
    bash "$root/macos/smoke-server.sh" "$resources"
fi

client="$work/MU Client.app"
if [[ "${MU_SOLO_CLIENT_DOWNLOAD_ON_FIRST_OPEN:-0}" == 1 ]]; then
    game="$work/MU Online.app"
    bash "$root/macos/install-client.sh" "$game"
    lipo -verify_arch arm64 "$game/Contents/MacOS/Main"
    mkdir -p "$client/Contents/MacOS" "$client/Contents/Resources"
    cp "$root/macos/"{install-client.sh,upstream.env} "$client/Contents/Resources/"
    cp "$root/macos/ClientInfo.plist" "$client/Contents/Info.plist"
    plutil -insert MUSoloClientRelease -string "$MUMAIN_VERSION-$MUMAIN_DATA_ID" \
        "$client/Contents/Info.plist"
    swiftc -swift-version 5 -O "$root/macos/ClientApp.swift" -o "$client/Contents/MacOS/MUClient"
    codesign --force --sign - "$client"
    codesign --verify --deep --strict "$client"
    lipo -verify_arch arm64 "$client/Contents/MacOS/MUClient"
else
    bash "$root/macos/install-client.sh" "$client"
    lipo -verify_arch arm64 "$client/Contents/MacOS/Main"
fi

ditto -c -k --sequesterRsrc --keepParent "$server" "$root/dist/MU-Server-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$client" "$root/dist/MU-Client-macOS-arm64.zip"
(cd "$root/dist" && shasum -a 256 MU-*-macOS-arm64.zip > SHA256SUMS.txt)

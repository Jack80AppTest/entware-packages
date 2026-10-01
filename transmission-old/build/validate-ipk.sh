#!/usr/bin/env bash
set -uo pipefail

IPK="${1:?usage: validate-ipk.sh /path/to/transmission-old.ipk}"
IPK="$(readlink -f "$IPK")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
check_file() {
    if [ -e "$1" ] || [ -L "$1" ]; then pass "present: $1"; else fail "missing: $1"; fi
}

mkdir -p "$TMP/control" "$TMP/data"
gzip -dc "$IPK" | tar -xf - -C "$TMP"
tar -xzf "$TMP/control.tar.gz" -C "$TMP/control"
tar -xzf "$TMP/data.tar.gz" -C "$TMP/data"

echo '===== PACKAGE CONTROL ====='
cat "$TMP/control/control"
echo '===== CONFFILES ====='
cat "$TMP/control/conffiles" 2>/dev/null || true
echo '===== PACKAGE SHA256 ====='
sha256sum "$IPK"
echo '===== PRIVATE RUNTIME ====='
find "$TMP/data/opt/lib/transmission-4.1" -maxdepth 1 -printf '%f -> %l\n' 2>/dev/null | sort || true

grep -qx 'Architecture: armv7-3.2' "$TMP/control/control"     && pass 'package architecture armv7-3.2'     || fail 'package architecture is not armv7-3.2'

grep -qx '/opt/etc/transmission/settings.json' "$TMP/control/conffiles"     && pass 'settings.json is protected as a conffile'     || fail 'settings.json is not protected as a conffile'

for runtime in     libstdc++.so.6 libstdc++.so.6.0.33     libgcc_s.so.1     libatomic.so.1 libatomic.so.1.2.0
do
    check_file "$TMP/data/opt/lib/transmission-4.1/$runtime"
done

for global_runtime in libstdc++.so.6 libgcc_s.so.1 libatomic.so.1; do
    if [ -e "$TMP/data/opt/lib/$global_runtime" ] || [ -L "$TMP/data/opt/lib/$global_runtime" ]; then
        fail "private GCC runtime leaked into global /opt/lib: $global_runtime"
    else
        pass "no global replacement of $global_runtime"
    fi
done

expected_bins=(
    transmission-daemon transmission-remote transmission-cli
    transmission-create transmission-edit transmission-show
)

for name in "${expected_bins[@]}"; do
    bin="$TMP/data/opt/bin/$name"
    check_file "$bin"
    [ -f "$bin" ] || continue

    info="$(file "$bin")"
    echo "$info"
    echo "$info" | grep -q 'ELF 32-bit.*ARM'         && pass "$name is a 32-bit ARM ELF"         || fail "$name is not a 32-bit ARM ELF"

    hdr="$(readelf -h "$bin")"
    echo "$hdr" | grep -q 'Machine:.*ARM'         && pass "$name ELF machine is ARM"         || fail "$name ELF machine is not ARM"
    echo "$hdr" | grep -q 'soft-float ABI'         && pass "$name uses soft-float ABI"         || fail "$name does not advertise soft-float ABI"

    interp="$(readelf -l "$bin" | grep 'Requesting program interpreter' || true)"
    echo "$interp"
    echo "$interp" | grep -q '/opt/lib/ld-linux.so.3'         && pass "$name uses Entware ARM loader"         || fail "$name does not use /opt/lib/ld-linux.so.3"

    dynpath="$(readelf -d "$bin" | grep -E '\((RPATH|RUNPATH)\)' || true)"
    echo "$dynpath"
    echo "$dynpath" | grep -Eq '\(RPATH\).*Library rpath: \[/opt/lib/transmission-4\.1\]$'         && pass "$name has exact private Transmission RPATH"         || fail "$name RPATH is not exactly /opt/lib/transmission-4.1"
done

echo '===== DAEMON NEEDED LIBRARIES ====='
readelf -d "$TMP/data/opt/bin/transmission-daemon" | grep NEEDED || true

grep -q 'ARGS="-g /opt/etc/transmission"' "$TMP/data/opt/etc/init.d/S88transmission"     && pass 'init script uses /opt/etc/transmission'     || fail 'init script config directory changed'

grep -q 'TRANSMISSION_WEB_HOME="/opt/share/transmission/public_html"' "$TMP/data/opt/etc/init.d/S88transmission"     && pass 'init script web path unchanged'     || fail 'init script web path changed'

check_file "$TMP/data/opt/share/transmission/public_html/index.html"
check_file "$TMP/data/opt/etc/transmission/settings.json"

glibc_versions="$(
    strings       "$TMP/data/opt/lib/transmission-4.1/libstdc++.so.6.0.33"       "$TMP/data/opt/lib/transmission-4.1/libgcc_s.so.1"       "$TMP/data/opt/lib/transmission-4.1/libatomic.so.1.2.0"       2>/dev/null | grep -oE 'GLIBC_[0-9]+(\.[0-9]+)+' | sort -Vu || true
)"
echo '===== GLIBC VERSIONS REQUIRED BY PRIVATE RUNTIME ====='
printf '%s\n' "$glibc_versions"
max_glibc="$(printf '%s\n' "$glibc_versions" | tail -n 1)"
if [ -z "$max_glibc" ]; then
    fail 'could not determine GLIBC requirements of private runtime'
elif [ "$(printf '%s\n' "$max_glibc" GLIBC_2.27 | sort -V | tail -n 1)" = "GLIBC_2.27" ]; then
    pass "private runtime GLIBC requirement is <= 2.27 (max: $max_glibc)"
else
    fail "private runtime requires newer than GLIBC 2.27 (max: $max_glibc)"
fi

req_versions="$TMP/required-cxx-versions.txt"
provided_versions="$TMP/provided-cxx-versions.txt"
missing_versions="$TMP/missing-cxx-versions.txt"
: > "$req_versions"
for name in "${expected_bins[@]}"; do
    strings "$TMP/data/opt/bin/$name" 2>/dev/null       | grep -E '^(GLIBCXX|CXXABI)_[0-9A-Za-z_.]+$' >> "$req_versions" || true
done
sort -u -o "$req_versions" "$req_versions"
strings "$TMP/data/opt/lib/transmission-4.1/libstdc++.so.6.0.33" 2>/dev/null   | grep -E '^(GLIBCXX|CXXABI)_[0-9A-Za-z_.]+$' | sort -u > "$provided_versions" || true
comm -23 "$req_versions" "$provided_versions" > "$missing_versions" || true

echo '===== REQUIRED C++ ABI VERSIONS ====='
cat "$req_versions"
if [ -s "$missing_versions" ]; then
    echo '===== MISSING C++ ABI VERSIONS =====' >&2
    cat "$missing_versions" >&2
    fail 'bundled libstdc++ does not provide every requested GLIBCXX/CXXABI version'
else
    pass 'bundled libstdc++ satisfies all GLIBCXX/CXXABI versions requested by Transmission'
fi

echo '===== TOP-LEVEL DATA CONTENT ====='
find "$TMP/data" -mindepth 1 -maxdepth 1 -printf '%f\n'
top_count="$(find "$TMP/data" -mindepth 1 -maxdepth 1 -printf '%f\n' | wc -l)"
if [ "$top_count" -eq 1 ] && [ -d "$TMP/data/opt" ]; then
    pass 'package writes only below /opt'
else
    fail 'package contains files outside /opt'
fi

if [ "$failures" -ne 0 ]; then
    echo "VALIDATION FAILED: $failures check(s) failed." >&2
    exit 1
fi

echo 'VALIDATION PASSED: all static checks succeeded.'

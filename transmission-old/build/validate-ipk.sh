#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFERENCE_MANIFEST="$ROOT_DIR/reference-all-in-one-files.txt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

declare -A PKGDIR
declare -A IPKPATH

if [ "$#" -eq 1 ] && [ -d "$1" ]; then
    mapfile -t IPKS < <(find "$1" -maxdepth 1 -type f -name 'transmission-old-*_4.1.3-*.ipk' -print | sort)
else
    IPKS=("$@")
fi

if [ "${#IPKS[@]}" -ne 5 ]; then
    echo "usage: validate-ipk.sh <directory-containing-five-ipks> OR <five-ipk-paths>" >&2
    echo "expected exactly 5 split Transmission IPKs, found ${#IPKS[@]}" >&2
    exit 2
fi

extract_ipk() {
    local ipk="$1"
    local slot="$2"
    mkdir -p "$slot/control" "$slot/data"
    gzip -dc "$ipk" | tar -xf - -C "$slot" || return 1
    tar -xzf "$slot/control.tar.gz" -C "$slot/control" || return 1
    tar -xzf "$slot/data.tar.gz" -C "$slot/data" || return 1
}

control_field() {
    local pkg="$1"
    local key="$2"
    awk -v key="$key" -F': ' '$1 == key { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' "${PKGDIR[$pkg]}/control/control"
}

payload_list() {
    local pkg="$1"
    find "${PKGDIR[$pkg]}/data" \( -type f -o -type l \) -printf '/%P\n' | sort
}

check_present() {
    local pkg="$1"
    local path="$2"
    if [ -e "${PKGDIR[$pkg]}/data$path" ] || [ -L "${PKGDIR[$pkg]}/data$path" ]; then
        pass "$pkg contains $path"
    else
        fail "$pkg missing $path"
    fi
}

echo '===== EXTRACTING PACKAGES ====='
for i in "${!IPKS[@]}"; do
    ipk="${IPKS[$i]}"
    slot="$TMP/pkg-$i"
    if ! extract_ipk "$ipk" "$slot"; then
        fail "could not extract $ipk"
        continue
    fi
    pkg="$(awk -F': ' '$1 == "Package" {print $2; exit}' "$slot/control/control")"
    if [ -z "$pkg" ]; then
        fail "missing Package field in $ipk"
        continue
    fi
    if [ -n "${PKGDIR[$pkg]+x}" ]; then
        fail "duplicate package $pkg"
        continue
    fi
    PKGDIR["$pkg"]="$slot"
    IPKPATH["$pkg"]="$(readlink -f "$ipk")"
    echo "--- $pkg ---"
    cat "$slot/control/control"
    echo "SHA256: $(sha256sum "$ipk" | awk '{print $1}')"
done

required_packages=(
    transmission-old-runtime
    transmission-old-daemon
    transmission-old-cli
    transmission-old-remote
    transmission-old-web
)

for pkg in "${required_packages[@]}"; do
    if [ -n "${PKGDIR[$pkg]+x}" ]; then
        pass "package present: $pkg"
    else
        fail "missing package: $pkg"
    fi
done

if [ "$failures" -ne 0 ]; then
    echo "VALIDATION FAILED: package set incomplete." >&2
    exit 1
fi

echo '===== METADATA ====='
for pkg in "${required_packages[@]}"; do
    version="$(control_field "$pkg" Version)"
    [ "$version" = "4.1.3-1" ] && pass "$pkg version is 4.1.3-1" || fail "$pkg version is '$version'"

    arch="$(control_field "$pkg" Architecture)"
    if [ "$pkg" = "transmission-old-web" ]; then
        [ "$arch" = "all" ] && pass "$pkg architecture is all" || fail "$pkg architecture is '$arch'"
    else
        [ "$arch" = "armv7-3.2" ] && pass "$pkg architecture is armv7-3.2" || fail "$pkg architecture is '$arch'"
    fi
done

for pkg in transmission-old-daemon transmission-old-cli transmission-old-remote; do
    deps="$(control_field "$pkg" Depends)"
    echo "$deps" | grep -Eq '(^|, )transmission-old-runtime(,|$)' \
        && pass "$pkg depends on transmission-old-runtime" \
        || fail "$pkg does not depend on transmission-old-runtime"
done

webdeps="$(control_field transmission-old-web Depends)"
echo "$webdeps" | grep -Eq '(^|, )transmission-old-daemon(,|$)' \
    && pass 'transmission-old-web depends on transmission-old-daemon' \
    || fail 'transmission-old-web does not depend on transmission-old-daemon'

runtime_provides="$(control_field transmission-old-runtime Provides)"
for provided in libstdc++.so.6 libgcc_s.so.1 libatomic.so.1; do
    echo "$runtime_provides" | grep -Fq "$provided" \
        && pass "runtime advertises $provided" \
        || fail "runtime does not advertise $provided"
done

daemon_control="${PKGDIR[transmission-old-daemon]}/control"
grep -qx '/opt/etc/transmission/settings.json' "$daemon_control/conffiles" 2>/dev/null \
    && pass 'settings.json is protected as daemon conffile' \
    || fail 'settings.json is not protected as daemon conffile'

grep -qx 'Require-User: transmission=224:transmission=224' "$daemon_control/control" \
    && pass 'daemon keeps Entware transmission user metadata' \
    || fail 'daemon Require-User metadata changed'

for pkg in transmission-old-runtime transmission-old-cli transmission-old-remote transmission-old-web; do
    if grep -q '/opt/etc/transmission/settings.json' "${PKGDIR[$pkg]}/control/conffiles" 2>/dev/null; then
        fail "$pkg incorrectly owns settings.json as a conffile"
    else
        pass "$pkg does not claim settings.json as a conffile"
    fi
done

echo '===== EXACT PAYLOAD OWNERSHIP ====='
declare -A EXPECTED
EXPECTED[transmission-old-runtime]='/opt/lib/transmission-4.1/libatomic.so.1
/opt/lib/transmission-4.1/libatomic.so.1.2.0
/opt/lib/transmission-4.1/libgcc_s.so.1
/opt/lib/transmission-4.1/libstdc++.so.6
/opt/lib/transmission-4.1/libstdc++.so.6.0.33'
EXPECTED[transmission-old-daemon]='/opt/bin/transmission-daemon
/opt/etc/init.d/S88transmission
/opt/etc/sysctl.d/20-transmission.conf
/opt/etc/transmission/settings.json'
EXPECTED[transmission-old-cli]='/opt/bin/transmission-cli
/opt/bin/transmission-create
/opt/bin/transmission-edit
/opt/bin/transmission-show'
EXPECTED[transmission-old-remote]='/opt/bin/transmission-remote'
EXPECTED[transmission-old-web]='/opt/share/transmission/public_html/images/apple-touch-icon.png
/opt/share/transmission/public_html/images/favicon.ico
/opt/share/transmission/public_html/images/favicon.svg
/opt/share/transmission/public_html/index.html
/opt/share/transmission/public_html/transmission-app.css
/opt/share/transmission/public_html/transmission-app.css.LEGAL.txt
/opt/share/transmission/public_html/transmission-app.css.map
/opt/share/transmission/public_html/transmission-app.js
/opt/share/transmission/public_html/transmission-app.js.LEGAL.txt'

for pkg in "${required_packages[@]}"; do
    expected_file="$TMP/$pkg.expected"
    actual_file="$TMP/$pkg.actual"
    printf '%s\n' "${EXPECTED[$pkg]}" | sed '/^$/d' | sort > "$expected_file"
    payload_list "$pkg" > "$actual_file"

    if diff -u "$expected_file" "$actual_file"; then
        pass "$pkg payload ownership is exact"
    else
        fail "$pkg payload differs from expected split"
    fi
done

echo '===== UNION MATCHES VALIDATED ALL-IN-ONE ====='
ownership="$TMP/ownership.tsv"
: > "$ownership"
for pkg in "${required_packages[@]}"; do
    while IFS= read -r path; do
        printf '%s\t%s\n' "$path" "$pkg" >> "$ownership"
    done < <(payload_list "$pkg")
done

duplicates="$TMP/duplicates.txt"
cut -f1 "$ownership" | sort | uniq -d > "$duplicates"
if [ -s "$duplicates" ]; then
    cat "$duplicates" >&2
    fail 'payload files are duplicated across split packages'
else
    pass 'no payload file is duplicated across split packages'
fi

union="$TMP/union.txt"
cut -f1 "$ownership" | sort -u > "$union"
if diff -u "$REFERENCE_MANIFEST" "$union"; then
    pass 'five-package union exactly matches validated all-in-one payload manifest'
else
    fail 'five-package union differs from validated all-in-one payload manifest'
fi

echo '===== /opt CONTAINMENT ====='
for pkg in "${required_packages[@]}"; do
    data="${PKGDIR[$pkg]}/data"
    top="$(find "$data" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -u)"
    if [ "$top" = "opt" ]; then
        pass "$pkg writes only below /opt"
    else
        printf '%s\n' "$top" >&2
        fail "$pkg contains top-level payload outside /opt"
    fi
done

echo '===== PRIVATE GCC RUNTIME ====='
runtime_root="${PKGDIR[transmission-old-runtime]}/data/opt/lib/transmission-4.1"
for name in libstdc++.so.6 libstdc++.so.6.0.33 libgcc_s.so.1 libatomic.so.1 libatomic.so.1.2.0; do
    check_present transmission-old-runtime "/opt/lib/transmission-4.1/$name"
done

[ "$(readlink "$runtime_root/libstdc++.so.6" 2>/dev/null)" = "libstdc++.so.6.0.33" ] \
    && pass 'libstdc++.so.6 symlink target is exact' \
    || fail 'libstdc++.so.6 symlink target is unexpected'
[ "$(readlink "$runtime_root/libatomic.so.1" 2>/dev/null)" = "libatomic.so.1.2.0" ] \
    && pass 'libatomic.so.1 symlink target is exact' \
    || fail 'libatomic.so.1 symlink target is unexpected'

for pkg in "${required_packages[@]}"; do
    for global_runtime in libstdc++.so.6 libgcc_s.so.1 libatomic.so.1; do
        if [ -e "${PKGDIR[$pkg]}/data/opt/lib/$global_runtime" ] || [ -L "${PKGDIR[$pkg]}/data/opt/lib/$global_runtime" ]; then
            fail "$pkg leaks $global_runtime into global /opt/lib"
        fi
    done
done
[ "$failures" -ge 0 ] && pass 'no split package replaces Entware global GCC runtime' || true

echo '===== ARMV7 ELF / LOADER / RPATH ====='
declare -A BINPKG
BINPKG[transmission-daemon]=transmission-old-daemon
BINPKG[transmission-remote]=transmission-old-remote
BINPKG[transmission-cli]=transmission-old-cli
BINPKG[transmission-create]=transmission-old-cli
BINPKG[transmission-edit]=transmission-old-cli
BINPKG[transmission-show]=transmission-old-cli

req_versions="$TMP/required-cxx-versions.txt"
: > "$req_versions"

for name in transmission-daemon transmission-remote transmission-cli transmission-create transmission-edit transmission-show; do
    pkg="${BINPKG[$name]}"
    bin="${PKGDIR[$pkg]}/data/opt/bin/$name"
    check_present "$pkg" "/opt/bin/$name"
    [ -f "$bin" ] || continue

    info="$(file "$bin")"
    echo "$info"
    echo "$info" | grep -q 'ELF 32-bit.*ARM' \
        && pass "$name is a 32-bit ARM ELF" \
        || fail "$name is not a 32-bit ARM ELF"

    hdr="$(readelf -h "$bin")"
    echo "$hdr" | grep -q 'Machine:.*ARM' \
        && pass "$name ELF machine is ARM" \
        || fail "$name ELF machine is not ARM"
    echo "$hdr" | grep -q 'soft-float ABI' \
        && pass "$name uses soft-float ABI" \
        || fail "$name does not advertise soft-float ABI"

    interp="$(readelf -l "$bin" | grep 'Requesting program interpreter' || true)"
    echo "$interp"
    echo "$interp" | grep -q '/opt/lib/ld-linux.so.3' \
        && pass "$name uses Entware ARM loader" \
        || fail "$name does not use /opt/lib/ld-linux.so.3"

    dynpath="$(readelf -d "$bin" | grep -E '\((RPATH|RUNPATH)\)' || true)"
    echo "$dynpath"
    echo "$dynpath" | grep -Eq '\(RPATH\).*Library rpath: \[/opt/lib/transmission-4\.1\]$' \
        && pass "$name has exact private Transmission RPATH" \
        || fail "$name RPATH is not exactly /opt/lib/transmission-4.1"

    strings "$bin" 2>/dev/null \
        | grep -E '^(GLIBCXX|CXXABI)_[0-9A-Za-z_.]+$' >> "$req_versions" || true
done
sort -u -o "$req_versions" "$req_versions"

echo '===== DAEMON NEEDED LIBRARIES ====='
readelf -d "${PKGDIR[transmission-old-daemon]}/data/opt/bin/transmission-daemon" | grep NEEDED || true

echo '===== INIT / WEB / CONFIG ====='
daemon_data="${PKGDIR[transmission-old-daemon]}/data"
grep -q 'ARGS="-g /opt/etc/transmission"' "$daemon_data/opt/etc/init.d/S88transmission" \
    && pass 'init script uses /opt/etc/transmission' \
    || fail 'init script config directory changed'
grep -q 'TRANSMISSION_WEB_HOME="/opt/share/transmission/public_html"' "$daemon_data/opt/etc/init.d/S88transmission" \
    && pass 'init script web path unchanged' \
    || fail 'init script web path changed'
check_present transmission-old-web '/opt/share/transmission/public_html/index.html'
check_present transmission-old-daemon '/opt/etc/transmission/settings.json'

echo '===== GLIBC COMPATIBILITY ====='
glibc_versions="$(
    strings \
      "$runtime_root/libstdc++.so.6.0.33" \
      "$runtime_root/libgcc_s.so.1" \
      "$runtime_root/libatomic.so.1.2.0" \
      2>/dev/null | grep -oE 'GLIBC_[0-9]+(\.[0-9]+)+' | sort -Vu || true
)"
printf '%s\n' "$glibc_versions"
max_glibc="$(printf '%s\n' "$glibc_versions" | tail -n 1)"
if [ -z "$max_glibc" ]; then
    fail 'could not determine GLIBC requirements of private runtime'
elif [ "$(printf '%s\n' "$max_glibc" GLIBC_2.27 | sort -V | tail -n 1)" = "GLIBC_2.27" ]; then
    pass "private runtime GLIBC requirement is <= 2.27 (max: $max_glibc)"
else
    fail "private runtime requires newer than GLIBC 2.27 (max: $max_glibc)"
fi

echo '===== C++ ABI COVERAGE ====='
provided_versions="$TMP/provided-cxx-versions.txt"
missing_versions="$TMP/missing-cxx-versions.txt"
strings "$runtime_root/libstdc++.so.6.0.33" 2>/dev/null \
    | grep -E '^(GLIBCXX|CXXABI)_[0-9A-Za-z_.]+$' | sort -u > "$provided_versions" || true
comm -23 "$req_versions" "$provided_versions" > "$missing_versions" || true

echo 'Required:'
cat "$req_versions"
if [ -s "$missing_versions" ]; then
    echo 'Missing:' >&2
    cat "$missing_versions" >&2
    fail 'private libstdc++ does not satisfy every requested GLIBCXX/CXXABI version'
else
    pass 'private libstdc++ satisfies every GLIBCXX/CXXABI version requested by all six binaries'
fi

echo '===== SIZE SUMMARY ====='
total_ipk=0
total_installed=0
for pkg in "${required_packages[@]}"; do
    ipk="${IPKPATH[$pkg]}"
    ipk_size="$(stat -c '%s' "$ipk")"
    installed="$(control_field "$pkg" Installed-Size)"
    printf '%-28s IPK=%10s  Installed-Size=%10s\n' "$pkg" "$ipk_size" "$installed"
    total_ipk=$((total_ipk + ipk_size))
    total_installed=$((total_installed + installed))
done
printf '%-28s IPK=%10s  Installed-Size=%10s\n' TOTAL "$total_ipk" "$total_installed"

if [ "$failures" -ne 0 ]; then
    echo "VALIDATION FAILED: $failures check(s) failed." >&2
    exit 1
fi

echo 'VALIDATION PASSED: all split-package static checks succeeded.'

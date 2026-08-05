#!/usr/bin/env bash
#
# Detect macOS keychain certificates that OpenSSL cannot parse.
#
# WHY THIS EXISTS
#
# The Matter SDK builds with pigweed, whose CIPD-provided Python ships a
# Chromium-patched ssl.py. On macOS that patch replaces
# SSLContext.set_default_verify_paths() with a function that dumps EVERY
# certificate in your keychain search list into one concatenated PEM blob and
# loads it in a single load_verify_locations(cadata=...) call.
#
# OpenSSL parses that blob all-or-nothing. So a single malformed certificate
# anywhere in your keychain breaks ALL default TLS in that Python, and the only
# symptom is:
#
#     ssl.SSLError: [PEM] ASN1 lib (_ssl.c:4030)
#
# which names neither the certificate nor the keychain. Bootstrap then fails at
# "Setting up Python environment" and it looks like the SDK does not build on
# macOS. It does. You have one bad certificate.
#
# The patched code also ignores SSL_CERT_FILE, so the usual "export a CA bundle"
# workaround does nothing, which sends people even further down the wrong path.
#
# Certificates like this are not exotic: any self-signed cert with a negative
# serial number (a leading 0xFF byte, violating RFC 5280 4.1.2.2) will do it,
# and those arrive routinely attached to S/MIME-signed email.
#
# This script finds the offender and prints the exact command to remove it.
#
# Usage:
#   check-macos-keychain-certs.sh [keychain ...]
#
# With no arguments it checks the real search list, which is what pigweed's
# ssl.py enumerates. Explicit keychain paths override that, which lets you test
# this script (or vet a single keychain) without touching your search list.
#
# Exit status: 0 = all certificates parse, 1 = at least one is unparseable.

set -uo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
    echo "not macOS; nothing to check"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ "$#" -gt 0 ]; then
    keychains="$(printf '%s\n' "$@")"
else
    # The search list pigweed's ssl.py enumerates: your keychains plus the
    # system root store it explicitly appends.
    keychains="$(security list-keychains 2>/dev/null | tr -d '"' | sed 's/^ *//;s/ *$//')"
    keychains="${keychains}
/System/Library/Keychains/SystemRootCertificates.keychain"
fi

total=0
bad_total=0

while IFS= read -r kc; do
    [ -n "$kc" ] || continue
    [ -r "$kc" ] || continue

    security find-certificate -a -p "$kc" >"$tmp/all.pem" 2>/dev/null || continue
    [ -s "$tmp/all.pem" ] || continue

    rm -f "$tmp"/cert-*.pem
    awk -v dir="$tmp" '
        /-----BEGIN CERTIFICATE-----/ { n++ }
        n > 0 { print > (dir "/cert-" n ".pem") }
    ' "$tmp/all.pem"

    for f in "$tmp"/cert-*.pem; do
        [ -e "$f" ] || continue
        total=$((total + 1))

        if openssl x509 -in "$f" -noout 2>/dev/null; then
            continue
        fi

        bad_total=$((bad_total + 1))

        # Unparseable as X.509, so identify it the hard way: recover the DER,
        # fingerprint it, and dig a human-readable name out of the raw ASN.1.
        # -A is required: without it openssl rejects the single long line that
        # stripping newlines produces, and silently yields an empty file (whose
        # SHA-1 is the famous da39a3ee... of the empty string).
        sed -e '1d' -e '$d' "$f" | tr -d '\n' \
            | openssl base64 -d -A >"$tmp/bad.der" 2>/dev/null
        sha1="$(shasum -a 1 "$tmp/bad.der" 2>/dev/null | awk '{print toupper($1)}')"
        label="$(openssl asn1parse -inform DER -in "$tmp/bad.der" 2>/dev/null \
                 | grep -E 'PRINTABLESTRING|UTF8STRING|IA5STRING' \
                 | head -3 | sed 's/.*://' | paste -sd' / ' - )"
        # Strip the temp-file path out of openssl's message; it is noise to the
        # reader and changes every run.
        reason="$(openssl x509 -in "$f" -noout 2>&1 | head -1 \
                  | sed -e "s| from $f||" -e 's|[[:space:]]*$||')"

        echo "UNPARSEABLE CERTIFICATE"
        echo "  keychain : $kc"
        echo "  identity : ${label:-<could not decode>}"
        echo "  sha1     : ${sha1:-<unknown>}"
        echo "  openssl  : $reason"
        if openssl asn1parse -inform DER -in "$tmp/bad.der" 2>/dev/null \
           | grep -q 'BAD INTEGER'; then
            echo "  cause    : malformed serial number (negative INTEGER);" \
                 "RFC 5280 4.1.2.2 requires a positive value"
        fi
        if [ -n "${sha1:-}" ]; then
            echo "  fix      : security delete-certificate -Z $sha1 '$kc'"
            echo "             (back it up first if you may need it:"
            echo "              security find-certificate -a -Z -p '$kc' > ~/keychain-backup.pem)"
        fi
        echo
    done
done <<EOF
$keychains
EOF

if [ "$bad_total" -eq 0 ]; then
    echo "OK: all $total keychain certificates parse cleanly"
    exit 0
fi

echo "FOUND $bad_total unparseable certificate(s) out of $total."
echo "Until removed, pigweed's Python will fail with 'ssl.SSLError: [PEM] ASN1 lib'"
echo "and the SDK bootstrap will not complete."
exit 1

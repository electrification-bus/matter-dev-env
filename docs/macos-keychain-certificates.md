# A bad certificate in your macOS keychain breaks the SDK bootstrap

This is an edge case, but it is worth its own page because the symptom points nowhere near the cause, the obvious workaround does not work, and the natural conclusion ("the Matter SDK does not build on macOS") is wrong.

If you are not seeing an SSL error, you do not need this page. `matter-dev-env` checks for the problem automatically during preflight.

## The symptom

`source scripts/bootstrap.sh` in the SDK fails at the "Setting up Python environment" step with:

```
ssl.SSLError: [PEM] ASN1 lib (_ssl.c:4030)
```

The traceback ends inside pigweed's Python, in `ssl.py`, at `load_verify_locations`. It names neither a certificate nor a keychain. Anything else that uses that Python's default TLS fails the same way.

## The cause

The SDK builds with [pigweed](https://pigweed.dev/), which supplies its own Python through CIPD rather than using yours. That interpreter is a Chromium build, and it ships a **patched `ssl.py`**.

On macOS the patch replaces `SSLContext.set_default_verify_paths()` with a function (`_darwin_synthesize_cert_pem`) that:

1. Enumerates **every** certificate in your keychain search list, plus the system root store, via Security.framework.
2. Concatenates all of them into a single PEM blob.
3. Loads that blob in one `load_verify_locations(cadata=...)` call.

OpenSSL parses that blob all-or-nothing. So **one** malformed certificate anywhere in your keychain invalidates the entire bundle, and the interpreter ends up with no trusted CAs at all rather than the 200-odd it should have.

The certificate does not have to be one you care about, or one you knowingly installed. Any self-signed certificate with a **negative serial number** (a leading `0xFF` byte, which violates [RFC 5280 section 4.1.2.2](https://www.rfc-editor.org/rfc/rfc5280#section-4.1.2.2)) will do it, and both OpenSSL 1.1.1 and 3.x reject those. Certificates like that arrive routinely attached to S/MIME-signed email and get added to your login keychain without ceremony.

## Why the obvious workaround does not work

The usual fix for "Python cannot find CA certificates on macOS" is to export a bundle and point `SSL_CERT_FILE` at it. That does nothing here.

The patched `set_default_verify_paths()` never consults `SSL_CERT_FILE`, `SSL_CERT_DIR`, or any other environment variable. It goes straight to the keychain. You can verify this yourself:

```bash
SSL_CERT_FILE=/path/to/good/bundle.pem \
  .environment/cipd/packages/pigweed/bin/python3.11 \
  -c "import ssl; ssl.create_default_context()"
```

That still raises the same error. Time spent on `SSL_CERT_FILE` is time wasted, which is part of why this problem eats afternoons.

## Diagnosing it

`matter-dev-env` installs the detector as a standalone command during preflight:

```bash
matter-check-keychain-certs
```

It walks the same keychain search list the patched `ssl.py` walks, tries to parse each certificate individually, and reports any that fail:

```
UNPARSEABLE CERTIFICATE
  keychain : /Users/you/Library/Keychains/login.keychain-db
  identity : Some Person somebody@example.edu/US
  sha1     : 0EF00C53D5EB41F53A31D3DD4961E0995C479C1D
  openssl  : Could not find or decode certificate
  cause    : malformed serial number (negative INTEGER); RFC 5280 4.1.2.2 requires a positive value
  fix      : security delete-certificate -Z 0EF00C53... '/Users/you/Library/Keychains/login.keychain-db'
```

Exit status is 0 when everything parses and 1 when something does not, so it is usable in scripts.

You can also point it at specific keychains instead of the live search list, which is handy for vetting one keychain without touching anything:

```bash
matter-check-keychain-certs ~/Library/Keychains/login.keychain-db
```

## Fixing it

Back the certificate up first if there is any chance you need it later:

```bash
security find-certificate -a -Z -p ~/Library/Keychains/login.keychain-db > ~/keychain-backup.pem
```

Then delete it by fingerprint, using the exact command the detector printed:

```bash
security delete-certificate -Z <SHA-1> ~/Library/Keychains/login.keychain-db
```

Confirm the fix. A fresh process re-reads the keychain, so no restart is needed:

```bash
matter-check-keychain-certs
# then, in the SDK:
.environment/cipd/packages/pigweed/bin/python3.11 \
  -c "import ssl; c=ssl.create_default_context(); print(len(c.get_ca_certs()), 'CA certs')"
```

A healthy result is a couple of hundred CA certificates. Bootstrap will then complete normally.

If deleting the certificate is not acceptable in your environment, the alternative is a `sitecustomize.py` on `PYTHONPATH` that re-overrides `SSLContext.set_default_verify_paths()` to load a known-good bundle. That works, but it has to be applied to every process in the build, so removing the bad certificate is much less trouble.

## Is this a bug?

Partly yours, partly upstream. The malformed certificate really is malformed. But failing the **whole** bundle rather than skipping the certificates it cannot parse is a robustness bug in the patched `ssl.py`: it turns one junk certificate in a user's keychain into a total, undiagnosable TLS failure. The same code on Linux reads a CA file from a well-known path and has no equivalent failure mode.

If you hit this, it is worth reporting upstream, since the fix (skip and warn, rather than fail the bundle) would save the next person the same afternoon.

## Related

- Preflight implements this check in [`roles/preflight/files/check-macos-keychain-certs.sh`](../roles/preflight/files/check-macos-keychain-certs.sh); its header comment carries the same explanation for anyone reading the code.
- Back to the [README](../README.md).

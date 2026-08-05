# matter-dev-env

Ansible automation that stands up a complete [Matter](https://csa-iot.org/all-solutions/matter/) SDK development environment: clones and maintains the repositories, installs the tools, bootstraps the SDK build environment, and optionally builds an example app and proves the result works by running a real certification test against it.

Works on **macOS** and **Debian/Ubuntu**, against **your own machine** (the default) or **any reachable host**.

## Why this exists

Setup instructions for Matter development are usually a wall of shell commands in a document. That form has predictable problems: it goes stale silently, it is not idempotent so you cannot safely re-run it, it fails in the middle and leaves you halfway, and every developer ends up with a subtly different environment. Worse, it encodes none of the hard-won knowledge about *why* a step is there, so the first unusual failure sends you back to square one.

This repo is an argument that setup should be executable, idempotent, self-checking, and re-runnable on a machine you are actively working on. Concretely:

- **It checks before it works.** Preflight catches the problems that would otherwise surface forty minutes into a build: not enough disk, wrong Python, missing Xcode tools, no SSH access to the repos you asked for.
- **It never destroys your work.** The repository role fast-forwards clean branches and leaves anything dirty or diverged strictly alone, then tells you which. No hard reset, no force checkout, no clean. It is safe to run every morning against a tree you are mid-change in.
- **It encodes the traps.** Several checks exist because the failure they catch is genuinely undiagnosable otherwise. The [macOS keychain certificate check](docs/macos-keychain-certificates.md) is the clearest example.
- **It proves it worked.** With `--tags build` it does not just install things, it builds an example app, builds the Python controller, commissions the app and runs a real certification test against it.

## Quick start

You need [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) (a virtualenv or `pipx install ansible` is fine) and `git`.

```bash
git clone https://github.com/electrification-bus/matter-dev-env.git
cd matter-dev-env

# Only needed if you already have ANSIBLE_CONFIG exported for another project.
source setup-env.sh

ansible-playbook setup.yml --tags preflight   # check this machine, change nothing
ansible-playbook setup.yml                    # do it
```

That gives you the SDK cloned, submodules checked out for your platform, the pigweed environment bootstrapped, and alchemy installed. Then:

```bash
cd ~/matter/connectedhomeip && source scripts/activate.sh
```

To also build and smoke-test, which takes several more minutes but proves the environment genuinely works:

```bash
ansible-playbook setup.yml --tags build
```

## What it does

| Role | What it does | Tag |
|------|--------------|-----|
| `preflight` | Verifies the machine can actually do this: supported OS, disk space, Python version, Xcode command line tools, GitHub SSH access for any private repos, and unparseable macOS keychain certificates. Reports every problem at once rather than one per run. | `preflight` |
| `platform_deps` | OS packages. The apt list mirrors the SDK's own `docs/guides/BUILDING.md`. On macOS this is deliberately almost empty, because the SDK only asks for Xcode there. | `deps` |
| `repos` | Clones and maintains the configured repositories under one root. Fast-forward only; never discards local work. | `repos` |
| `toolchain` | SDK submodules for your platform, the pigweed bootstrap, alchemy, and optionally the ZAP release. | `toolchain` |
| `build` | Optional: build an example app, build the Python controller, then commission the app and run a certification test against it. | `build` |

Any tag can be run on its own, and `--check` gives you a dry run.

## Two audiences: public-only, and CSA members

Matter development splits into two cases that need different repositories. This is the one thing worth deciding before your first run, and it is a single setting.

**Building products, integrations, or applications** (the large majority). Everything you need is public: the SDK itself, its example apps, the Python controller and certification test scripts, alchemy, and ZAP. This is the **default**, it requires no GitHub credentials at all, and preflight will not ask for any.

```bash
ansible-playbook setup.yml    # nothing to configure
```

**Developing the standard itself**: authoring specification text, adding clusters or device types, writing certification test plans. That additionally needs the CSA members-only repositories, which require both [CSA](https://csa-iot.org/) participating membership and your SSH key registered with GitHub. Turn it on with one key in your `host_vars`:

```yaml
matter_csa_member: true
```

| Repository | Public | Needed for | Default |
|---|---|---|---|
| `connectedhomeip` (the SDK) | yes | everything | on |
| `alchemy` | yes | generating SDK artifacts from spec sources | on |
| `zap` | yes | the ZAP GUI from source | off |
| `connectedhomeip-doc` | yes | grep-able rendered SDK docs | off |
| `connectedhomeip-spec` | **no** | authoring specification text | CSA members |
| `chip-test-plans` | **no** | authoring certification test plans | CSA members |

`matter_csa_member` reflects access you already have; it is not a way to obtain it. Set it without membership and preflight says so plainly, before anything is cloned, rather than letting a `git clone` fail with an opaque permission error partway through the run. The members-only entries use SSH URLs deliberately, so they fail cleanly instead of prompting for credentials.

Anything in that table can be overridden individually with `matter_repos_enable` and `matter_repos_disable`, whatever your membership.

## Configuration

All configuration lives in [`group_vars/all.yml`](group_vars/all.yml), which is heavily commented and is the only file most people need to read. The defaults stand up a working environment as-is.

### Your personal configuration

Do not edit `group_vars/all.yml` for your own settings. Copy the template instead:

```bash
mkdir -p host_vars
cp examples/host_vars/localhost.yml host_vars/localhost.yml
$EDITOR host_vars/localhost.yml
```

Ansible loads `host_vars/<inventory_hostname>.yml` automatically and it takes precedence over `group_vars/all.yml`. Put **only** the values that differ from the defaults in it; everything you leave out keeps tracking upstream, which is the whole point.

The entire `host_vars/` directory is gitignored, so your personal paths can never be committed by accident and `git pull` never conflicts with them. The tracked template lives at `examples/host_vars/localhost.yml`, well away from the live directory, so there is no negation-pattern subtlety to get wrong. One consequence worth knowing: because the directory is ignored, `git clean -xfd` will delete your `host_vars/` file along with other ignored files.

For a machine other than this one, name the file after the inventory host, for example `host_vars/devbox.local.yml`. Anything can also be set for a single run with `-e`, for example `ansible-playbook setup.yml -e matter_root=/opt/matter`, which overrides everything else.

### AI coding agent context

This repo ships a [`CLAUDE.md`](CLAUDE.md): shared, project-specific context for [Claude Code](https://claude.com/claude-code) and similar agents. Checking it in is deliberate. It carries facts about *this project* that are useful to anyone working on it and are not inferable from the code: the repository safety contract an agent must never break, the `ANSIBLE_CONFIG` trap, the lint conventions, and how to test the repos role without touching real clones. Historically that file was often kept out of public repos; the more useful convention is to share the project facts and keep the personal parts separate, which is what this repo does.

**Keep your own agent configuration out of it.** Two places to put personal context, both gitignored here:

| File | Scope | Committed |
|---|---|---|
| `CLAUDE.md` | This project, shared with everyone | **yes** |
| `CLAUDE.local.md` | This project, just you | no, gitignored |
| `~/.claude/CLAUDE.md` | You, across every project | not part of any repo |

So personal preferences (your editor, your shell quirks, how you like commit messages written, paths on your machine) belong in `CLAUDE.local.md` or your user-level file. Project facts that would help the next contributor belong in `CLAUDE.md`, and a pull request improving it is as welcome as one improving the code.

`AGENTS.local.md` is gitignored on the same basis, for tools that read `AGENTS.md` instead.

One gotcha worth knowing if you contribute: **many developers globally gitignore `CLAUDE.md` and `AGENTS.md`** to keep AI context out of published repos. If you are one of them, that global rule silently drops the file from your commits with no error. This repo's `.gitignore` carries an explicit `!CLAUDE.md` and `!AGENTS.md` to override it, so the shared file survives. Worth checking your own repos for the same silent omission.

### The settings you are most likely to change

- `matter_root`: where every repository is cloned. Defaults to `~/matter`. Point it at a tree you already have and the repos role will adopt those clones rather than re-cloning, under the safety contract below.
- `matter_repos_enable` / `matter_repos_disable` / `matter_repos_extra`: turn individual repositories on or off, or add your own, **without copying the whole `matter_repos` list**. YAML lists do not merge, so redefining `matter_repos` to flip one flag would force you to paste the entire list and keep it in sync forever. These three are merged against the defaults by name instead. A CSA member's entire personal config can be one key:

  ```yaml
  matter_repos_enable: [connectedhomeip-spec, chip-test-plans]
  ```

  Disable wins over enable if a name appears in both, so the safe outcome survives a config mistake.
- `matter_submodule_platforms`: which platforms' submodules to check out. The SDK has around 78 submodules and you rarely want all of them; this defaults to just the platform you are provisioning.
- `matter_build_example` / `matter_build_python_controller` / `matter_smoke_test`: off by default, all enabled at once by `--tags build`.

A repository's `version:` applies when it is **cloned**. On an existing clone the role fast-forwards whatever branch you are on and never switches branches, because switching would disrupt work in progress. To move an existing clone to a different branch, check it out yourself.

## Provisioning another machine

The default inventory is this machine over a local connection, with nothing to configure. To provision something else, add it to `inventory.ini` and use `-l`:

```ini
[matter_dev]
localhost     ansible_connection=local
devbox.local  ansible_user=you
```

```bash
ansible-playbook setup.yml -l devbox.local
```

Nothing else changes. The roles do not care whether they are running locally or over SSH.

## The repository safety contract

This is the part that makes the tool safe to re-run against a tree you are working in, so it is worth stating precisely. For each configured repository:

- **Absent** → cloned at the configured version.
- **Present and clean and behind** → fast-forwarded, and told so.
- **Present with local modifications** → fetched only. Working tree untouched, reported as `SKIPPED (local changes)`.
- **Present and diverged** (local commits *and* upstream commits) → fetched only, reported as `SKIPPED (diverged: N ahead, M behind)`. Rebase or merge it yourself.
- **Present and ahead** → nothing to pull, reported as such.

There is no code path that runs `git reset --hard`, `git checkout --force`, or `git clean`. Set `matter_repos_update: fetch-only` to never move a working tree at all, or `none` to leave existing clones completely alone.

## Troubleshooting

- **macOS: bootstrap fails with `ssl.SSLError: [PEM] ASN1 lib`.** One malformed certificate in your keychain breaks all TLS in pigweed's Python, and `SSL_CERT_FILE` does not help. Preflight detects it and names the offender; see [docs/macos-keychain-certificates.md](docs/macos-keychain-certificates.md) for the full explanation and the fix. You can re-run the detector any time with `matter-check-keychain-certs`.
- **`ansible-playbook` cannot find the inventory.** You probably have `ANSIBLE_CONFIG` exported for another project, which wins over this repo's `ansible.cfg`. Run `source setup-env.sh` first.
- **A repository was not updated.** That is by design if it has local changes or has diverged; the run summary says which and why. See the safety contract above.

## Reference

| Path | Purpose |
|------|---------|
| `setup.yml` | The entry point. Runs the roles in order, with tags. |
| `group_vars/all.yml` | All user configuration, heavily commented. |
| `examples/host_vars/localhost.yml` | Template for your personal overrides. Copy it into `host_vars/`, which is gitignored in full. |
| `inventory.ini` | Hosts. Defaults to this machine over a local connection. |
| `ansible.cfg` | Connection defaults; keeps SSH alive through long builds. |
| `setup-env.sh` | Source this if you already export `ANSIBLE_CONFIG` for another project. |
| `roles/preflight/` | Pre-run checks, including the keychain certificate detector. |
| `roles/platform_deps/` | OS packages, per platform. |
| `roles/repos/` | Clone and fast-forward, under the safety contract above. |
| `roles/toolchain/` | Submodules, pigweed bootstrap, alchemy, ZAP. |
| `roles/build/` | Example app, Python controller, smoke test. |
| `docs/macos-keychain-certificates.md` | Why one bad keychain certificate breaks the SDK bootstrap on macOS, and how to fix it. |
| `CLAUDE.md` | Shared project context for AI coding agents. Personal agent config goes in the gitignored `CLAUDE.local.md`. |
| `CONTRIBUTING.md` | How to get involved; Discussions versus Issues; how to add a preflight check. |

## Status and contributing

Working and in daily use on macOS (Apple Silicon). The Debian/Ubuntu package paths follow the SDK's own documented list and the same logic proven on Raspberry Pi test-event hosts, but have had less mileage than the macOS path; reports welcome.

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to get involved, including when to open a [Discussion](https://github.com/electrification-bus/matter-dev-env/discussions) versus an [Issue](https://github.com/electrification-bus/matter-dev-env/issues).

The most valuable contribution is usually a new **preflight check**. If a Matter setup problem cost you an afternoon, encoding it in `roles/preflight/` means it costs the next person thirty seconds. Questions about Matter SDK setup are welcome in Discussions even when they do not turn into a change here.

This project is not affiliated with the Connectivity Standards Alliance or the connectedhomeip project. It automates their documented setup rather than replacing it.

## License

Apache-2.0, matching [connectedhomeip](https://github.com/project-chip/connectedhomeip) and [alchemy](https://github.com/project-chip/alchemy). See [LICENSE](LICENSE).

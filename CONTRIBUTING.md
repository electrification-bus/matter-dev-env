# Contributing

Thanks for your interest in contributing. `matter-dev-env` is Ansible automation that stands up a [Matter](https://csa-iot.org/all-solutions/matter/) SDK development environment: repositories, tools, the pigweed build environment, and an optional build plus certification smoke test. It exists partly to be useful and partly to make an argument: setup should be executable, idempotent, self-checking, and safe to re-run on a machine you are actively working on.

The most valuable contributions are usually not new features. They are **preflight checks**. If a Matter setup problem cost you an afternoon, encoding it here means it costs the next person thirty seconds.

## How to contribute

### Discussions

Use [Discussions](https://github.com/electrification-bus/matter-dev-env/discussions) for:

- Open-ended questions about scope ("should this manage the certification-tool / Test Harness too, or is that a different repo?")
- Support for a new platform (Fedora, Arch, WSL, a container image) before writing it, since each one is a real maintenance commitment
- "Is this failure worth a preflight check?" when you are not yet sure it generalises beyond your machine
- Anything about Matter SDK setup itself, even if it turns out not to be a change here. Shared debugging is the point.

Discussions are open-ended and a good place to align on direction before something becomes a concrete change. Aligned outcomes often turn into one or more Issues or pull requests.

### Issues

Use [Issues](https://github.com/electrification-bus/matter-dev-env/issues) for actionable changes:

- A role failing on a specific OS and version, with the `ansible-playbook` output and your `ansible --version`
- A concrete preflight check to add, with the symptom it catches and how to detect it
- Upstream drift: the SDK changed a script name, a package list, or a release asset naming scheme, and something here needs to follow
- Documentation gaps where a specific change is intended
- Discussion outcomes that have alignment and a clear scope

If you are not sure whether something is an Issue or a Discussion, start with a Discussion. We can convert it later.

### Pull requests

Pull requests are welcome.

- For small fixes (typos, a package added to the apt list, a corrected upstream path, a clearer failure message) open a PR directly.
- For substantive changes (a new role, a new supported platform, anything that changes the repository safety contract) open a Discussion or Issue first so we can align on scope before you invest the effort.
- **Never weaken the safety contract.** No code path may run `git reset --hard`, `git checkout --force`, `git clean`, or `ansible.builtin.git` with `force: true` against an existing clone. People run this against trees they are mid-change in, and that promise is the reason they can. If you think you need an exception, open a Discussion first.
- **Cite upstream for anything you copy.** Package lists, script invocations, and build flags should say in a comment where they came from (for example `docs/guides/BUILDING.md`), so the next person can check whether upstream has moved.
- **Comment the why, not the what.** The house style is heavier comments than most Ansible, but only for non-obvious *why*: a hidden constraint, an upstream quirk, the reason a check exists. Do not add comments that restate the task name.
- **Everything user-facing goes in `group_vars/all.yml`.** New behavior should be configurable there, with a comment explaining the tradeoff, and should default to whatever is safe and fast.
- **`CLAUDE.md` is shared; keep personal agent config out of it.** That file carries project facts for AI coding agents (the safety contract, the lint conventions, how to test without touching real clones). Improving it is as welcome as improving the code. Your own preferences go in `CLAUDE.local.md` or `~/.claude/CLAUDE.md`, both of which stay out of this repo. If you globally gitignore `CLAUDE.md`, note that this repo overrides that with `!CLAUDE.md`, so your edits to it will be committed.
- One commit per logical change is fine. We do not require squash or any particular branch naming.

## Adding a preflight check

This is the highest-value contribution, so it gets its own section. A good check:

1. Catches something **before** it wastes time, rather than diagnosing it afterwards.
2. Produces a message that names the actual problem **and the fix**, ideally a command the reader can paste. Compare "SSL error" against naming the offending certificate, its SHA-1, why OpenSSL rejects it, and the exact `security delete-certificate` line.
3. Appends to `preflight_problems` rather than failing immediately, so one run reports everything wrong instead of one problem per run.
4. Is skipped cleanly on platforms where it does not apply.

If the detection logic is more than a few lines of shell, put it in `roles/preflight/files/` as a standalone script and install it into `matter_bin_dir` as well, so people can re-run the diagnosis without the playbook. `check-macos-keychain-certs.sh` is the worked example: read its header comment for the level of explanation to aim for.

## Quality gates

Run before opening a PR:

```bash
ansible-lint                              # must be clean, no new noqa without justification
ansible-playbook setup.yml --syntax-check
markdownlint-cli2 '**/*.md'               # if you touched docs
```

`ansible-lint` currently passes with zero findings. If you must add a `# noqa`, add a comment above the task explaining why the rule genuinely does not apply. There are three today, each for the same reason: `ansible.builtin.git` cannot express "fetch, then fast-forward only if the tree is clean and has not diverged", which is exactly the guarantee this repo makes.

## Testing

There is no CI test suite yet, because the honest unit of test here is "a real machine". Test what you touch:

**Any change**: `ansible-playbook setup.yml --tags preflight` should pass, and running it twice should report `changed=0` the second time. Idempotence is not optional.

**Changes to the `repos` role**: do not test against your real clones. Build throwaway fixtures with a local bare repo as the origin, put them into each interesting state, run the role, then assert that nothing was lost:

```bash
# a bare "upstream", plus clones left behind / dirty / ahead
# then run the role against them:
ansible-playbook setup.yml --tags repos -e matter_root=/tmp/fixtures/root \
  -e '{"matter_repos":[{"name":"dirty","url":"/tmp/fixtures/origin.git","version":"master","enabled":true}]}'
```

The behavior to verify: `behind` fast-forwards, `dirty` is untouched with its edits intact, `ahead` keeps its local commits, a diverged repo is reported and not merged, and an absent one is cloned.

**Changes to `platform_deps` or `toolchain`**: state which OS and version you ran it on in the PR. A clean container or VM is ideal, since it catches the "worked because it was already installed" class of bug.

**Changes that could affect a real build**: `ansible-playbook setup.yml --tags build` runs the full path and ends by commissioning an example app and running a real certification test against it. It takes several minutes and is the strongest signal available.

## Platform support

macOS and Debian/Ubuntu today. Adding a platform means adding a `roles/platform_deps/tasks/<os>.yml`, teaching `preflight` what "supported" means, and committing to keep it working. Open a Discussion first: an unmaintained platform path is worse than an honest "not supported yet".

## Relationship to upstream

This repo is not affiliated with the Connectivity Standards Alliance or the [connectedhomeip](https://github.com/project-chip/connectedhomeip) project. It automates *their* documented setup and follows their instructions rather than replacing them. When upstream and this repo disagree, upstream is right and this is a bug.

If a fix belongs upstream (a genuine SDK bug, a wrong instruction in `BUILDING.md`) please send it there too. Everyone benefits more from that than from a workaround here, and a workaround we can delete later is the best kind.

## Code of conduct

Be respectful and constructive. We appreciate everyone who takes the time to file an issue, start a discussion, or send a pull request.

## License

By contributing you agree that your contributions are licensed under the [Apache-2.0 License](LICENSE) that covers this project.

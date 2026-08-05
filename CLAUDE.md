# Guidance for AI coding agents

Shared, project-specific context for Claude Code and similar tools. It is checked in deliberately, because everything here is useful to anyone working on this repo and most of it is not inferable from the code alone.

**Keep personal preferences out of this file.** Put those in `CLAUDE.local.md`, which is gitignored, or in your user-level `~/.claude/CLAUDE.md`. This file is for facts about the project, not about you.

## What this is

Ansible automation that stands up a Matter SDK development environment: clones repositories, installs tools, bootstraps the SDK build environment, and optionally builds an example app and runs a real certification test to prove the result works. It targets `localhost` by default and any reachable host otherwise, on macOS and Debian/Ubuntu.

Read `README.md` for what it does and `group_vars/all.yml` for every setting. Those two are the source of truth; this file only covers how to work on the code.

## The one rule that must not be broken

**The repos role must never be able to destroy a user's work.** No code path may introduce `git reset --hard`, `git checkout --force`, `git clean`, `git pull` with rebase/merge that could conflict, or `ansible.builtin.git` with `force: true` against an existing clone.

Updating is strictly: fetch, then fast-forward **only** when the tree is clean, has an upstream, and has not diverged. Anything else is reported and left alone. People run this against trees they are mid-change in, and that promise is the only reason it is safe to do so.

This is the most likely thing for an agent to "helpfully" break while making the role seem more capable. Do not. If a change seems to require it, stop and ask.

Related invariant: a repo's `version:` applies at clone time only. Existing clones are never switched to another branch.

## Running anything

`ANSIBLE_CONFIG` exported for another project silently wins over this repo's `ansible.cfg`, and then the inventory is not found and `matter_dev` "does not match". Always either:

```bash
source setup-env.sh                          # sets ANSIBLE_CONFIG to this repo
# or prefix every command:
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook setup.yml --tags preflight
```

Useful invocations:

```bash
ansible-playbook setup.yml --tags preflight   # read-only, safe anywhere
ansible-playbook setup.yml --tags repos       # clone/update only
ansible-playbook setup.yml --check            # dry run
```

## Quality gates

All three must pass before proposing a change:

```bash
ansible-lint                                  # currently ZERO findings; keep it that way
ansible-playbook setup.yml --syntax-check
markdownlint-cli2 '**/*.md'                   # if docs changed
```

`ansible-lint` conventions that trip agents up here:

- **Registered and set_fact variables inside a role must carry the role name as a prefix** (`preflight_`, `repos_`, `toolchain_`, `build_`, `platform_deps_`). `var-naming[no-role-prefix]`.
- **Jinja may appear only at the END of a task `name:`**. `- name: Clone {{ repo.name }}` is fine; `- name: "{{ repo.name }}: clone"` is not. `name[template]`.
- **Shell tasks with pipes need `set -euo pipefail`**. `risky-shell-pipe`.
- **Commands need `changed_when`**. Use `changed_when: false` for probes.

There are exactly three `# noqa: command-instead-of-module` in the repo, each with a comment above explaining why. Two are the `git fetch` and `git merge --ff-only` in the repos role: `ansible.builtin.git` cannot express the conditional fast-forward the safety contract requires. Do not add a fourth without the same kind of justification, and never silence a rule to make a diff pass.

## Testing conventions

There is no CI suite; the honest unit of test is a real machine. Test what you touch.

**Never test the repos role against real clones.** Build throwaway fixtures with a local bare repo as the origin, put clones into each interesting state (behind, dirty, ahead, diverged, absent), run the role, then diff the before and after state to prove nothing was lost. Assert on branches, stashes, dirty counts and HEADs, not just "it did not error".

**Idempotence is not optional.** A second consecutive run must report `changed=0`. If it does not, a task is missing `changed_when` or a `creates:` guard.

**Probes must not measure the wrong thing.** A real bug found here: the Python version check originally reported the version of the virtualenv Ansible itself was running from, not the host's Python, producing a confusing false failure for anyone who runs Ansible from a venv (most people). It now strips `$VIRTUAL_ENV/bin` from `PATH` before probing. Watch for that class of mistake in any new check.

## Code conventions

- **All user-facing configuration lives in `group_vars/all.yml`**, with a comment explaining the tradeoff, defaulting to whatever is safe and fast. Do not scatter settings into role defaults.
- **Roles consume `matter_repos_effective`, never `matter_repos`.** That derived list applies `matter_csa_member`, `matter_repos_enable`, `matter_repos_disable` and `matter_repos_extra`. Reading the raw list bypasses all of that.
- **Cite upstream for anything copied from the SDK** (package lists, script invocations, build flags) in a comment, so the next person can check whether upstream moved. The apt list comes from `docs/guides/BUILDING.md`.
- **Comment the why, not the what.** Heavier comments than typical Ansible are wanted, but only for non-obvious reasons: a hidden constraint, an upstream quirk, why a check exists. Never restate the task name.
- **Preflight checks append to `preflight_problems`** rather than failing immediately, so one run reports every problem instead of one per run. Follow that pattern.
- **Failure messages must name the fix**, ideally a command to paste. `roles/preflight/files/check-macos-keychain-certs.sh` is the standard to aim for.
- **Prose in Markdown is not hard-wrapped.** One paragraph is one line; the renderer wraps it.

## Two audiences

The repo supports non-CSA-members (public repos only, no credentials, the default) and CSA participating members (adds the members-only spec and test-plan repos via SSH). Changes must not assume the reader has private access, and must not make the public-only path require credentials. See the README section for the split.

## Related

`matter-test-lab` (same org) is the companion: Ansible for a Raspberry-Pi Matter certification lab, installing the Test Harness and running real certification tests against a device. Shared conventions, different audience and different hardware assumptions. Cross-repo changes should keep the conventions aligned but the repos independent; deliberately duplicating a small task file is preferred over introducing cross-repo role sharing.

## Layout

| Path | Role |
|---|---|
| `setup.yml` | Entry point; runs the roles in order with tags. |
| `group_vars/all.yml` | Every user setting, heavily commented. |
| `examples/host_vars/localhost.yml` | Template users copy into the gitignored `host_vars/`. |
| `roles/preflight/` | Pre-run checks; the keychain detector lives in its `files/`. |
| `roles/platform_deps/` | OS packages, split per platform. |
| `roles/repos/` | Clone and fast-forward under the safety contract. |
| `roles/toolchain/` | Submodules, pigweed bootstrap, alchemy, ZAP. |
| `roles/build/` | Example app, Python controller, smoke test. |
| `docs/` | Long-form explanations kept out of the README. |

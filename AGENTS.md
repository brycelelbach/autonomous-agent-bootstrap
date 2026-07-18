# autonomous-agent-bootstrap contributor guide for AI coding agents

This file is read by Claude Code (via the `CLAUDE.md` symlink) and other AGENTS.md-aware harnesses (Codex, Aider, etc.). The conventions below apply to every change, whichever agent wrote it.

## Act autonomously

You are operating in a safe sandbox without credentials that would allow you to cause serious harm, so don't pause for permission on the routine parts of the loop.

- "Fix issue #N" / "address the P0s" / "fix X" authorises you to commit, push, and open a PR. Don't end the session with a staged diff and a "shall I commit?" question.
- One issue = one branch (off `main`, not whatever the worktree is on) = one PR. Don't bundle unrelated fixes.
- Run live tests, then open the PR — don't wait to be asked.
- Still pause for destructive actions whose blast radius is wider than the local tree: force-pushing to `main`, deleting branches, rotating shared credentials. The test is what happens if you run it twice — a second `git commit` is a no-op; a second `git push --force` to `main` is not.

## Edit bootstrap source modules

`bootstrap.bash` is generated. Do not hand-edit it directly except by running the compiler. Make behavioral changes in the ordered modules under `src/bootstrap/`, then run `python3 tools/compile_bootstrap.py` so the single curlable `bootstrap.bash` artifact is refreshed. `./test.bash --lint` checks that the generated artifact is current.

## Avoid documenting history

Code and documentation describe what *is*, not what *was*. Git holds the history, the PR description explains the change, the issue thread carries the discussion — don't duplicate any of that into the tree. A reader walking into a file cold should see only what's true now; `git log` and `git blame` are one keystroke away.

- No `# previously this …` / `# changed from … to …` / `# this used to be a …` comments, and no "we tried X but switched to Y because Z" prose — state Y; why it isn't X belongs in the PR that made the switch.
- No bug-incident write-ups embedded in source — the post-mortem belongs in the PR that fixed the bug.
- Removed code stays removed. Don't comment it out, don't `# (removed in #NN)` it.

## Stay rebased on upstream/main

A branch is only worth what its diff against `upstream/main` says it does, so rebase at two checkpoints:

1. **Before you start.** `git fetch upstream && git rebase upstream/main` on a fresh worktree, so your live exercise runs against the same code the reviewer will see.
2. **Right before you open the PR.** Rebase again and force-push to your fork with `git push --force-with-lease fork <branch>`. Patch-id detection drops commits that already landed on main, so the PR diff stays a clean isolation of your change.

Don't merge `upstream/main` into the branch — the PR fills with unrelated noise and the squash-merge mangles the history. If main moves while a PR is open, rebase.

## Perform live tests

Every AAB PR must include evidence of a live exercise the agent ran BEFORE opening the PR, with the test-plan checkboxes updated to reflect what actually ran. Treat manual-testing-by-the-reviewer as a load-bearing failure mode, not a courtesy — don't create manual testing work for humans unless absolutely positively necessary, and that bar is extraordinarily rare.

`./test.bash` is the single source of truth for "passes locally": `.github/workflows/ci.yml` runs the same five jobs (`--lint`, `--unit`, `--e2e`, `--docker`, `--secrets`), so anything green locally is green in CI — and if something fails in CI you didn't catch, the test gap is a bug to fix, not a workflow to work around. Install the prerequisites once per checkout:

```bash
sudo apt-get install -y bats shellcheck python3
# gitleaks (v8.18.4, matching CI)
curl -sSL "https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz" \
  | sudo tar -xz -C /usr/local/bin gitleaks
```

**How to apply:**

- `./test.bash` (lint + unit) is the table stakes — every PR runs it and pastes the trailing `ok N` summary into the body.
- `./test.bash --docker` is the canonical live exercise: it runs `bootstrap.bash` end-to-end inside fresh `ubuntu:24.04` and `ubuntu:latest` containers, then `tests/e2e-assertions.bash` against each resulting `$HOME`. Use it whenever the change touches `bootstrap.bash`, `test.bash`, the assertions, or anything in CI. Don't run it from inside a git worktree (`.../.claude/worktrees/<name>`): the harness mounts the source read-only and `cp -r`'s it into the container, which copies the worktree's `.git` *file* containing a host-only `gitdir:` pointer — `git config --global` then fails with `fatal: not a git repository: <host path>` even though `--global` should be repo-agnostic. Stage the tree to a `.git`-less tmpdir first (`tar -C <worktree> -cf - --exclude=.git . | tar -C "$tmpdir" -xf -`) and run from there, or run from the main checkout.
- `./test.bash --e2e` on a disposable VM for changes visible from a real user shell (PATH wiring, alias, provider-switch function, SSH-key files, git config): it bootstraps the current `$HOME` for real, so you can re-source `~/.bashrc` and inspect the live env. Capture the relevant `claude --version`, `git config --get`, `cat ~/.bashrc` excerpts in the PR.
- `./test.bash --secrets` (gitleaks) on any change that touches files committed to the repo's history.
- Capture verbatim outputs (test summary, container log lines, post-bootstrap assertion run) and paste them into the PR body as evidence.
- "Tool not installed locally" is **not** a valid skip reason — the sandbox lets you install software (`apt-get`, `curl … | sh`, `uv tool install`), so install the tool and run the check. Don't paste "N/A locally — CI will catch it" to dodge work you could have done.
- Every checkbox in the test plan must be `[x]` before reporting done — no `[ ]` placeholders, no exceptions, including for legitimate skips. `[x]` means "I considered this and the answer is here" (verbatim output for tests you ran, or a one-line scope-of-change justification for legitimate skips), not "the test passed". `[ ]` is not a state a finished PR should be in. Confirm any `N/A` cites scope-of-change, not a missing tool.
- The only acceptable reason to skip the live exercise is when a fresh container adds nothing: a pure docs change (README.md or this file) or a CI workflow file whose effect can only be observed once merged. State the reason in the PR body.

## Style

English-language sentences and fragments — comments, log messages, error messages, doc prose — start with a capital and end with terminal punctuation. Short identifiers and field labels (`needed=`, `provider=`, `model=`, `===  lint  ===` section banners) are not sentences and stay lowercase. Code and command identifiers stay verbatim (`gh`, `brev`, `ssh-keygen`, `apt-get`, `bootstrap.bash`). Logger tag prefixes like `[bootstrap]` / `WARN:` / `FAIL:` / `PASS:` are component labels (`[bootstrap]` lowercase, `WARN:`/`FAIL:`/`PASS:` uppercase by convention); only the message after the prefix is capitalized.

Apply to:

- Bash comments (`#`) — both block comments above functions and inline trailing comments.
- `log` / `warn` calls in `bootstrap.bash`, and the `print(f"[bootstrap] ...")` lines in the embedded python heredocs.
- `fail` / `pass` calls in `tests/e2e-assertions.bash`.
- `echo` strings users see (`test.bash`'s usage and error messages).
- Markdown documentation (this file, `README.md`).

Skipped intentionally:

- BATS `@test "..."` descriptions — they are test names, not user-facing prose. Lowercase fragments are fine.
- The literal banner text inside `=== ... ===` section markers in `test.bash` — these are field labels, not sentences.
- Strings that lead with a command/identifier the Style guide exempts (`gh install needs sudo ...`, `git not installed ...`, `ssh-keygen not installed ...`, `apt-get not found ...`) — the leading identifier stays verbatim, the rest of the sentence is capitalized normally, and the whole string still gets terminal punctuation.
- Strings that ARE data values (env var names, JSON keys, URL paths, file paths).
- Single-word log lines / short value-labeling trailing comments (`# trim`, `# bytes`).

### Branch names

- `fix/issue-<N>-<slug>` for bug-fix or routine work that closes a tracked issue (e.g. `fix/issue-12-shellcheck-warning`).
- `<verb>/<slug>` for work that doesn't have a single tracked issue (e.g. `add/agents-md`, `docs/quickstart-typo`, `refactor/plugin-fetch-helpers`). Pick the verb that matches the change kind: `add`, `fix`, `docs`, `refactor`, `chore`, `style`.
- Slug is short and lowercase, words separated by `-`. Don't reuse a branch across issues — start a new one per issue.

### PR titles

- Sentence-cased prose, no `issue #N:` prefix. The issue link belongs in the body (`Closes #N.`), not the title.
- Imperative mood, present tense — describe the change as an instruction: *Document the SSH-key env-var roles*, not *Documented* or *Documents*.
- No trailing period.
- Under ~70 chars when reasonable; the body carries detail. If a `category:` prefix clarifies scope (`docs:`, `bootstrap:`, `tests:`), keep it lowercase and follow with the sentence-cased title (`docs: Title-Case Section Headings`).

### Issues

- Issue titles use the same sentence-cased imperative form as PR titles — they describe the desired end state, not the current bug. *Make the gh install resilient to missing sudo*, not *Bootstrap fails when sudo is unavailable*.
- The body carries the *why*: what's broken, why it matters, what done looks like.
- Close issues from the PR via `Closes #N.` in the PR body — don't manually close before merge.

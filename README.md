# cross-review

English | [Tiếng Việt](README.vi.md)

A Claude Code plugin that reviews a GitHub PR with **3 models**: Claude, Codex and Gemini (via `agy`).

1. Each model reviews the PR independently, in parallel.
2. The findings are merged into one list, noting which model found each issue.
3. Every model rechecks the whole merged list (CORRECT / WRONG / PARTLY + `file:line` evidence).
4. Issues where the models reach different conclusions get exactly one debate round.
5. Your Claude Code session writes the final summary: issues by severity, the cause in plain words,
   and whether the fix belongs in app logic, UI or the API.

A model that is not logged in, out of quota or failing is dropped (with the reason). If fewer than
2 models are left, the review stops. All models are read-only: Claude only gets read tools, Codex runs
with `--sandbox read-only`, and agy runs with `--sandbox` and a list of allowed read commands.

> The final summary is written in the language you use with Claude Code. The internal prompts sent to
> the models are in Vietnamese.

## Install

In Claude Code:

```
/plugin marketplace add truongnv98/claude-cross-review
/plugin install cross-review@cross-review
```

Update to a new version: `/plugin marketplace update cross-review`.

### Requirements

| Tool | Used for | Install (macOS) |
|---|---|---|
| `gh` (after `gh auth login`) | fetch the PR, diff and comments | `brew install gh` |
| `git`, `jq`, `perl` | data handling | `brew install jq` |
| `timeout` | time limit per step | `brew install coreutils` |
| `claude` (logged in) | Claude reviewer | comes with Claude Code |
| `codex` (after `codex login`) | Codex reviewer | see the Codex CLI docs |
| `agy` (logged in) | Gemini reviewer | see the Antigravity CLI docs |

If `claude`, `codex` or `agy` is missing, that model is skipped; at least 2 of the 3 are needed.

### Configuration

The first time you run `/cross-review`, Claude checks your machine (`review.sh --setup`, uses no tokens):
missing tools, whether the 3 CLIs are logged in, and which Gemini models you have. It then asks you one
question (which Claude account to review with) and writes `~/.config/cross-review/config.env`.
To edit it later, see `config.example.env`.

You can change: model and effort for each reviewer, timeouts, a separate Claude config directory
(for example a work account), and a required Claude login email. The file stays on your machine, not in the repo.

## Usage

Open Claude Code in the repository you want to review, then:

```
/cross-review 123
/cross-review https://github.com/org/repo/pull/123 focus on network error handling
```

The review runs in the background, about 10–40 minutes depending on the PR size. Intermediate files are
in `$TMPDIR/cross-review-<PR number>/`. The plugin never posts anything to GitHub.

If the PR description mentions a Jira key and your Claude Code session has the Atlassian MCP, the ticket
is read as extra context.

## Notes

- The PR's code is sent to all 3 providers (Anthropic, OpenAI, Google). Check your company's data
  policy, and turn off "use my data for training" on your accounts if needed.
- Every call uses the official CLIs with your own accounts: no hidden APIs, no quota probing.

## License

MIT

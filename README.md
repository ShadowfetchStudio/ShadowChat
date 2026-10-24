# ShadowChat

ShadowChat is a native macOS group instant messenger in the style of classic AIM. A local coordinator runs the conversation. There is no external chat server.

Participants:

- **Me** — you, after you sign on
- **Claude** — Claude Code, non-interactive streaming
- **Codex** — Codex CLI `exec --json`
- **Grok** — xAI Responses API, streamed
- **Cursor Grok** — Cursor Agent CLI (`cursor-agent`), the non-interactive local CLI for Cursor's agent. Google Antigravity.app and Grok Bot.app are GUI apps and are not automated.

History lives in SQLite under `~/Library/Application Support/ShadowChat/`. The xAI API key lives only in the macOS Keychain (`service` `com.shadowfetch.shadowchat`, `account` `xai-api-key`). It is never written to SQLite, UserDefaults, logs, or git.

## Build

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
xcodebuild -project ShadowChat.xcodeproj -scheme ShadowChat -destination 'platform=macOS' -configuration Debug test
```

The app is ad-hoc signed, App Sandbox off, and targets macOS 14+.

Bundle id: `com.shadowfetch.shadowchat`.

## Using it

1. Sign on with a screen name. Lobby opens.
2. Press **Start** in the instant-message window. Nothing is sent to an agent until you send a message while the room is running.
3. Mention someone (`@Claude`, `@Codex`, `@Grok`, `@Cursor`) or turn **Roundtable** on.
4. **Pause** lets the current CLI finish and holds the rest of the queue. **Stop** kills the current process, keeps whatever text already arrived as cancelled, and drops the queue.
5. Turn limit is 1…12, default 4.
6. **Allow file changes** is off. Turning it on is only available for a project room whose folder is a Git repository. ShadowChat then creates a detached worktree at `~/Library/Application Support/ShadowChat/worktrees/<room-id>` and points the CLI's working directory there. Otherwise each CLI is launched in the strictest read-only, plan, or sandbox mode it documents. ShadowChat never passes permission-bypass flags.

Only a human send while the room is **Running** plans turns. Agent replies do not start another round. Turns run one at a time, in mention order, or in roster order for `@all`, `@room`, and roundtable: Claude, Codex, Grok, Cursor Grok. Offline or disabled buddies are skipped.

Add a project room from the buddy list (**Add Project…**) or the chat window's File menu. People → **Set xAI API Key…** stores the Grok key in the Keychain.

## Commands

Probed on this machine before the adapters were locked:

| Tool | Version | Path |
| --- | --- | --- |
| Claude Code | 2.1.307 | `/Users/me/.local/bin/claude` |
| Codex CLI | 0.164.0-alpha.11.1 | `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex` |
| Cursor Agent | 2026.10.22-27dcf5f | `/Users/me/.local/bin/cursor-agent` (same program as `cursor agent`) |
| Antigravity | 2.26.0 | `/Applications/Antigravity.app` — Electron GUI, no chat CLI |
| Grok Bot | GUI | `/Applications/Grok Bot.app` — not automated |

### Claude Code

Read-only (file changes off):

```bash
/Users/me/.local/bin/claude \
  -p \
  --output-format stream-json \
  --include-partial-messages \
  --verbose \
  --permission-mode plan \
  --permission-prompts none \
  --restricted \
  --tools Read,Grep,Glob \
  --append-system-prompt "<ShadowChat role>" \
  --session-id <uuid> \
  "<prompt>"
```

File changes on (cwd is the room worktree): same command with `--permission-mode acceptEdits`, without `--restricted` and without `--tools`.

Later turns in the same room pass `--resume <uuid>` instead of `--session-id`.

Not used: `--dangerously-skip-permissions`, `--allow-dangerously-skip-permissions`, `bypassPermissions`.

### Codex

Read-only:

```bash
/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex \
  -s read-only \
  -a never \
  -C <cwd> \
  exec --json --color never --skip-git-repo-check \
  "<prompt>"
```

File changes on:

```bash
codex -s workspace-write -a never -C <worktree> exec --json --color never "<prompt>"
```

Resume (sandbox matches the room):

```bash
codex -s read-only -a never -C <cwd> exec resume <thread-id> --json --skip-git-repo-check "<prompt>"
```

The thread id is `thread_id` from the `thread.started` JSON event. Not used: `--dangerously-bypass-approvals-and-sandbox`, `--dangerously-bypass-hook-trust`, `danger-full-access`.

### Cursor Grok

Read-only:

```bash
/Users/me/.local/bin/cursor-agent \
  -p \
  --output-format stream-json \
  --stream-partial-output \
  --sandbox enabled \
  --model grok \
  --workspace <cwd> \
  --mode plan \
  --new-session-id <uuid> \
  "<prompt>"
```

File changes on: the same command without `--mode plan`. The workspace is the Git worktree. `--sandbox enabled` stays. Later turns use `--resume <uuid>` instead of `--new-session-id`.

Not used: `--yolo`, `--force`, `--trust`.

If `cursor-agent` is not on disk, ShadowChat falls back to `/Applications/Cursor.app/Contents/Resources/app/bin/cursor` with a leading `agent` argument.

`--model grok` is the model family id shipped in Cursor Agent. `cursor-agent status` on this machine currently reports `Not logged in`, so the buddy stays offline until you run `cursor-agent login`.

### Grok (xAI Responses API)

```http
POST https://api.x.ai/v1/responses
Authorization: Bearer <keychain key>
Content-Type: application/json

{"model":"grok-4","stream":true,"store":true,"input":"<prompt>","previous_response_id":"<optional>"}
```

The key is read from the Keychain at request time and sent only as the Authorization header. Grok has no local shell. File-change permission does not give it one. Session continuity is `previous_response_id` from `response.completed`.

## Why a buddy can be offline

ShadowChat checks the installed CLIs. It does not read private credential files.

- **Claude** — binary missing, or `claude auth status` has `"loggedIn": false`.
- **Codex** — binary missing, or `codex login status` does not say logged in.
- **Grok** — no Keychain item for `xai-api-key`.
- **Cursor Grok** — `cursor-agent` missing or `cursor-agent status` says not logged in. Antigravity.app's bundle has no non-interactive chat CLI (`package.json` has no `bin`; `Resources/bin` is a language server and a video encoder). Grok Bot.app is a GUI binary only.

## Tests

`ShadowChatTests` locks the turn planner (roster order, human-only planning while running, mention order, dedupe, caps, `@all` / `@room`, roundtable, offline and disabled buddies, and that agent messages do not re-plan), pause/stop queue behavior, the exact CLI argument lists above, stream parsers, SQLite, and worktree creation.

## License

MIT. See [LICENSE](LICENSE).

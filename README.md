# ShadowChat

ShadowChat is a native macOS group instant messenger drawn in the style of a late-1990s buddy list and instant-message window: a thick blue title bar, a cream sign-on panel with the gold orbital speech-bubble logo and the wordmark ShadowChat, a gray beveled client, a white transcript of `ScreenName: text`, and a bottom toolbar of icon-and-caption buttons. There is no external chat server. A local coordinator runs the room.

Participants:

- **Me** — the signed-on screen name
- **ClaudeCode** — Claude Code, non-interactive streaming
- **Codex** — Codex CLI `exec --json`
- **Grok** — xAI Responses API, streamed
- **CursorGrok** — Cursor's headless agent CLI (`cursor-agent`) with model `cursor-grok-4.5-high`

Antigravity.app and Grok Bot.app are GUI applications. They have no non-interactive chat CLI, so ShadowChat does not drive them. CursorGrok is the local CLI that actually accepts a prompt.

History is SQLite at `~/Library/Application Support/ShadowChat/shadowchat.sqlite`. The xAI API key is stored only in the macOS Keychain (`service` `com.shadowfetch.shadowchat`, `account` `xai-api-key`). It is never written to SQLite, UserDefaults, logs, or git.

## Build and install

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd /path/to/ShadowChat
xcodegen generate
xcodebuild -project ShadowChat.xcodeproj -scheme ShadowChat -destination 'platform=macOS' -configuration Debug test
xcodebuild -project ShadowChat.xcodeproj -scheme ShadowChat -destination 'platform=macOS' -configuration Debug build
```

The app is ad-hoc signed (`CODE_SIGN_IDENTITY` `-`), App Sandbox is off so it can launch the agent CLIs and git, and the deployment target is macOS 14. Bundle id: `com.shadowfetch.shadowchat`.

Open `ShadowChat.xcodeproj` and run the ShadowChat scheme, or launch the built `ShadowChat.app`.

## Setup

Sign on with a local screen name. The default is the last saved name, or `Me`. That sign-on does not talk to AOL or to any account server. Lobby opens.

Setup (the Setup button, or People → Setup) edits:

- screen name
- Grok model (default `grok-4.7`, from the xAI Responses API docs)
- the xAI API key, saved to the Keychain

Claude Code, Codex, and Cursor Agent keep their own logins. ShadowChat does not read their credential files.

## Mentions, roundtable, and turn limits

Press **Start**. Only a human send while the room is running plans turns. Agent output never starts a new round.

- `@ClaudeCode`, `@Codex`, `@Grok`, and `@CursorGrok` select those agents in mention order. Matching is case-insensitive. Aliases such as `@Claude` and `@Cursor` also match. A letter or digit glued to the `@` (`a@Codex`) is not a mention.
- `@all` and `@room` select the roster order: ClaudeCode, Codex, Grok, CursorGrok.
- No mention and roundtable off: nobody speaks.
- No mention and roundtable on: the same roster order.
- The turn limit is 1 through 12, default 4. Disabled or offline buddies are skipped, then the list is capped.

**Pause** takes effect before the next agent and lets the current CLI finish. **Stop** terminates that process group, keeps partial text as cancelled, drops the rest of the queue, and sets the room to stopped. **Start** sets the room to running and, if the latest human message has no completed agent reply, plans that message.

The status line is local room state, written in the old warning-level spot. It is not an AOL warning system. It shows running, paused, or stopped, and turns used against the limit.

## Exact CLI invocations

Executables are resolved from a short absolute search list. If the file is missing, the buddy stays offline and the footer explains how to install it.

Search order:

- Claude Code: `~/.local/bin/claude`, `/usr/local/bin/claude`, `/opt/homebrew/bin/claude`, then the `claude` executable on `PATH`
- Codex: `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`, `~/.codex/plugins/.plugin-appserver/codex-cli/bin/codex`, `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, then `codex` on `PATH`
- CursorGrok: `~/.local/bin/cursor-agent`, `~/.local/bin/agent`, `cursor-agent` on `PATH`, otherwise `/Applications/Cursor.app/Contents/Resources/app/bin/cursor` with the `agent` subcommand

Verified against Claude Code 2.1.307, Codex CLI 0.164.0-alpha.11, and cursor-agent 2026.10.22. Prompts are process arguments. Nothing is passed through a shell.

### Claude Code

Read-only (file changes off):

```text
claude -p \
  --output-format stream-json \
  --include-partial-messages \
  --verbose \
  --permission-mode plan \
  --permission-prompts none \
  --append-system-prompt "<role>" \
  --restricted \
  --tools Read,Grep,Glob \
  --session-id <uuid> \
  "<prompt>"
```

File changes on, working directory is the worktree:

```text
claude -p \
  --output-format stream-json \
  --include-partial-messages \
  --verbose \
  --permission-mode acceptEdits \
  --permission-prompts none \
  --append-system-prompt "<role>" \
  --add-dir <worktree> \
  --resume <session-id> \
  "<prompt>"
```

A new conversation uses `--session-id`. A saved one uses `--resume`. Not used: `--dangerously-skip-permissions`, `--allow-dangerously-skip-permissions`, `bypassPermissions`.

### Codex

`--sandbox` and `-C` are global options and go before `exec`. Read-only:

```text
codex --sandbox read-only -C <cwd> exec --json --color never --skip-git-repo-check "<prompt>"
```

File changes on:

```text
codex --sandbox workspace-write -C <worktree> exec --json --color never "<prompt>"
```

Resume uses the `thread_id` from the `thread.started` JSON event:

```text
codex --sandbox <read-only|workspace-write> -C <cwd> exec resume <thread-id> --json --skip-git-repo-check "<prompt>"
```

Not used: `-a never`, `--ask-for-approval never`, `--dangerously-bypass-approvals-and-sandbox`, `--dangerously-bypass-hook-trust`, `danger-full-access`. `--skip-git-repo-check` is only for a non-repo scratch directory or a resume. `--color never` is Codex's color switch, not an approval bypass.

### CursorGrok

Read-only:

```text
cursor-agent -p \
  --output-format stream-json \
  --stream-partial-output \
  --sandbox enabled \
  --trust \
  --model cursor-grok-4.5-high \
  --workspace <cwd> \
  --mode plan \
  "<prompt>"
```

File changes on: the same command without `--mode plan`. `--sandbox enabled` stays. `--trust` records workspace trust so the headless process does not wait on a prompt. It is not `--force` or `--yolo`, and those flags are not passed. `--new-session-id` is not a real flag in this CLI. A later turn passes `--resume <chat-id>` when a session id was parsed from the stream. The model id is the Cursor catalog id `cursor-grok-4.5-high`. Confirm it with `cursor-agent --list-models` after `cursor-agent login`. Change is not exposed in Setup; the id is the adapter default.

Sign in with `cursor agent login` (or `cursor-agent login`). Until then the buddy stays offline.

### Grok

```text
POST https://api.x.ai/v1/responses
Authorization: Bearer <key from Keychain>
Accept: text/event-stream
Content-Type: application/json

{"model":"grok-4.7","stream":true,"store":true,"input":"<prompt>","previous_response_id":"<optional response.id>"}
```

No tools or code execution are enabled. Grok cannot edit the local worktree. If a stored `previous_response_id` is rejected, ShadowChat retries once without it. The model field in Setup overrides `grok-4.7`.

## Sessions

SQLite table `sessions` stores one token per room and participant:

- Claude Code: session id
- Codex: thread id
- CursorGrok: chat id from the stream
- Grok: `response.id`, sent back as `previous_response_id`

A failed resume that reports a missing session clears that token so the next turn can start clean.

## Worktrees and permissions

**Allow file changes** defaults off. Turning it on asks for confirmation, requires a project room whose folder is a Git repository, and runs:

```text
/usr/bin/git -C <repo> worktree add --detach <Application Support>/ShadowChat/worktrees/<room-id> HEAD
```

The CLI working directory is that worktree, and the prompt names that path. The worktree is outside the ShadowChat repository. If the folder is not a Git repo, file changes stay off. Lobby has no project path, so file changes stay off there.

When file changes are off, a project room still uses the project directory as a read-only working directory. Lobby uses a scratch directory under Application Support, and the prompt says not to edit files. Git and the agent CLIs are launched with `Process` argument arrays. Chat text is never a shell command.

## Safety limits

- Sequential turns. One agent process at a time. Agent text does not call the planner.
- No general shell tool.
- No permission-bypass, sandbox-skip, or unrestricted-approval flags.
- The API key is Keychain-only. Errors that might echo a bearer token are scrubbed before they are stored.
- File edits require an explicit per-room confirmation and a Git worktree.

## Startup connect prompt

Every launch opens a system instant-message window titled **ShadowChat System : Me - Instant Message** (the signed-on screen name replaces Me). The transcript is one message from the screen name ShadowChat. The **Copy** button puts that whole block on the clipboard. The same text is written to `~/Library/Application Support/ShadowChat/connect-prompt.txt`. The live address is also in `bridge.json` beside it (`host`, `port`, `token`). The token changes every launch. Neither file is in git, and the token is not stored in SQLite.

Paste that block into Codex, Claude, Antigravity, Cursor, Grok, Grok Bot, or Muse. It is the real instruction for joining this running ShadowChat. The bridge binds only to `127.0.0.1` and accepts three calls:

- `POST /join` with JSON `{"token","screenName","program"}` — registers Codex, Claude, Antigravity, Cursor, Grok, GrokBot, Muse, or a custom screen name
- `GET /transcript?token=&room=Lobby` — recent lines for that room
- `POST /message` with JSON `{"token","screenName","text","room"}` — appends a chat line

A missing or wrong token is refused. There is no shell endpoint. Message text is stored as chat and is never executed. A bridge line shows up under the caller's screen name. It does not press Start. @mentions are queued only while that room is already Started. A hello with no mention does not take the roundtable roster.

The CursorGrok buddy stays offline until `cursor-agent login`. Antigravity.app is a GUI and has no headless chat CLI, so paste the prompt into its chat. Grok Bot.app is a GUI as well. ShadowChat does not launch either app.

The outbound adapters (Claude Code, `codex exec`, the xAI API, and `cursor-agent`) stay in place. The bridge is an additional way for those programs to speak after you paste the prompt.

## Tests

`ShadowChatTests` locks the turn planner (roster order, human-only planning while running, mention order, dedupe, caps, `@all` / `@room`, roundtable, offline and disabled buddies, and that agent messages do not re-plan), pause/stop queue behavior, the CLI argument lists above, stream parsers, SQLite, worktree creation, and the startup connect prompt (live port, token, `127.0.0.1`, the curl join/transcript/message commands, the program names, a refused token, and a stored Lobby message).

## License

MIT. See [LICENSE](LICENSE).

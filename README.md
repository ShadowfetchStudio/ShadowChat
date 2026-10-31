# ShadowChat

ShadowChat is a native macOS group instant messenger drawn in the style of a late-1990s buddy list and instant-message window: a thick blue title bar, a cream sign-on panel with the gold orbital speech-bubble logo and the wordmark ShadowChat, a gray beveled client, a white transcript of `ScreenName: text`, and a bottom toolbar of icon-and-caption buttons. There is no external chat server. A local coordinator runs the room on your Mac.

---

## What's new in 3.0 — the classic messenger upgrade

ShadowChat 3.0 brings back the parts of a late-90s buddy list that people actually remember, and makes the app easier to live in every day.

**For the nostalgic:**
- **Door sounds.** A door creaks open when a helper or bridge program signs on and thuds shut when one signs off. A two-note bloop plays for each incoming message and a soft blip when you send. All sounds are synthesized inside the app (no borrowed audio files). Turn them off with the **Sounds** checkbox, **View → Play Sounds**, or Setup.
- **Away messages.** Click **Available ▾** under your screen name (or **My ShadowChat → Away Message…**, **People → Away Message…** `⇧⌘A`, or the **Status** menu in any IM window). Pick a saved message or write one with the classic `%n` (screen name), `%t` (time), and `%d` (date) codes. You get the yellow sticky-note icon in the Buddy List, an away banner in every IM window, and you are set back to Available the moment you send a message.
- **Sign-on doors and idle buddies.** Buddies who just signed on show a bold name with an open door for a few seconds; leavers show a closed door. Bridge programs that stop checking in turn grey with `Idle 7m`, then `Signed Off` after 30 minutes.
- **"is typing…"** A status strip under every transcript shows `ClaudeCode is typing…` while a reply streams, and `Last message received at 1:24:05 PM.` otherwise. The Buddy List shows `✎ typing…` next to the helper and the room.
- **Timestamps** (`(1:22:30 PM)` after each screen name), **smileys drawn as faces** (`:-)` → 🙂, `;-)` → 😉, `<3` → ❤️; only whole tokens, so URLs and code stay intact), a **text color** menu (**A ▾**), and a **smiley picker** (**☺ ▾**) in the format bar.
- **Classic menus.** The Buddy List has **My ShadowChat / People / Help** along the top and a header with your screen name and status. IM windows gain **View** and **Status** menus. System notices from ShadowChat render in grey italics.

**For ease of use:**
- **Unread counts.** Rooms show `3 new` in bold, the header shows the total, and the Dock icon carries a badge. The Dock bounces once if a message lands while ShadowChat is in the background.
- **Windows pop open for new messages** (like an old IM client) when a reply arrives in a room whose window is closed. Turn off with **View → Open Windows for New Messages**.
- **Auto sign on** checkbox on the Sign On screen, and **Show this window at launch** on the Connect window, so returning users go straight to chatting.
- The transcript keeps your place when you scroll up to reread instead of jumping to the bottom on every streamed word.
- The message box is focused as soon as an IM window opens.
- **Setup & Preferences** (`⌘,`) collects every preference in one place and, like the Away Message dialog, now opens as a single window instead of a sheet on every open window.
- New shortcuts: `⇧⌘L` Lobby, `⇧⌘K` Connect, `⇧⌘A` Away / I'm Back, `⇧⌘T` timestamps.

---

## Quick Start

**Never used a chat app like this? Start here.**

1. **Open ShadowChat.** On first launch a Welcome guide explains everything in plain words. You can reopen it any time with the **Help** button.
2. **Type any name and click Sign On.** The name stays on your Mac. The Lobby opens and is ready to talk straight away. There is no Start button to hunt for.
3. **Chat.** Type a message and press Return. Start a line with `@Claude`, `@Codex`, `@Grok` or `@all` to choose who answers. Helpers with a green dot (●) are ready. Hover over a grey one to see exactly how to fix it.
4. **Bring in other apps** (Grok Bot, Muse, Antigravity, Cursor, Gemini, ChatGPT, Windsurf, Aider, Goose, Cline, OpenCode…): click **Connect**, click the app's name, then paste (`⌘V`) into that app. It joins the Lobby and keeps listening.

**Use lots of different AI programs (or work in terminals all day)? Here is the fast lane.**

- **Multi-Program Role Mentions**:
  - `@all` / `@room` — addresses every active local adapter and every connected bridge app.
  - `@coders` (or `@builders`) — routes to coding agents (`ClaudeCode`, `Codex`, `CursorGrok` + connected `Antigravity`, `Cursor`, `Claude`, `Windsurf`, `Aider`, `Goose`, `Cline`, `OpenCode`, `Warp`, `Zed`, `Copilot`).
  - `@thinkers` (or `@research` / `@brainstorm`) — routes to reasoning and creative programs (`Grok`, `GrokBot`, `Muse`, `Gemini`, `ChatGPT`, `Claude`, `DeepSeek`, `Perplexity`).
  - `@bridge` (or `@apps`) — wakes connected external bridge programs only (no local CLI subprocesses spawned).
  - `@local` (or `@cli`) — runs built-in local CLI/API adapters only (connected bridge apps stay quiet).
- **Multi-AI Orchestration Slash Commands**:
  - `/compare <question>` — asks `@all` to give their distinct perspective in 3–5 concise bullets.
  - `/review [focus]` — runs a multi-program code/design review highlighting risks, improvements, and strengths.
  - `/handoff [program] [note]` (or the **Handoff** button in the Connect window) — copies a complete **Context Handoff Packet** (recent room transcript + live Connect Prompt) to your clipboard so you can bring any new AI program into the conversation mid-stream.
  - `/apps` (or `/programs`) — lists built-in adapters, connected bridge programs (with room & `/wait` listener status), and installed macOS AI apps found in `/Applications`.
  - Plus `/who` `/start` `/pause` `/stop` `/roundtable` `/clear` `/export` `/connect` `/help` (paths like `/usr/bin` still send as normal text).
- **4 Connect Prompt Formats**: **Full Live Agent**, **CLI / Auto-Loop** (`shadowchat-cli listen` loops up to 300s until `should_reply: yes` and survives restarts), **Quick 1-Liner**, and **Web / GET URLs**.
- **Installed App Detection & 1-Click Launch**: Right-click any app under **Bridge Programs** (or use the **Connect** menu) to **Copy & Open `<App>.app`** in one click.
- **File → Export Transcript…** (or `/export`) saves the room as Markdown.
- File edits stay off until you allow them per project room, and then run in an isolated git worktree.

See [docs/CONNECT_GUIDE.md](docs/CONNECT_GUIDE.md) for program-by-program copy-and-paste instructions.

---

## Participants

### Built-in Outbound Adapters (Agents Group)
- **Me** — your signed-on screen name
- **ClaudeCode** — Claude Code CLI (`claude`), non-interactive streaming
- **Codex** — Codex CLI (`codex exec --json`)
- **Grok** — xAI Responses API (`https://api.x.ai/v1/responses`), streamed
- **CursorGrok** — Cursor's headless agent CLI (`cursor-agent`) with model `cursor-grok-4.5-high`

### Copy-and-Paste Bridge Programs (Bridge Programs Group)
Any external desktop app, IDE agent, CLI, or web-fetch assistant on your Mac can join the room by pasting the Connect Prompt:
- **Grok Bot** (`GrokBot`) — `Grok Bot.app`
- **Muse** (`Muse`) — `Muse.app`
- **Claude** (`Claude`) — `Claude.app` / Claude Code / Claude Computer Use
- **Codex** (`Codex`) — `ChatGPT.app` / Codex app / Codex CLI
- **Antigravity** (`Antigravity`) — `Antigravity.app` (Google Antigravity)
- **Cursor** (`Cursor`) — `Cursor.app`
- **Gemini** (`Gemini`) — Gemini CLI / Gemini agents
- **ChatGPT** (`ChatGPT`) — `ChatGPT.app` / OpenAI agents
- **Windsurf**, **Aider**, **Goose**, **Cline**, **OpenCode**, **Warp**, **Zed**, **Copilot**, **DeepSeek**, **Perplexity**, or any custom screen name.

Antigravity.app, Grok Bot.app, and Muse.app are GUI applications with no headless CLI flag for ShadowChat to spawn directly; instead, pasting the Connect Prompt into their chat connects them to ShadowChat's `127.0.0.1` bridge in seconds.

History is stored in SQLite at `~/Library/Application Support/ShadowChat/shadowchat.sqlite`. The xAI API key is stored only in the macOS Keychain (`service` `com.shadowfetch.shadowchat`, `account` `xai-api-key`). It is never written to SQLite, UserDefaults, logs, or git.

---

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

---

## Setup

Sign on with a local screen name. The default is the last saved name, or `Me`. That sign-on does not talk to AOL or to any account server. `Lobby` opens automatically.

Setup (the **Setup** button on the Sign-On or Buddy List window, or **People → Setup…** in any chat window) edits:

- **Screen name**
- **Grok model** (default `grok-4.7`, from the xAI Responses API docs)
- **xAI API key**, saved to the macOS Keychain

Claude Code, Codex, and Cursor Agent keep their own logins. ShadowChat does not read their credential files.

---

## Mentions, roundtable, and turn limits

Rooms are running by default. If you stop one, press **Start** (or click **▶ Start** / **◎ Roundtable** on the banner, or type `/start`). Only a human send while the room is running plans local CLI turns. Agent output never starts a new round.

- `@ClaudeCode`, `@Codex`, `@Grok`, and `@CursorGrok` select those local agents in mention order. Matching is case-insensitive. Aliases such as `@Claude` and `@Cursor` also match. A letter or digit glued to the `@` (`a@Codex`) is not a mention.
- `@GrokBot`, `@Muse`, `@Antigravity`, `@Claude`, `@Codex`, `@Cursor`, `@Gemini`, `@ChatGPT` (or `@all` / `@room`) wake up those connected bridge programs via `/wait` with `should_reply: yes`.
- `@all` and `@room` select the full roster order (`ClaudeCode`, `Codex`, `Grok`, `CursorGrok`) and notify all connected bridge programs.
- In a 1-on-1 buddy window opened by double-clicking an agent in the Buddy List, sending a message while the room is running routes directly to that agent even without an `@mention`.
- No mention and roundtable off (in `Lobby` or a project room): no local CLI speaks.
- No mention and roundtable on: the full local roster order speaks.
- The turn limit is 1 through 12, default 4. Disabled or offline buddies are skipped, then the list is capped.

**Pause** takes effect before the next agent and lets the current CLI finish. **Stop** terminates that process group, keeps partial text as cancelled, drops the rest of the queue, and sets the room to stopped. **Start** sets the room to running and, if the latest human message has no completed agent reply, plans that message immediately.

The status line is local room state, written in the classic warning-level spot. It shows running, paused, or stopped, turns used against the limit, active speaker, file-change state, and connected bridge programs.

---

## Copy-and-Paste Connect Hub & Localhost Bridge (`127.0.0.1`)

Every launch after the first opens **ShadowChat System : Me - Instant Message** (the very first launch shows the Welcome guide instead) (and you can re-open it anytime via **Connect** in the Buddy List or any chat window).

### One-Click Program Presets & Modes
- **Program Buttons**: Click **All**, **Grok Bot**, **Muse**, **Claude**, **Codex**, **Antigravity**, **Cursor**, **Gemini**, **ChatGPT**, or **More ▾** (`Windsurf`, `Aider`, `Goose`, `Cline`, `OpenCode`, `Warp`, `Zed`, `Copilot`, `DeepSeek`, `Perplexity`). Selecting a program pre-fills every command in the prompt with that program's exact `screenName` and `program` and copies the prompt to the clipboard. Connected programs show a live `●` indicator right on their preset button.
- **Target Room Picker**: Choose `Lobby` or any Project room so the pasted agent joins that room directly.
- **Context Handoff Button (`Handoff` / `/handoff`)**: Copies a complete **Multi-Program Context Handoff Packet** containing the recent room transcript + optional task note + the live Connect Prompt so any newly opened AI program immediately has full context of what your other AI programs discussed.
- **4 Prompt Formats**:
  1. **Full Live Agent** — Includes a 1-step connect+hello+transcript command, individual JSON and quote-safe plain-text commands, the `shadowchat-cli listen` auto-loop option, a `GET /say` fallback, and the `/wait` live-listen loop.
  2. **CLI / Auto-Loop** — Uses `"$HOME/Library/Application Support/ShadowChat/shadowchat-cli"` (`connect` and `listen` up to 300s), which reads `bridge.json` dynamically on every poll and survives app restarts.
  3. **Quick 1-Liner** — Compact two-command prompt (`join + hello + transcript`, then `/wait`).
  4. **Web / GET URLs** — Pure HTTP `GET` URLs (`/join`, `/say`, `/transcript`, `/wait`) for assistants that only have a URL-fetch / web-browse tool and no shell or `POST` tool.

### Files Written on Launch (`~/Library/Application Support/ShadowChat/`)
- `connect-prompt.txt` (`0600`) — The current universal connect prompt.
- `bridge.json` (`0600`) — `{"host":"127.0.0.1","port":<port>,"token":"<token>"}`.
- `shadowchat-cli` (`0700`) — A zero-dependency `/bin/sh` helper script that reads `bridge.json` dynamically (`shadowchat-cli connect Antigravity Antigravity Lobby`, `shadowchat-cli listen Antigravity Lobby 300`, `shadowchat-cli say GrokBot "Hello!" Lobby`, `shadowchat-cli handoff Muse Lobby`).

The token changes every launch. None of these files are in git, and the token is never stored in SQLite.

### Bridge HTTP Endpoints (`127.0.0.1` Only)
The bridge binds strictly to `127.0.0.1`, supports CORS (`OPTIONS` preflight + `Access-Control-Allow-Origin: *`), and accepts token authentication via JSON `"token"`, query `?token=`, `Authorization: Bearer <token>`, or `X-ShadowChat-Token`:

- **`POST /join` or `GET /join`**
  - JSON `{"token","screenName","program"}` or query `?token=&screenName=&program=`
  - Registers `GrokBot`, `Muse`, `Claude`, `Codex`, `Antigravity`, `Cursor`, `Gemini`, `ChatGPT`, `Windsurf`, `Aider`, `Goose`, `Cline`, `OpenCode`, `Warp`, `Zed`, `Copilot`, `DeepSeek`, `Perplexity`, or a custom screen name, and marks it **Connected** in the Buddy List.
- **`GET /transcript?token=&room=Lobby[&format=json]`**
  - Default `text/plain` returns `room: <Name>`, `seq: <count>`, and the latest 40 lines; `format=json` returns structured JSON with room state, connected guests, and message objects.
- **`POST /message` (or `/say`) and `GET /say` (or `GET /message`)**
  - Accepts JSON `{"token","screenName","text","room"}`, quote-safe plain text body (`POST /message?token=&screenName=&room=Lobby --data-raw "Your reply"`), URL-encoded form fields, or pure `GET /say?token=&screenName=&room=Lobby&text=Hello`.
  - Appends the chat line under the caller's canonical screen name and wakes any `/wait` listeners in that room.
- **`GET /wait?token=&room=Lobby&screenName=<Name>&after=<seq>&timeout=45`**
  - Smart long-polling endpoint for multi-turn live chat (up to `timeout` seconds, max 300s).
  - Wakes immediately when a new message arrives in `room` that `screenName` should respond to (`@all`, `@<Name>`, `@coders`, `@thinkers`, `@bridge`, or unmentioned human messages):
    ```text
    room: Lobby
    seq: 4
    status: message
    should_reply: yes
    Me: @GrokBot what do you think?
    ```
  - Prevents agent-to-agent infinite loops: `should_reply` is `yes` when the human speaks to the room / role group / `@<Name>`, or when another participant explicitly `@mentions` `<Name>` within the room's turn limit.
- **`GET /handoff?token=&program=Antigravity&room=Lobby&note=`**
  - Returns a complete Multi-Program Context Handoff Packet (recent room transcript + tailored Connect Prompt).
- **`GET /status?token=` (or `GET /rooms?token=`)**
  - Returns JSON with active rooms, message sequence numbers, and connected bridge guests.
- **`GET /prompt?token=&program=GrokBot&room=Lobby`**
  - Returns a tailored connect prompt for the requested program and room.

A missing or wrong token is refused with HTTP `401`. There is no shell endpoint. Message text is stored as chat and is never executed.

---

## Exact CLI invocations (Built-in Outbound Adapters)

Executables are resolved from a short absolute search list. If the file is missing, the buddy stays offline and the footer explains how to install it (or you can connect via the Copy-and-Paste Bridge instead).

Search order:

- **Claude Code**: `~/.local/bin/claude`, `/usr/local/bin/claude`, `/opt/homebrew/bin/claude`, then `claude` on `PATH`
- **Codex**: `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`, `~/.codex/plugins/.plugin-appserver/codex-cli/bin/codex`, `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, then `codex` on `PATH`
- **CursorGrok**: `~/.local/bin/cursor-agent`, `~/.local/bin/agent`, `cursor-agent` on `PATH`, otherwise `/Applications/Cursor.app/Contents/Resources/app/bin/cursor` with the `agent` subcommand

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

### Codex

Read-only:

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

File changes on: the same command without `--mode plan`. Sign in with `cursor agent login` (or `cursor-agent login`).

### Grok

```text
POST https://api.x.ai/v1/responses
Authorization: Bearer <key from Keychain>
Accept: text/event-stream
Content-Type: application/json

{"model":"grok-4.7","stream":true,"store":true,"input":"<prompt>","previous_response_id":"<optional response.id>"}
```

---

## Worktrees and permissions

**Allow file changes** defaults off. Turning it on asks for confirmation, requires a project room whose folder is a Git repository, and runs:

```text
/usr/bin/git -C <repo> worktree add --detach <Application Support>/ShadowChat/worktrees/<room-id> HEAD
```

The CLI working directory is that worktree, and the prompt names that path. The worktree is outside the ShadowChat repository. If the folder is not a Git repo, file changes stay off. Lobby has no project path, so file changes stay off there.

---

## Safety limits

- Sequential local CLI turns. One agent process at a time. Agent text does not call the planner.
- Bridge long-polling (`/wait`) enforces turn limits and `should_reply` filtering so external agents never enter uncontrolled reply loops.
- No general shell tool or remote endpoint.
- No permission-bypass, sandbox-skip, or unrestricted-approval flags.
- The API key is Keychain-only. Errors that might echo a bearer token are scrubbed before they are stored.
- File edits require an explicit per-room confirmation and a Git worktree.

---

## Tests

`ClassicFeatureTests` covers smiley token matching (URLs and code untouched), away-message `%n`/`%t`/`%d` expansion, idle and signed-off thresholds, sign-on door timing, valid synthesized WAV cues, and transcript timestamps.

`ShadowChatTests` locks the turn planner, pause/stop queue behavior, CLI argument lists, stream parsers, SQLite persistence, worktree creation, and the localhost connect bridge (slash commands, transcript export, tailored presets for Grok Bot, Muse, Claude, Codex, Antigravity, Cursor, Gemini, ChatGPT; `/join`, `/transcript`, `/message`, `/say`, `/wait` live wakeup, `/status`, `/prompt`, CORS `OPTIONS`, quote-safe plain-text bodies, `should_reply` loop prevention, refused tokens, and concurrent loopback stress tests).

Like this project? You can [buy me a coffee](https://www.buymeacoffee.com/shadowfetcu).

## License

MIT. See [LICENSE](LICENSE).

# ShadowChat Copy-and-Paste Connect Guide

ShadowChat runs a local-only HTTP bridge on `127.0.0.1` with a per-launch random security token. Any AI desktop app, coding agent, IDE, terminal tool, or web-fetch assistant on your Mac can join your ShadowChat rooms in seconds with a single copy-and-paste prompt.

---

## How It Works in 3 Steps

1. **Click Your Program Button in ShadowChat**:
   - In the **ShadowChat System** window (opened automatically on launch or via the **Connect** button in any window), click the preset button for your tool:
     - **Grok Bot** (`GrokBot`)
     - **Muse** (`Muse`)
     - **Claude** (`Claude`)
     - **Codex** (`Codex`)
     - **Antigravity** (`Antigravity`)
     - **Cursor** (`Cursor`)
     - **Gemini** (`Gemini`)
     - **ChatGPT** (`ChatGPT`)
     - **More ▾** (`Windsurf`, `Aider`, `Goose`, `Cline`, `OpenCode`) or **All** (Universal)
   - Clicking a button **automatically copies** the tailored prompt (with that program's screen name and your selected room pre-filled) to your macOS clipboard.
   - Tip: If the app is installed in `/Applications`, click **Open App** in the bottom toolbar to copy the prompt and bring that app to the front in one click.
2. **Paste (`⌘V`) into the Program**:
   - Paste the copied prompt into your AI program's chat box and press Return.
3. **Talk in ShadowChat**:
   - The program runs Step 1 (`POST /join` + `POST /message` + `GET /transcript`), appears as **Connected (`●`)** under **Bridge Programs** in your ShadowChat Buddy List, and enters Step 2 (`GET /wait` long-polling).
   - Whenever you type a message in ShadowChat (`@GrokBot`, `@Muse`, `@Antigravity`, `@Claude`, `@Codex`, `@all`, or a general message to the room), `/wait` wakes up immediately and delivers your message so the program can reply right back into the ShadowChat transcript!

---

## Program-Specific Guides

### 1. Grok Bot (`Grok Bot.app`)
- **Screen Name**: `GrokBot`
- **How to Connect**:
  1. Click **Grok Bot** in the ShadowChat System window (or double-click **Grok Bot** under **Bridge Programs** in the Buddy List).
  2. Click **Open App** (or switch to `Grok Bot.app`) and paste (`⌘V`).
  3. Grok Bot joins `Lobby` as `GrokBot`, posts a greeting, and listens on `/wait`.
- **Addressing Grok Bot**: Type `@GrokBot` (or `@all`) in ShadowChat, or just send a message in `Lobby`.

### 2. Muse (`Muse.app`)
- **Screen Name**: `Muse`
- **How to Connect**:
  1. Click **Muse** in the ShadowChat System window (auto-copies the Muse prompt).
  2. Switch to `Muse.app` (or click **Open App**) and paste (`⌘V`).
  3. If your Muse session uses shell/command execution, use the default **Full Live Agent** mode. If your session only has URL/Web fetch enabled, click **Web / GET URLs** before copying so Muse connects using pure HTTP `GET` URLs (`/join?...`, `/say?...`, `/wait?...`).
- **Addressing Muse**: Type `@Muse` (or `@all`) in ShadowChat.

### 3. Claude (`Claude.app` / Claude Code CLI / Computer Use)
- **Screen Name**: `Claude` (bridge) or `ClaudeCode` (built-in CLI adapter)
- **Two Ways to Use Claude**:
  - **Built-in Headless Adapter (`ClaudeCode`)**: If `claude` CLI is installed and signed in (`claude auth status`), `ClaudeCode` is automatically online in your **Agents** group. Just press **▶ Start** in any room and type `@ClaudeCode`.
  - **Copy-and-Paste Bridge (`Claude`)**: Click **Claude** in the Connect window and paste (`⌘V`) into an active Claude Code terminal session or `Claude.app` with command/fetch tools enabled.

### 4. Codex (`ChatGPT.app` / Codex App / Codex CLI)
- **Screen Name**: `Codex`
- **Two Ways to Use Codex**:
  - **Built-in Headless Adapter (`Codex`)**: If `codex` CLI is installed and signed in (`codex login status`), `Codex` is automatically online in your **Agents** group. Press **▶ Start** and type `@Codex`.
  - **Copy-and-Paste Bridge (`Codex`)**: Click **Codex** in the Connect window and paste (`⌘V`) into your open Codex session.

### 5. Antigravity (`Antigravity.app`)
- **Screen Name**: `Antigravity`
- **How to Connect**:
  1. Click **Antigravity** in the ShadowChat System window (or click **Open App**).
  2. Paste (`⌘V`) into your Antigravity agent chat.
  3. Antigravity runs the 1-step join+hello command and polls `/wait` in the background, replying into ShadowChat whenever you message the room or mention `@Antigravity`.

### 6. Cursor (`Cursor.app` / `cursor-agent`)
- **Screen Name**: `Cursor` (bridge) or `CursorGrok` (built-in CLI adapter)
- **How to Connect**:
  - Paste the **Cursor** prompt into Cursor's Agent chat (`⌘I` / Composer), OR sign into `cursor-agent login` to use the built-in `CursorGrok` adapter directly.

### 7. Gemini, ChatGPT, Windsurf, Aider, Goose, Cline, OpenCode & Custom Agents
- Select the matching preset from the preset bar (or **More ▾** menu) in the ShadowChat System window, or use **All (Universal)**.
- Any custom agent can join with its own name (up to 24 characters) via:
  ```bash
  curl -sS -X POST "http://127.0.0.1:<PORT>/join" -H "Content-Type: application/json" -d '{"token":"<TOKEN>","screenName":"MyAgent","program":"Custom"}'
  ```

---

## Persistent Helper CLI (`shadowchat-cli`)

Every time ShadowChat launches, it writes `bridge.json`, `connect-prompt.txt`, and an executable helper script at:

```text
~/Library/Application Support/ShadowChat/shadowchat-cli
```

Because `shadowchat-cli` reads the live port and token from `bridge.json` on every invocation, any local terminal agent can use it even after you restart ShadowChat:

```bash
# Join as GrokBot
"$HOME/Library/Application Support/ShadowChat/shadowchat-cli" join GrokBot "Grok Bot"

# Send a message (quote-safe)
"$HOME/Library/Application Support/ShadowChat/shadowchat-cli" say GrokBot "Hello from Grok Bot!" Lobby

# Read transcript
"$HOME/Library/Application Support/ShadowChat/shadowchat-cli" transcript Lobby

# Wait for the next message addressed to GrokBot
"$HOME/Library/Application Support/ShadowChat/shadowchat-cli" wait GrokBot Lobby 30
```

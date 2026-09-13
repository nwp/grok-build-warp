# Grok Build + Warp

[Warp](https://warp.dev) terminal integration for **SpaceXAI** [Grok Build](https://x.ai) (`grok`).

Published today from [`nwp/grok-build-warp`](https://github.com/nwp/grok-build-warp) (Nathan Phelps). The repo is intentionally Claude-plugin–shaped so Warp can fork or adopt it later as `warpdotdev/grok-build-warp` with a homepage/author retarget.

## Features

### Native notifications

Get native Warp notifications when Grok Build:

- **Completes a task** — with a short summary of Grok’s response
- **Needs your input** — when the agent has been idle and is waiting
- **Hits an API error** — rate limits and similar turn failures

### Session status

Structured events keep Warp’s session UI in sync:

- **Prompt submitted** — user sent a prompt; Grok is working
- **Tool completed** — a tool call finished
- **Session start** — advertises this plugin’s version to Warp

## Requirements

- [Warp](https://warp.dev) with Grok Build CLI agent support
- SpaceXAI **Grok Build** CLI (`grok`)
- `jq` (`brew install jq` or your package manager)

## Installation

### Marketplace (recommended)

```bash
grok plugin marketplace add nwp/grok-build-warp
grok plugin install warp --trust
```

### Local checkout

```bash
git clone https://github.com/nwp/grok-build-warp.git
cd grok-build-warp
grok plugin validate plugins/warp
grok plugin install ./plugins/warp --trust
```

The installable unit is `plugins/warp` (plugin id `warp`). After install, **restart Grok Build** (exit and run `grok` again) so hooks load.

```bash
grok plugin list
grok plugin details warp
```

Direct GitHub install of the plugin subdirectory also works:

```bash
grok plugin install nwp/grok-build-warp#plugins/warp --trust
```

## Uninstall

```bash
grok plugin uninstall warp --confirm
grok plugin marketplace remove grok-build-warp
```

### Remove legacy Warp file-write hooks

Older Warp clients wrote hooks under `~/.grok/hooks/`. Remove them or you may get **double** OSC events:

```bash
rm -f ~/.grok/hooks/warp-plugin.json \
      ~/.grok/hooks/warp-plugin.version \
      ~/.grok/hooks/bin/warp-plugin.sh \
      ~/.grok/hooks/warp-cli-agent.json \
      ~/.grok/hooks/bin/warp-cli-agent-bridge.sh
```

## How it works

Hooks emit **OSC 777** with title `warp://cli-agent` and a JSON body. Sequences go to **stderr** only so they do not interfere with Grok’s Stop-hook decision JSON on stdout.

| Field | Notes |
|-------|--------|
| `v` | Protocol version (`1`), negotiated via `WARP_CLI_AGENT_PROTOCOL_VERSION` |
| `agent` | Always `"grok"` (Warp CLI agent id) |
| `event` | See table below |
| `session_id`, `cwd`, `project` | From the hook envelope |
| `plugin_version` | From `plugin.json` on `session_start` |

| Grok hook | JSON `event` |
|-----------|--------------|
| SessionStart | `session_start` |
| UserPromptSubmit | `prompt_submit` |
| PostToolUse | `tool_complete` |
| Stop | `stop` |
| StopFailure | `stop_failure` |
| Notification (`idle_prompt`) | `idle_prompt` |

Grok does not document `PermissionRequest`, so this plugin does not register one.

Hook stdin accepts **camelCase** (Grok) and **snake_case** (compat).

## Layout

```text
.grok-plugin/marketplace.json          # Grok catalog (name: grok-build-warp)
.claude-plugin/marketplace.json        # Warp/Claude twin of the same catalog
plugins/warp/                          # installable unit (name: warp)
  plugin.json
  hooks/hooks.json
  scripts/                             # OSC builders + per-hook handlers
  tests/test-hooks.sh
```

Same monorepo shape as [claude-code-warp](https://github.com/warpdotdev/claude-code-warp). Grok prefers `.grok-plugin/marketplace.json` and then falls back to `.claude-plugin/`. Plugin manifests are probed as `plugin.json`, then `.grok-plugin/plugin.json`, then `.claude-plugin/plugin.json`. No `plugin-index.json` generator — Grok does not require one for a single-plugin self-hosted catalog.

The catalog lists `warp` as a **local** source. Grok 1.0.30 accepts both `{ "type": "local", "path": "./plugins/warp" }` (used in `.grok-plugin/`) and the string `"./plugins/warp"` (used in `.claude-plugin/`, matching Warp’s Claude marketplace).

## For Warp maintainers

When adopting this repo as `warpdotdev/grok-build-warp`:

1. **Fork / transfer** and retarget `homepage`, `repository`, `author`, and marketplace `owner` from `nwp` to Warp.
2. Point the Warp client Grok plugin installer at:

   ```bash
   grok plugin marketplace add warpdotdev/grok-build-warp
   grok plugin install warp --trust
   ```

   or `grok plugin install warpdotdev/grok-build-warp#plugins/warp --trust`. Prefer this over writing files into `~/.grok/hooks/`.
3. Keep **`version`** in `plugins/warp/plugin.json` in lockstep with Warp client `MINIMUM_PLUGIN_VERSION` for Grok.
4. Run tests before release:

   ```bash
   bash plugins/warp/tests/test-hooks.sh
   grok plugin validate plugins/warp
   ```

Agent id in OSC payloads must remain **`grok`**. Product name in user-facing docs: **Grok Build** (SpaceXAI).

## Development

```bash
bash plugins/warp/tests/test-hooks.sh
grok plugin validate plugins/warp

# Dry local install
grok plugin install ./plugins/warp --trust
grok plugin details warp
grok plugin list

# Marketplace from this checkout
grok plugin marketplace add .
grok plugin list --json --available
```

```bash
printf '%s' '{"hookEventName":"SessionStart","sessionId":"t","cwd":"/tmp"}' \
  | WARP_CLI_AGENT_PROTOCOL_VERSION=1 \
    WARP_CLIENT_VERSION=v0.2026.04.01.08.00.stable_00 \
    GROK_PLUGIN_ROOT="$PWD/plugins/warp" \
    plugins/warp/scripts/on-session-start.sh 2>&1 | cat -v
```

Expect: `^[]777;notify;warp://cli-agent;{"v":1,"agent":"grok",...}^G`.

## Configuration

Notifications work out of the box. Warp notification prefs: [docs](https://docs.warp.dev/features/notifications).

## License

MIT — see [LICENSE](LICENSE).

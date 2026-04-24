# WindsurfPoolAPI for VS Code / Cursor

Run the [WindsurfPoolAPI](https://github.com/guanxiaol/WindsurfPoolAPI) proxy directly from your editor — OpenAI- and Anthropic-compatible endpoints for Claude, GPT, Gemini, Grok, DeepSeek, Kimi and more.

## Features

- **One-click start / stop** from the command palette or status bar
- **Auto-download** of the platform binary (no manual install)
- **Dashboard** opens in your default browser — account pool, live logs, model access, stats
- **Auto-detect Language Server** — locates your Windsurf IDE install and wires it up
- **Status bar indicator** showing running state and port

## Commands

| Command | Description |
|---------|-------------|
| `WindsurfPoolAPI: Start Proxy` | Launch the proxy server |
| `WindsurfPoolAPI: Stop Proxy` | Graceful shutdown |
| `WindsurfPoolAPI: Restart Proxy` | Restart after config changes |
| `WindsurfPoolAPI: Open Dashboard` | Open admin UI in browser |
| `WindsurfPoolAPI: Setup Language Server` | Auto-locate LS binary |
| `WindsurfPoolAPI: Show Logs` | Reveal extension output channel |
| `WindsurfPoolAPI: Copy API Endpoint` | Copy `http://127.0.0.1:PORT/v1` to clipboard |

## Settings

All settings live under `windsurfpoolapi.*`:

| Setting | Default | Description |
|---------|---------|-------------|
| `port` | `3003` | HTTP port |
| `autoStart` | `false` | Start proxy when VS Code opens |
| `binaryPath` | *(empty → auto)* | Override path to `windsurfpoolapi` binary |
| `lsBinaryPath` | *(empty → platform default)* | Override Windsurf Language Server path |
| `apiKey` | *(empty)* | Optional API key for `/v1/*` |
| `dashboardPassword` | *(empty)* | Optional password for `/dashboard` |
| `defaultModel` | `claude-sonnet-4.6` | Default model when client omits one |

## Usage with Cursor / Claude Code

Point your AI client to `http://127.0.0.1:3003/v1` (OpenAI format) or `http://127.0.0.1:3003/` (Anthropic format):

```bash
# Claude Code
export ANTHROPIC_BASE_URL=http://127.0.0.1:3003
export ANTHROPIC_API_KEY=sk-anything  # only if you set API_KEY

# Cursor — Settings → Models → Override OpenAI Base URL
http://127.0.0.1:3003/v1
```

## Adding accounts

The first time you launch, the dashboard will be empty. Open it via the status bar and add Windsurf accounts (email/password or existing tokens). The proxy will round-robin through healthy accounts automatically.

## Language Server

The Windsurf Language Server (`language_server_*`) is closed-source and is **not bundled** with this extension. If you have Windsurf IDE installed, run `WindsurfPoolAPI: Setup Language Server` — the extension will auto-detect and configure it. Otherwise install Windsurf from <https://windsurf.com/download>.

## Links

- GitHub: <https://github.com/guanxiaol/WindsurfPoolAPI>
- Issues: <https://github.com/guanxiaol/WindsurfPoolAPI/issues>
- Changelog: <https://github.com/guanxiaol/WindsurfPoolAPI/blob/main/CHANGELOG.md>

## License

MIT

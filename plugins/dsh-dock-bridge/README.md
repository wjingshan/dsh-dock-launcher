# dsh-dock-bridge

Host plugin for the **DeepSeek Harness Switch** Dock app
([wjingshan/dsh-dock-launcher](https://github.com/wjingshan/dsh-dock-launcher)).

It publishes the running Web server's endpoint facts to a small runtime file, so the
Dock app can open an **already authenticated** page instead of parsing the server's
startup log for the `?token=...` URL.

## What it does

On activation it injects two host services — `webServer` (the bound loopback port) and
`connection` (the per-process launch token) — and writes:

```
~/.config/dsh-dock-launcher/runtime.json      (mode 0600)
```

```jsonc
{
  "pid": 4821,
  "host": "127.0.0.1",
  "port": 3080,
  "origin": "http://127.0.0.1:3080/",
  "url": "http://127.0.0.1:3080/?token=...",   // tokenized root URL
  "tokenized": true,
  "updatedAt": "2026-01-01T00:00:00.000Z"
}
```

It rewrites the file only when a value actually changes (checked once a minute), and
deletes it on disposal — so a stopped server leaves no stale port behind. The file is
removed only when its `pid` is the current process.

## Install

```sh
dsh plugin --profile web add dsh-dock-bridge
```

or from a checkout, with a path:

```sh
dsh plugin --profile web add /path/to/dsh-dock-launcher/plugins/dsh-dock-bridge
```

Then restart the Web profile. The plugin is a host row inserted by
[`cordis.patch.yml`](cordis.patch.yml); remove that insert and the harness behaves
exactly as before — the Dock app falls back to reading the startup log.

## Configuration

| Field | Default | Meaning |
|---|---|---|
| `path` | `~/.config/dsh-dock-launcher/runtime.json` | Runtime file location |

The `DSH_DOCK_RUNTIME` environment variable overrides the default path.

## Security

- The file contains a **live launch token**, so it is written owner-only (`0600`) and
  the token is never logged — only the redacted origin and PID are.
- Loopback only. The plugin opens no socket, makes no network request, and sends
  nothing anywhere.
- Zero dependencies, no build step, plain ESM. Every step is guarded so a failure can
  only log and stop; it never throws into the host's startup path.

## License

MIT

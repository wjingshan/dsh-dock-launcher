/**
 * dsh-dock-bridge — host-side companion for the DeepSeek Harness Switch Dock app.
 *
 * The Web surface authenticates every Host RPC method and WebSocket stream with a
 * per-process launch token that `dsh-web-app` prints as `?token=...`. A Dock app
 * that opens the bare origin would land on a 401 page, and the only other way to
 * recover the token is to parse the server's startup log.
 *
 * This plugin publishes the facts directly instead: the process PID, the bound
 * loopback port, the clean origin, and the tokenized root URL returned by
 * `ctx.connection.authenticatedUrl()`. It writes them to
 *
 *     ~/.config/dsh-dock-launcher/runtime.json      (mode 0600)
 *
 * on activation, refreshes the file when a value actually changes, and removes it
 * on disposal (so a stopped server leaves no stale port behind).
 *
 * Design constraints, in order:
 *   1. Never break the host. Every step is guarded; a failure logs and stops.
 *   2. No dependencies and no build step — plain ESM.
 *   3. The file carries a live credential, so it is owner-only (0600).
 *
 * @module dsh-dock-bridge
 */

import { chmodSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'

/** Plugin name; also the row id inserted by `cordis.patch.yml`. */
export const name = 'dsh-dock-bridge'

/**
 * Both services must exist before the row activates. `webserver` owns the bound
 * port, `connection` owns the per-process launch token.
 */
export const inject = ['webServer', 'connection']

/** Default runtime file location, shared with the Dock app. */
export const DEFAULT_RUNTIME_PATH = join(
  homedir(),
  '.config',
  'dsh-dock-launcher',
  'runtime.json',
)

/** How long to wait for the server to report a bound port before giving up. */
const READY_TIMEOUT_MS = 15_000
const READY_POLL_MS = 250

/** How often the file is re-checked for changes (token rotation, port rebind). */
const REFRESH_MS = 60_000

/**
 * Publish this process's endpoint facts for the Dock app.
 *
 * @param {object} ctx - Cordis context; injects `webServer` and `connection`.
 * @param {{ path?: string }} [config] - optional overrides.
 */
export function apply(ctx, config = {}) {
  const runtimePath =
    (typeof config.path === 'string' && config.path) ||
    process.env.DSH_DOCK_RUNTIME ||
    DEFAULT_RUNTIME_PATH

  /** Last payload serialized, so an unchanged state never rewrites the file. */
  let lastWritten
  let readyTimer
  let refreshTimer
  let disposed = false

  const debug = (message) => {
    try {
      ctx.logger?.debug?.(`[dsh-dock-bridge] ${message}`)
    } catch {
      /* logging must never be the reason a plugin fails */
    }
  }

  /** Read the bound port, or 0 while the server has not listened yet. */
  const boundPort = () => {
    const port = ctx.webServer?.port
    return Number.isInteger(port) && port > 0 ? port : 0
  }

  /** Build the payload for the current state; returns null while not ready. */
  const snapshot = () => {
    const port = boundPort()
    if (!port) return null

    const origin = `http://127.0.0.1:${port}/`
    let url = origin
    try {
      const tokenized = ctx.connection?.authenticatedUrl?.(origin)
      if (typeof tokenized === 'string' && tokenized.length > origin.length) {
        url = tokenized
      }
    } catch (error) {
      debug(`authenticatedUrl failed, publishing the clean origin: ${error}`)
    }

    return {
      pid: process.pid,
      host: '127.0.0.1',
      port,
      origin,
      url,
      tokenized: url !== origin,
      updatedAt: new Date().toISOString(),
    }
  }

  /** Write the file when the state changed. Returns true when it wrote. */
  const publish = () => {
    if (disposed) return false
    const payload = snapshot()
    if (!payload) return false

    const body = `${JSON.stringify(payload, null, 2)}\n`
    if (body === lastWritten) return false

    try {
      mkdirSync(dirname(runtimePath), { recursive: true })
      writeFileSync(runtimePath, body, { mode: 0o600 })
      // writeFileSync honors mode only on creation, so enforce it every time.
      chmodSync(runtimePath, 0o600)
      lastWritten = body
      // The URL carries a live token; log the redacted origin only.
      debug(`published ${payload.origin} (pid ${payload.pid}) to ${runtimePath}`)
      return true
    } catch (error) {
      debug(`cannot write ${runtimePath}: ${error}`)
      return false
    }
  }

  /** Remove the file, but only when this process owns it. */
  const cleanup = () => {
    try {
      const current = JSON.parse(readFileSync(runtimePath, 'utf8'))
      if (current?.pid !== process.pid) return
      rmSync(runtimePath, { force: true })
      debug(`removed ${runtimePath}`)
    } catch {
      /* absent, unreadable, or someone else's file — leave it alone */
    }
  }

  const stopTimers = () => {
    if (readyTimer) clearTimeout(readyTimer)
    if (refreshTimer) clearInterval(refreshTimer)
    readyTimer = undefined
    refreshTimer = undefined
  }

  const waitUntilReady = (deadline) => {
    if (disposed) return
    if (publish()) {
      // Keep the file honest if the port or token ever changes.
      refreshTimer = setInterval(publish, REFRESH_MS)
      refreshTimer.unref?.()
      return
    }
    if (Date.now() >= deadline) {
      debug('server never reported a bound port; nothing published')
      return
    }
    readyTimer = setTimeout(() => waitUntilReady(deadline), READY_POLL_MS)
    readyTimer.unref?.()
  }

  /**
   * The host does not necessarily dispose the plugin tree on the way out: a
   * SIGTERM/SIGINT shutdown can exit straight from the CLI's own signal path,
   * and then a `dispose`-only cleanup leaves a stale file naming a dead PID.
   * `process.on('exit')` is the one hook that still runs there, and it is the
   * documented home for synchronous cleanup. It only observes the exit — it
   * never changes how the process terminates.
   */
  const onProcessExit = () => cleanup()

  // Guarded so that no failure here can reach the host's startup path.
  try {
    process.on('exit', onProcessExit)
    waitUntilReady(Date.now() + READY_TIMEOUT_MS)
  } catch (error) {
    debug(`activation failed: ${error}`)
  }

  ctx.on('dispose', () => {
    disposed = true
    stopTimers()
    cleanup()
    // A reloaded plugin must not leave its listener behind.
    try {
      process.off('exit', onProcessExit)
    } catch {
      /* nothing to detach */
    }
  })
}

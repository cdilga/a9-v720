# Fork notes — cdilga/a9-v720

Fork of [intx82/a9-v720](https://github.com/intx82/a9-v720) with local reliability
fixes for the STA-mode fake server, packaged as a published container image so it
can be deployed by *pulling* an immutable tag (no build on the deploy host).

## What's different from upstream

- **`src/v720_sta.py`** — three independent reliability fixes for newer field
  firmware (observed `202312111512`), each upstreamable:
  1. **Handle `P2P_UDP_CMD_PCM` (cmd 6) without flooding.** That firmware
     interleaves a PCM audio stream with the JPEG frames; upstream has no handler
     so every PCM packet is logged as a multi-line "Unknown request" WARNING —
     ~1200 msg/min while any client streams (Frigate keeps a stream open 24/7).
     We consume PCM silently and log its presence once per session. (We do NOT
     surface PCM audio and do NOT ACK it — the camera streams video fine without
     ACKing PCM, confirmed empirically.)
  2. **Null-guard the retransmission-confirm send.** The 100 ms retransmit timer
     (daemon thread) races teardown, which sets `self._udp = None` → `None.send`.
  3. **Fan out each JPEG frame to all listeners.** Upstream assembled the frame
     *inside* the per-callback loop and drained the shared queue, so with >1
     registered callback the first got the frame and the rest got an empty one —
     which broke `/snapshot` whenever a live client was connected.
- **Colour control (`IrLed`, command 202) in STA mode.** Upstream can only send
  this from AP mode (`--irled`), so a server-mode deployment has no way to reach
  it — and the camera *persists* the setting, so a unit that was ever put into
  "IR" mode streams **monochrome forever** (chroma planes a flat 128) with no
  way to tell why. Note 202 drives no illuminator on most boards: the IR LED
  footprint is unpopulated (only Q1 + R1 and the IR+/- header are fitted), so
  its only observable effect is switching the ISP to monochrome — see
  [upstream #20](https://github.com/intx82/a9-v720/issues/20).
  - `v720_sta.ir_led(bool)` sends `{"code":202,"IrLed":0|1}` inside the same
    `301` forward envelope already used for base-info/open-video.
  - **`V720_IR_LED`** env: `0` = colour, `1` = b&w, unset = send nothing
    (upstream behaviour). Re-applied on every (re)registration — the camera
    drops and re-registers regularly, so a one-shot would not stick.
  - **`GET /dev/<uid>/ir`** reports the mode; **`?on=0|1`** sets it live.
  - The base-info blob is now logged at INFO (it carries the camera's persisted
    `IrLed`/`instLed`), and an unknown `/dev/<uid>/<cmd>` returns 404 instead of
    hanging the client with no response.
- **`Dockerfile`** — COPY-based build (no build-time `git clone`), Python 3.11
  (upstream uses `Thread.setDaemon/setName`, removed in 3.12), opencv-headless.
- **`.github/workflows/docker-publish.yml`** — builds and pushes
  `ghcr.io/cdilga/a9-v720` on push to `naxclow-fixes`/`master` and on `v*` tags.

## Deploy

Pull an immutable tag from GHCR — do not build on the host:

```
image: ghcr.io/cdilga/a9-v720:<tag>
```

Ports: `80/tcp` (bootstrap + MJPEG out), `6123/tcp` + `6123/udp` (control + media).
Run with host networking (the camera is handed the server's own LAN IP at
`getA9ConfCheck` time).

## Upstreaming

The `v720_sta.py` fixes are candidates for an upstream PR to intx82/a9-v720; the
packaging/CT is deployment-specific and stays in the fork.

# Luckfox Startup Workflow (SeedSigner)

This page documents the runtime startup sequence on Luckfox Pico hardware, with emphasis on execution order and memory behavior on the Luckfox Pico Mini.

## Goal

Bring up:
- SeedSigner UI (`python main.py`)
- Camera stack (`rk_dvbm`, `video_rkisp`, `video_rkcif`, `sc3336`)
- `rkaiq_3A_server` for real-time auto-exposure

while avoiding startup-time memory contention that can crash SeedSigner on Mini.

## Why startup order matters on Mini

The Mini is memory-constrained. If camera services are started too early, SeedSigner can fail opening SPI display resources (`/dev/spidev0.0`) due to memory pressure during init.

Observed reliable behavior:
1. Start SeedSigner first.
2. Wait for display/SPI initialization.
3. Start `rkaiq_3A_server` afterward.

Observed unreliable behavior:
1. Start `rkaiq_3A_server` first.
2. Then start SeedSigner.
3. SeedSigner may fail during startup (display init).

## Current runtime components

### Entry point
- `buildroot/files/S99seedsigner`
  - Executes `/start-seedsigner.sh`

### Main orchestrator
- `buildroot/files/start-seedsigner.sh`
  - Kills stale `rkipc` (if present)
  - Optionally bootstraps camera graph via temporary `rkipc`
  - Runs retry loop for SeedSigner startup
  - Starts camera service only after app init conditions are met

### Camera service wrapper
- `buildroot/files/rkaiq-service` (installed as `/usr/bin/rkaiq-service`)
  - Loads camera kernel modules if missing
  - Exports `LD_LIBRARY_PATH` for Rockchip libs
  - Starts/stops `/oem/usr/bin/rkaiq_3A_server`
  - Writes logs to `/tmp/rkaiq_3A_server.log`

## Disabled services

The following unnecessary services are removed or disabled during the build to
reduce image bloat and improve boot time on this air-gapped device:

- **rkipc** – Full IP camera server. Autostart in `RkLunch.sh` is commented out
  because SeedSigner only needs `rkaiq_3A_server` for camera auto-exposure.
- **Samba (smbd/nmbd)** – Network file sharing binaries and configuration
  removed from rootfs.
- **adbd** – Android Debug Bridge daemon removed from rootfs.
- **Unnecessary init.d scripts** – Any default SDK init scripts for samba or
  lunch-init are removed.

## No boot autostart for camera service

`rkaiq-service` is intentionally installed to `/usr/bin/rkaiq-service` (not as `/etc/init.d/S50...`) so it is not started by generic boot order before SeedSigner.

SeedSigner controls when camera service starts.

## Adaptive retry logic

`start-seedsigner.sh` includes adaptive behavior to handle board and boot-media timing differences (SPI-NAND vs microSD):

- On each retry:
  - Stop camera service (`rkaiq-service stop`)
  - Kill stale `rkipc`
  - Restart SeedSigner cleanly
- Camera service start is delayed until:
  - SeedSigner process is alive
  - SPI init signal is detected (via process fds), then an additional delay is applied
- Delay increases slightly per retry:
  - `camera_post_spi_delay = CAMERA_POST_SPI_DELAY + retry_count`

This gives the UI more headroom to initialize first, especially on Mini and on slower boot timing paths.

## Why `rkaiq_3A_server` is required

The critical function provided by `rkaiq_3A_server` is:
- **real-time automatic exposure adjustment** for camera capture.

Without it, camera frames may be available but exposure behavior is degraded/static.

## Field validation checklist

After boot:

1. Verify media/video nodes:
```sh
ls -l /dev/media* /dev/video* /dev/v4l-subdev* 2>/dev/null
```

2. Verify SeedSigner + camera service processes:
```sh
ps | grep -E "python|rkaiq_3A_server|rkipc" | grep -v grep
```

3. Check startup and camera logs:
```sh
tail -n 120 /tmp/startup.log
tail -n 120 /tmp/rkaiq_3A_server.log
```

4. Functional check in app:
- Camera scan works
- Exposure adjusts dynamically in changing light

## Notes for future changes

- Treat startup order as a functional requirement, not just cleanup.
- Test both Mini and Max, and both SPI-NAND and microSD boot timing.
- If memory regressions reappear, adjust post-SPI camera delay and retry backoff before changing camera features.

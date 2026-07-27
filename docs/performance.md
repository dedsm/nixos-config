# Desktop responsiveness tuning (`dedsm.performance`)

`modules/nixos/performance` ports the parts of [CachyOS](https://cachyos.org/) that are worth having on manwe, using packages that are already in nixpkgs. Enabled on manwe; off by default everywhere else.

The premise: CachyOS's reputation for feeling faster comes mostly from **scheduling and process-priority** work, not from its `-O3`/`x86-64-v3` package rebuilds. The scheduling parts are in nixpkgs already, so this needs no third-party flake input and no extra substituter.

Everything here is revertible without a reboot.

## What it enables

### 1. sched_ext via `services.scx` (`scx_lavd`)

sched_ext (mainline since kernel 6.12) lets the CPU scheduler be loaded as a BPF program instead of using the kernel's built-in EEVDF. `scx` is the upstream project shipping the schedulers and the loader daemon.

`scx_lavd` is latency- and power-aware. The gain is behaviour under load: when something saturates the cores — a `nixos-rebuild`, a large build, a browser with many tabs — the compositor, input handling and audio keep their timing instead of being fair-shared into stutter. It trades a little throughput for that.

Safety properties worth knowing:

- The kernel watchdogs the BPF scheduler. If it stalls a runnable task past a timeout, the kernel evicts it and EEVDF resumes automatically.
- The unit is gated on `ConditionPathIsDirectory=/sys/kernel/sched_ext`, so on a kernel without sched_ext it simply doesn't start — it can't fail the boot.
- It only governs `SCHED_NORMAL`/`BATCH`/`IDLE`. Real-time threads (pipewire) stay with the kernel's RT class.

Change scheduler per host with `dedsm.performance.scheduler`. `scx_bpfland` is the main alternative (interactive-focused, less power-aware). Note nixpkgs defaults `services.scx.scheduler` to `scx_rustland`, which runs its policy in userspace — an experimentation vehicle, not a fast default. The module overrides it.

### 2. `ananicy-cpp` with the CachyOS rule set

Applies `nice`/`ioclass`/cgroup assignments per process name from a rule set covering hundreds of binaries, so compilers and indexers yield to the compositor, terminal and browser.

This composes with scx rather than duplicating it: scx decides *when* runnable tasks run, ananicy decides *what priority they ask for*. `nice` still feeds the scx scheduler's weight calculation, and `ionice` is block-layer, independent of the CPU scheduler.

Both `package` and `rulesProvider` are overridden, because both nixpkgs defaults point at `pkgs.ananicy` — the dormant 2023 shell implementation with its equally old rules. The maintained lineages are `ananicy-cpp` (C++ rewrite) and `ananicy-rules-cachyos`.

### 3. Writeback sysctls

| sysctl | value | effect |
| --- | --- | --- |
| `vm.dirty_bytes` | 256 MiB | a process generating writes starts writing out dirty data itself at this point |
| `vm.dirty_background_bytes` | 64 MiB | background flusher threads wake here, before the limit above |
| `vm.dirty_writeback_centisecs` | 1500 (15s) | interval between flusher wakeups |

This is the item most likely to produce a *noticeable* difference on manwe, and it isn't really a CachyOS feature — it's that the kernel's defaults are wrong for 128 GiB of RAM. The defaults are ratios (`dirty_ratio=20`, `dirty_background_ratio=10`), so ~25 GiB of dirty pages can accumulate before a writer is throttled, with background flush starting around 12 GiB. Draining that to NVMe in one go stalls the system for seconds — the "copied a big file and the desktop froze" pattern, easy to hit with nix builds and VM images. Absolute caps turn one long stall into continuous small writeback.

Setting the `*_bytes` knobs implicitly zeroes the `*_ratio` counterparts; the kernel treats them as mutually exclusive.

### 4. `vm.vfs_cache_pressure = 50`

Biases reclaim away from the dentry/inode cache and towards the page cache. The Nix store is millions of small files behind deep symlink chains, so evaluation, store traversal and GC are metadata-heavy and benefit from a warm dentry cache. 128 GiB leaves room for it. (Default is 100. Never set 0 — it invites OOM.)

## Deliberately not taken from CachyOS

These come from [`CachyOS-Settings`](https://github.com/CachyOS/CachyOS-Settings) and are wrong for this machine:

- **`vm.swappiness = 100`, `vm.page-cluster = 0`** — tuned for zram, which CachyOS ships by default. manwe has 128 GiB and a physical swap partition that exists for hibernation, so it should essentially never swap; these would make the kernel *more* eager to page out to a partition we want left alone. zram itself is pointless at this RAM size.
- **`fs.file-max = 2097152`** — the kernel auto-sizes this from RAM at roughly `pages/10`, which is ~3.3M at 128 GiB. Setting CachyOS's value would *lower* the limit. It's tuned for an 8–16 GiB machine.
- **`kernel.unprivileged_userns_clone = 1`** — an Arch/Debian kernel patch knob that doesn't exist on mainline; `systemd-sysctl` would just log a failure. NixOS covers this with `security.allowUserNamespaces` (on by default).
- **NVMe I/O scheduler → `kyber`** (their `60-ioschedulers.rules`) — mainline defaults NVMe to `none` because the device queues are deep enough that software scheduling mostly adds overhead. Speculative benefit; revisit only if read stalls during heavy writes are actually observed.
- **The CachyOS kernel** (`linuxPackages_cachyos`, via the [chaotic-nyx](https://nyx.chaotic.cx/) flake) — BORE and scx_lavd address the same complaint, so with sched_ext enabled the delta over `linuxPackages_latest` is small. The cost isn't: a third-party input tracking `nyxpkgs-unstable` against our 26.05 pin, a substituter to trust, a two-stage rollout (their module must be enabled and rebuilt *before* adding the derivations, or an LTO kernel compiles locally), and a kernel swap on a machine with LUKS, btrfs subvolumes and a hibernation path that took work to get right — see [`hibernation.md`](./hibernation.md).

`services.system76-scheduler` was considered as the ananicy alternative and rejected for this host. Its central feature is a "latency profile" of CFS tunables (`sched_latency_ns`, `sched_wakeup_granularity_ns`, …) that no longer exist since EEVDF replaced CFS in 6.6 — and running scx bypasses the in-kernel scheduler's tunables anyway. Its other differentiator, foreground/background switching, needs the desktop to report focus over D-Bus, which exists for COSMIC and GNOME but not Hyprland. What remains is nice/ioclass assignment, which ananicy does with a much larger maintained rule set. Run one or the other, never both — they would both write `nice` on the same PIDs.

## Verifying

```bash
# sched_ext available, and the daemon actually running the intended scheduler
ls /sys/kernel/sched_ext
systemctl status scx

# ananicy running and matching rules
systemctl status ananicy-cpp

# sysctls landed
sysctl vm.dirty_bytes vm.dirty_background_bytes vm.dirty_writeback_centisecs vm.vfs_cache_pressure
```

To A/B test the scheduler without rebuilding, `sudo systemctl stop scx` and use the machine — EEVDF takes back over immediately. `systemctl start scx` to return. This is a feel change, not a benchmark change: throughput will not improve, so the honest test is daily use for a week and then turning it off to see whether the machine gets worse.

# Sleep & hibernation (manwe)

Why the laptop sleeps the way it does, and what is deliberately tuned. All of
this lives in `modules/nixos/laptop/default.nix` except `boot.resumeDevice`,
which is host-specific and sits in `hosts/manwe/hardware-configuration.nix`.

## The hardware constraint

manwe is a Framework 13 (AMD Ryzen AI 9 HX 370, Strix Point) with **128 GiB of
RAM**. `/sys/power/mem_sleep` offers **`s2idle` only** — this platform exposes
`S0 S4 S5`, so there is no S3 to fall back to.

Measured s2idle drain, taken from `/var/lib/upower/history-charge-*.dat` over
windows bounded by `PM: suspend entry` / `PM: suspend exit`, is **~1.4 %/h
(≈0.65 W)**, i.e. roughly **71 hours** from full to empty.

That is *not* a misconfiguration — it is the platform floor. DRAM self-refresh
on this model costs ~0.45 W per 48 GB stick against a ~0.23 W non-RAM baseline,
so ~1 W is the expected cost of keeping 128 GiB alive. The machine already runs
`powertop --auto-tune`, keeps all PCI runtime PM on `auto`, disables every ACPI
wakeup source except `PWRB` in `powerManagement.powerDownCommands`, and logs
zero `amd_pmc ... didn't reach deepest state` warnings.

**Conclusion: multi-day standby cannot come from tuning s2idle. It has to come
from actually reaching hibernate.**

## Suspend-then-hibernate

`services.logind.settings.Login` sets `HandleLidSwitch` and
`HandleLidSwitchExternalPower` to `suspend-then-hibernate`;
`HandleLidSwitchDocked` is `ignore`.

`systemd.sleep.settings.Sleep`:

| Setting | Value | Why |
|---|---|---|
| `HibernateMode` | `shutdown` | Real power-off rather than platform hibernate — the only mode that actually stops the drain. |
| `HibernateDelaySec` | `24h` | How long it sits in s2idle before writing the image. At 1.4 %/h this spends ~34% of the battery before hibernating. |
| `HibernateOnACPower` | `no` | No point burning a write cycle while plugged in. |

`image_size` is pinned to `0` via `systemd.tmpfiles.rules`, which tells the
kernel to make the image as small as it can rather than pre-sizing it against
RAM.

> **Note:** `HibernateDelaySec=24h` means that in practice the machine almost
> never reaches the hibernate stage — the retained journal shows 597 `s2idle`
> entries against a handful of hibernation attempts. Functionally it behaves as
> plain suspend. Shortening this is the single biggest lever on standby life,
> but see the reliability caveat below before doing so.

## Why `boot.resumeDevice` is set explicitly

`swapDevices` already names the swap LV, so `boot.resumeDevice` looks
redundant. It is not.

With a **systemd initrd** (`boot.initrd.systemd.enable = true`, which this host
uses), nixpkgs emits `resume=` on the kernel command line *only* from
`boot.resumeDevice`. Unlike the scripted initrd, there is **no `swapDevices`
fallback** — see [NixOS/nixpkgs#273053](https://github.com/NixOS/nixpkgs/issues/273053),
still open.

Without it, resume relies entirely on the volatile EFI `HibernateLocation`
variable. When that variable goes missing the machine cold-boots and the
session is lost silently — which is exactly what happened on 2026-07-25.
Setting `resumeDevice` also raises the resume job timeout from 2 minutes to
infinity.

Both `swapDevices` and `boot.resumeDevice` must therefore reference the same
UUID. **If the swap volume is ever recreated, update both.**

## Layout notes

- Swap is a **plain 64 GiB LV** (`nixos-swap`) sitting beside btrfs — *not* a
  btrfs swapfile. So there is no `resume_offset` to compute and none of the
  NODATACOW caveats apply.
- LUKS is opened in the initrd before the swap `.device` unit appears, so the
  resume device is available when it is needed.
- Secure Boot is disabled and no kernel lockdown is active — lockdown would
  block hibernation outright.
- **Latent trap:** `boot.tmp.useTmpfs = true` gives a ~63 GiB `/tmp` that
  systemd's pre-hibernate space check does *not* count but the kernel does. A
  full `/tmp` can fail a hibernate that systemd believed would fit.

## Reliability caveat, and `pm_async=0`

Hibernate *resume* on Ryzen AI 300 is a **known, unfixed** AMD/Framework bug,
with community reports of a 15–50% failure rate that worsens the longer the
machine stays hibernated. This machine's own history matches that shape.

`systemd.tmpfiles.rules` therefore also pins `/sys/power/pm_async` to `0`,
serialising device resume instead of bringing devices back in parallel. This is
a community A/B-tested workaround from a near-identical configuration (Ryzen AI
300, LVM-on-LUKS, 64 GiB swap), but it is **n=1 upstream — treat it as
experimental** and drop it if a proper kernel fix lands.

Because of this, **test hibernate deliberately** (`systemctl hibernate` with
nothing important open) after any change to this area, and before shortening
`HibernateDelaySec` to something that will trigger it unattended.

## Related

- [`login-flow.md`](./login-flow.md) — what happens on the way back up: hyprlock
  is the auth gate on resume, password-only after suspend.
- `hypridle` (`modules/common/users/common/wayland/hypridle/default.nix`) only
  locks and DPMS-offs; it has **no suspend listener**. Combined with
  `HandleLidSwitchDocked = "ignore"`, closing the lid while docked on battery
  leaves the machine fully awake.

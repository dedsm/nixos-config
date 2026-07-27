# Desktop responsiveness tuning, ported selectively from CachyOS.
#
# CachyOS's reputation for "feeling faster" is mostly scheduling and process
# priority work, not its -O3/x86-64-v3 rebuilds. Those two parts are already in
# nixpkgs (services.scx, ananicy-cpp, ananicy-rules-cachyos), so no third-party
# flake input or extra substituter is needed here.
#
# Everything in this module is revertible without a reboot: stop the two
# services and write the old sysctl values back.
#
# See docs/performance.md for what was deliberately NOT taken from CachyOS.
{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.performance;
in {
  options.dedsm.performance = {
    enable = mkOption {
      description = "Desktop responsiveness tuning (sched_ext, ananicy, writeback sysctls)";
      type = with types; bool;
      default = false;
    };

    scheduler = mkOption {
      description = ''
        Which sched_ext scheduler the scx daemon runs. scx_lavd is the
        latency-aware, power-aware one (came out of the handheld/gaming work);
        scx_bpfland is the general interactive alternative. Note that nixpkgs
        defaults services.scx.scheduler to scx_rustland, which runs its policy
        in userspace and is an experimentation vehicle, not a fast default.
      '';
      type = with types; str;
      default = "scx_lavd";
    };
  };

  config = mkIf cfg.enable {
    # sched_ext: load the CPU scheduler as a BPF program instead of using the
    # kernel's built-in EEVDF. Swappable at runtime (systemctl restart scx), and
    # the kernel watchdogs it — if the BPF scheduler stalls a runnable task past
    # a timeout it is evicted and EEVDF takes over automatically. Only governs
    # SCHED_NORMAL/BATCH/IDLE; real-time threads (pipewire) are untouched.
    #
    # The upstream unit is gated on ConditionPathIsDirectory=/sys/kernel/sched_ext,
    # so on a kernel built without sched_ext this silently does not start rather
    # than failing the boot. Requires kernel >= 6.12 (module asserts this).
    services.scx = {
      enable = true;
      scheduler = cfg.scheduler;
    };

    # ananicy-cpp: applies nice / ioclass / cgroup assignments per process name,
    # so compilers and indexers yield to the compositor, terminal and browser.
    # Complementary to scx rather than redundant: scx decides when runnable tasks
    # run, ananicy decides what priority they ask for. nice still feeds the scx
    # scheduler's weight calculation, and ionice is block-layer, so neither is
    # bypassed by running a BPF scheduler.
    services.ananicy = {
      enable = true;
      # Both of these override nixpkgs defaults, which point at pkgs.ananicy —
      # the dormant 2023 shell implementation and its equally old rules.
      # ananicy-cpp is the maintained C++ rewrite; the CachyOS rule set is the
      # maintained rule set (hundreds of binaries, refreshed continuously).
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
    };

    boot.kernel.sysctl = {
      # Writeback limits. The kernel's defaults are *ratios* of total RAM
      # (dirty_ratio=20, dirty_background_ratio=10), which are actively harmful
      # at manwe's 128 GiB: ~25 GiB of dirty pages may accumulate before a
      # process is forced to block, with background flush only starting at
      # ~12 GiB. Draining that to NVMe in one go stalls the whole system for
      # seconds (the "copied a big file and the desktop froze" pattern, easy to
      # hit with nix builds and VM images). Absolute byte caps turn one long
      # stall into continuous small writeback.
      #
      # Setting the *_bytes knobs implicitly zeroes their *_ratio counterparts;
      # the pair are mutually exclusive in the kernel.
      #
      # Force a writing process to start writing out dirty data itself at 256 MiB.
      "vm.dirty_bytes" = 268435456;
      # Wake the background flusher threads at 64 MiB, well before the limit
      # above, so writeback is usually already underway by the time it is hit.
      "vm.dirty_background_bytes" = 67108864;
      # Interval between flusher wakeups, in centiseconds: 15s instead of the
      # default 5s. Fewer wakeups (better for idle power) is safe precisely
      # because the two thresholds above now bound how much can pile up.
      "vm.dirty_writeback_centisecs" = 1500;

      # Bias reclaim away from the dentry/inode (VFS metadata) cache and towards
      # the page cache. The Nix store is millions of small files behind deep
      # symlink chains, so evaluation, store traversal and GC are metadata-heavy
      # and benefit directly from a warm dentry cache — and 128 GiB leaves ample
      # room to keep it. 100 is the default; do not set 0 (invites OOM).
      "vm.vfs_cache_pressure" = 50;
    };
  };
}

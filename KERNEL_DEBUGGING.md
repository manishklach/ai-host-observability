# Kernel Debugging Guide

This guide collects practical kernel-side debugging options that complement the observability scripts in this repo.

It is oriented toward host-side failures on accelerated Linux systems, especially:

- hidden memory pressure
- pinned-memory growth
- RDMA or `mlx5` registration blowups
- VFIO or IOMMU issues
- PCIe instability
- GPU-host mismatch symptoms

## Recommended Kernel Configs

These are the most useful `CONFIG_*` options for deeper inspection.

### Production-Friendly Observability

- `CONFIG_PSI`
- `CONFIG_CGROUPS`
- `CONFIG_DEBUG_FS`
- `CONFIG_FTRACE`
- `CONFIG_DYNAMIC_FTRACE`
- `CONFIG_TRACEPOINTS`
- `CONFIG_KPROBES`
- `CONFIG_KALLSYMS`
- `CONFIG_PSTORE`
- `CONFIG_PSTORE_CONSOLE`

For persistent crash logs, also enable a pstore backend such as:

- `CONFIG_PSTORE_RAM`
- `CONFIG_EFI_VARS_PSTORE`
- `CONFIG_PSTORE_BLK`

### Memory Attribution and Leak Hunting

- `CONFIG_PAGE_OWNER`
- `CONFIG_DEBUG_KMEMLEAK`

### Deep Interactive Debugging

- `CONFIG_KGDB`
- `CONFIG_KDB`
- `CONFIG_DEBUG_INFO`
- `CONFIG_FRAME_POINTER`

If your architecture supports `CONFIG_STRICT_KERNEL_RWX`, note that software breakpoints may be affected unless hardware breakpoints are available.

## High-Value Runtime Interfaces

### Pressure and Reclaim

- `/proc/pressure/memory`
- `/proc/pressure/cpu`
- `/proc/pressure/io`
- `/proc/vmstat`
- `/proc/meminfo`

Useful `vmstat` counters:

- `allocstall`
- `pgscan_kswapd`
- `pgscan_direct`
- `pgsteal_kswapd`
- `pgsteal_direct`
- `pswpin`
- `pswpout`
- `kswapd_low_wmark_hit_quickly`

### VM Sysctls

Useful `/proc/sys/vm/*` knobs:

- `watermark_scale_factor`
- `min_free_kbytes`
- `swappiness`
- `compact_unevictable_allowed`
- `stat_refresh`

Examples:

```bash
cat /proc/sys/vm/watermark_scale_factor
cat /proc/sys/vm/min_free_kbytes
cat /proc/sys/vm/stat_refresh
```

### Debugfs and Tracefs

- `/sys/kernel/debug`
- `/sys/kernel/tracing`

Relevant examples:

```bash
mount -t debugfs nodev /sys/kernel/debug
mount -t tracefs tracefs /sys/kernel/tracing
```

### Persistent Crash Logs

- `/sys/fs/pstore`

Useful on reboot after a crash or hang:

```bash
ls -l /sys/fs/pstore
```

## Recommended Tools by Problem Type

### 1. Slow Host Memory Blowup

Start with:

- `PSI`
- `/proc/vmstat`
- `page_owner`
- `mlx5` debugfs counters
- tracepoints or ftrace if you need timing context

Strongly consider:

- `CONFIG_PAGE_OWNER`
- `CONFIG_DEBUG_FS`

Why:

- This is usually an attribution and timing problem, not an interactive-stop problem.

### 2. Suspected Kernel Memory Leak

Start with:

- `kmemleak`
- `page_owner`
- `slab` and `vmstat` inspection

Strongly consider:

- `CONFIG_DEBUG_KMEMLEAK`
- `CONFIG_PAGE_OWNER`

Commands:

```bash
echo scan > /sys/kernel/debug/kmemleak
cat /sys/kernel/debug/kmemleak
```

### 3. Driver or RDMA Path Needs Timing Detail

Start with:

- `ftrace`
- tracepoints
- `dynamic_debug`
- kprobes

Useful because:

- They let you inspect the path without freezing the machine.

Examples:

```bash
echo function_graph > /sys/kernel/tracing/current_tracer
echo 1 > /sys/kernel/tracing/tracing_on
cat /sys/kernel/tracing/trace
```

Dynamic debug example:

```bash
echo 'module mlx5_core +p' > /sys/kernel/debug/dynamic_debug/control
```

### 4. Hard Hang or Crash in a Reproducible Path

Use:

- `KGDB`
- `KDB`
- `pstore`

Why:

- This is where you may need to stop inside the kernel, inspect call stacks, and break on functions.

### 5. Crash Logs Needed Across Reboot

Use:

- `pstore`
- `ramoops` or another pstore backend

Useful kernel command line patterns depend on platform, but persistent log capture is often more valuable than live stepping for crash triage.

## KGDB and KDB

### When KGDB Helps

`KGDB` is best for:

- reproducible hangs
- reproducible crashes
- driver bugs where you need source-level inspection
- checking variables, stacks, and breakpoints at exact kernel locations

### When KGDB Is Not the Best First Tool

Do not start with `KGDB` for:

- slow memory growth
- reclaim thrash
- pressure analysis
- “system became unhealthy over time” issues

Those usually respond better to:

- `PSI`
- `page_owner`
- `ftrace`
- `dynamic_debug`
- `pstore`

### Common KGDB Requirements

- `CONFIG_KGDB`
- `CONFIG_DEBUG_INFO`
- `CONFIG_FRAME_POINTER`

Often useful:

- `CONFIG_KDB`
- `CONFIG_KALLSYMS`

Kernel docs also describe:

- `kgdbwait` kernel parameter
- `kgdbcon`
- `kgdboc` sysfs/runtime configuration

Examples from the docs:

```bash
echo ttyS0 > /sys/module/kgdboc/parameters/kgdboc
echo 1 > /sys/module/debug_core/parameters/kgdb_use_con
```

## Page Owner

`page_owner` is especially useful when memory is being allocated but it is unclear who is responsible.

Typical workflow:

```bash
mount -t debugfs nodev /sys/kernel/debug
cat /sys/kernel/debug/page_owner > /tmp/page_owner.txt
```

On supported kernels, stack aggregation helpers may also be available under debugfs.

## Kmemleak

`kmemleak` is useful for suspected kernel memory leaks, but it is a debug feature and can add overhead.

Typical workflow:

```bash
mount -t debugfs nodev /sys/kernel/debug
echo scan > /sys/kernel/debug/kmemleak
cat /sys/kernel/debug/kmemleak
```

## Dynamic Debug

Dynamic debug is a good middle ground when you need more verbosity from a driver without rebuilding the kernel.

Example:

```bash
echo 'module mlx5_core +p' > /sys/kernel/debug/dynamic_debug/control
echo 'file drivers/net/* +p' > /sys/kernel/debug/dynamic_debug/control
```

You may also need higher console verbosity:

```bash
dmesg -n 8
```

## Tracefs and Ftrace

For timing-sensitive bugs, tracing is usually a better first move than `printk()`.

Basic example:

```bash
mount -t tracefs tracefs /sys/kernel/tracing
echo nop > /sys/kernel/tracing/current_tracer
echo 1 > /sys/kernel/tracing/events/enable
echo 1 > /sys/kernel/tracing/tracing_on
sleep 5
echo 0 > /sys/kernel/tracing/tracing_on
cat /sys/kernel/tracing/trace > /tmp/trace.txt
```

## PSI Monitors

PSI is not just for passive scraping. It also supports threshold-triggered monitoring.

Example trigger:

```bash
python3 - <<'PY'
import os, select
fd = os.open("/proc/pressure/memory", os.O_RDWR | os.O_NONBLOCK)
os.write(fd, b"some 150000 1000000")
p = select.poll()
p.register(fd, select.POLLPRI)
print("waiting")
while True:
    print(p.poll())
PY
```

This is useful when you want to wake up a userspace monitor when memory pressure crosses a threshold rather than polling continuously.

## Practical Recommendation

For the kind of issue that motivated this repo, a very strong kernel-debugging baseline is:

- `CONFIG_PSI`
- `CONFIG_DEBUG_FS`
- `CONFIG_FTRACE`
- `CONFIG_DYNAMIC_FTRACE`
- `CONFIG_TRACEPOINTS`
- `CONFIG_PAGE_OWNER`
- `CONFIG_PSTORE`
- `CONFIG_PSTORE_CONSOLE`
- `CONFIG_KALLSYMS`

Then add:

- `CONFIG_DEBUG_KMEMLEAK` when leak hunting
- `CONFIG_KGDB` and `CONFIG_KDB` when you truly need stop-the-world debugging

## References

- [KGDB/KDB](https://www.kernel.org/doc/html/v6.6/dev-tools/kgdb.html)
- [PSI](https://www.kernel.org/doc/html/v6.10/accounting/psi.html)
- [/proc/sys/vm](https://www.kernel.org/doc/html/latest/admin-guide/sysctl/vm.html)
- [trace debugging](https://www.kernel.org/doc/html/latest/trace/debugging.html)
- [dynamic debug](https://kernel.org/doc/html/next/admin-guide/dynamic-debug-howto.html)
- [page_owner](https://docs.kernel.org/6.9/mm/page_owner.html)
- [kmemleak](https://www.kernel.org/doc/html/v6.1/dev-tools/kmemleak.html)
- [pstore](https://docs.kernel.org/power/shutdown-debugging.html)

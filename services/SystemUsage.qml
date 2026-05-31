pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Internal

Singleton {
    id: root

    // CPU properties
    property string cpuName: ""
    property real cpuPerc
    property real cpuTemp

    // GPU properties
    readonly property string gpuType: GlobalConfig.services.gpuType.toUpperCase() || autoGpuType
    property string autoGpuType: "NONE"
    property string gpuName: ""
    property real gpuPerc
    property real gpuTemp

    // Memory properties
    property real memUsed
    property real memTotal
    readonly property real memPerc: memTotal > 0 ? memUsed / memTotal : 0

    // Rolling usage history (0..1) for the dashboard sparkline graphs
    readonly property int historyLength: 30
    readonly property CircularBuffer cpuBuffer: _cpuBuffer
    readonly property CircularBuffer gpuBuffer: _gpuBuffer
    readonly property CircularBuffer memBuffer: _memBuffer

    // Per-widget graph point interval (ms): config value, or the measure interval when 0.
    // Measurements within one point interval are averaged into a single graph point.
    readonly property int cpuGraphInterval: GlobalConfig.dashboard.performance.cpuGraphInterval > 0 ? GlobalConfig.dashboard.performance.cpuGraphInterval : GlobalConfig.dashboard.resourceUpdateInterval
    readonly property int gpuGraphInterval: GlobalConfig.dashboard.performance.gpuGraphInterval > 0 ? GlobalConfig.dashboard.performance.gpuGraphInterval : GlobalConfig.dashboard.resourceUpdateInterval
    readonly property int memGraphInterval: GlobalConfig.dashboard.performance.memGraphInterval > 0 ? GlobalConfig.dashboard.performance.memGraphInterval : GlobalConfig.dashboard.resourceUpdateInterval

    // Storage properties (aggregated)
    readonly property real storagePerc: {
        let totalUsed = 0;
        let totalSize = 0;
        for (const disk of disks) {
            totalUsed += disk.used;
            totalSize += disk.total;
        }
        return totalSize > 0 ? totalUsed / totalSize : 0;
    }

    // Individual disks: Array of { mount, used, total, free, perc }
    property var disks: []

    property real lastCpuIdle
    property real lastCpuTotal

    property int refCount

    // Graph aggregation: accumulate measurements, push their average once per graph interval
    property real _cpuSum: 0
    property int _cpuCount: 0
    property real _gpuSum: 0
    property int _gpuCount: 0
    property real _memSum: 0
    property int _memCount: 0

    // Drop the first sample of each measurement session — the shell/dashboard startup spikes
    // the GPU (and is generally unreliable), so it shouldn't become a graph point.
    property bool _cpuWarmed: false
    property bool _gpuWarmed: false
    property bool _memWarmed: false

    function _ticksPerPoint(graphInterval: int): int {
        return Math.max(1, Math.round(graphInterval / GlobalConfig.dashboard.resourceUpdateInterval));
    }

    function _pushCpu(): void {
        if (!_cpuWarmed) {
            _cpuWarmed = true;
            return;
        }
        _cpuSum += root.cpuPerc;
        _cpuCount++;
        if (_cpuCount >= _ticksPerPoint(root.cpuGraphInterval)) {
            _cpuBuffer.push(_cpuSum / _cpuCount);
            _cpuSum = 0;
            _cpuCount = 0;
        }
    }

    function _pushGpu(): void {
        if (!_gpuWarmed) {
            _gpuWarmed = true;
            return;
        }
        _gpuSum += root.gpuPerc;
        _gpuCount++;
        if (_gpuCount >= _ticksPerPoint(root.gpuGraphInterval)) {
            _gpuBuffer.push(_gpuSum / _gpuCount);
            _gpuSum = 0;
            _gpuCount = 0;
        }
    }

    function _pushMem(): void {
        if (!_memWarmed) {
            _memWarmed = true;
            return;
        }
        _memSum += root.memPerc;
        _memCount++;
        if (_memCount >= _ticksPerPoint(root.memGraphInterval)) {
            _memBuffer.push(_memSum / _memCount);
            _memSum = 0;
            _memCount = 0;
        }
    }

    function cleanCpuName(name: string): string {
        return name.replace(/\(R\)|\(TM\)|CPU|\d+(?:th|nd|rd|st) Gen |Core |Processor/gi, "").replace(/\s+/g, " ").trim();
    }

    function cleanGpuName(name: string): string {
        return name.replace(/\(R\)|\(TM\)|Graphics/gi, "").replace(/\s+/g, " ").trim();
    }

    function formatKib(kib: real): var {
        const mib = 1024;
        const gib = 1024 ** 2;
        const tib = 1024 ** 3;

        if (kib >= tib)
            return {
                value: kib / tib,
                unit: "TiB"
            };
        if (kib >= gib)
            return {
                value: kib / gib,
                unit: "GiB"
            };
        if (kib >= mib)
            return {
                value: kib / mib,
                unit: "MiB"
            };
        return {
            value: kib,
            unit: "KiB"
        };
    }

    // Always-on background service: the graph feeders (CPU/GPU/memory) measure continuously so
    // history is already populated whenever a widget is shown, not just while the dashboard is open.
    // The first sample is dropped via the _*Warmed flags (shell-start GPU spike).
    Timer {
        running: true
        interval: GlobalConfig.dashboard.resourceUpdateInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload();
            meminfo.reload();
            gpuUsage.running = true;
        }
    }

    // On-demand: storage usage and temperatures are only displayed inside the dashboard, so they
    // measure only while something refs the service (refCount > 0) to avoid needless lsblk/sensors runs.
    Timer {
        running: root.refCount > 0
        interval: GlobalConfig.dashboard.resourceUpdateInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            storage.running = true;
            sensors.running = true;
        }
    }

    CircularBuffer {
        id: _cpuBuffer

        capacity: root.historyLength + 1
    }

    CircularBuffer {
        id: _gpuBuffer

        capacity: root.historyLength + 1
    }

    CircularBuffer {
        id: _memBuffer

        capacity: root.historyLength + 1
    }

    // One-time CPU info detection (name)
    FileView {
        id: cpuinfoInit

        path: "/proc/cpuinfo"
        onLoaded: {
            const nameMatch = text().match(/model name\s*:\s*(.+)/);
            if (nameMatch)
                root.cpuName = root.cleanCpuName(nameMatch[1]);
        }
    }

    FileView {
        id: stat

        path: "/proc/stat"
        onLoaded: {
            const data = text().match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/);
            if (data) {
                const stats = data.slice(1).map(n => parseInt(n, 10));
                const total = stats.reduce((a, b) => a + b, 0);
                const idle = stats[3] + (stats[4] ?? 0);

                const totalDiff = total - root.lastCpuTotal;
                const idleDiff = idle - root.lastCpuIdle;
                root.cpuPerc = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0;

                root.lastCpuTotal = total;
                root.lastCpuIdle = idle;
                root._pushCpu();
            }
        }
    }

    FileView {
        id: meminfo

        path: "/proc/meminfo"
        onLoaded: {
            const data = text();
            root.memTotal = parseInt(data.match(/MemTotal: *(\d+)/)[1], 10) || 1;
            root.memUsed = (root.memTotal - parseInt(data.match(/MemAvailable: *(\d+)/)[1], 10)) || 0;
            root._pushMem();
        }
    }

    Process {
        id: storage

        // Get physical disks with aggregated usage from their partitions
        // -J triggers JSON output. -b triggers bytes.
        command: ["lsblk", "-J", "-b", "-o", "NAME,SIZE,TYPE,FSUSED,FSSIZE,MOUNTPOINT"]

        stdout: StdioCollector {
            onStreamFinished: {
                const data = JSON.parse(text);
                const diskList = [];
                const seenDevices = new Set();

                // Helper to recursively sum usage from children (partitions, crypt, lvm)
                const aggregateUsage = dev => {
                    let used = 0;
                    let size = 0;
                    let isRoot = dev.mountpoint === "/" || (dev.mountpoints && dev.mountpoints.includes("/"));

                    if (!seenDevices.has(dev.name)) {
                        // lsblk returns null for empty/unformatted partitions, which parses to 0 here
                        used = parseInt(dev.fsused) || 0;
                        size = parseInt(dev.fssize) || 0;
                        seenDevices.add(dev.name);
                    }

                    if (dev.children) {
                        for (const child of dev.children) {
                            const stats = aggregateUsage(child);
                            used += stats.used;
                            size += stats.size;
                            if (stats.isRoot)
                                isRoot = true;
                        }
                    }
                    return {
                        used,
                        size,
                        isRoot
                    };
                };

                for (const dev of data.blockdevices) {
                    // Only process physical disks at the top level
                    if (dev.type === "disk" && !dev.name.startsWith("zram")) {
                        const stats = aggregateUsage(dev);

                        if (stats.size === 0) {
                            continue;
                        }

                        const total = stats.size;
                        const used = stats.used;

                        diskList.push({
                            mount: dev.name,
                            used: used / 1024      // KiB
                            ,
                            total: total / 1024    // KiB
                            ,
                            free: (total - used) / 1024,
                            perc: total > 0 ? used / total : 0,
                            hasRoot: stats.isRoot
                        });
                    }
                }

                // Sort by putting the disk with root first, then sort the rest alphabetically
                root.disks = diskList.sort((a, b) => {
                    if (a.hasRoot && !b.hasRoot)
                        return -1;
                    if (!a.hasRoot && b.hasRoot)
                        return 1;
                    return a.mount.localeCompare(b.mount);
                });
            }
        }
    }

    // GPU name detection (one-time)
    Process {
        id: gpuNameDetect

        running: true
        command: ["sh", "-c", "nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || glxinfo -B 2>/dev/null | grep 'Device:' | cut -d':' -f2 | cut -d'(' -f1 || lspci 2>/dev/null | grep -i 'vga\\|3d controller\\|display' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const output = text.trim();
                if (!output)
                    return;

                // Check if it's from nvidia-smi (clean GPU name)
                if (output.toLowerCase().includes("nvidia") || output.toLowerCase().includes("geforce") || output.toLowerCase().includes("rtx") || output.toLowerCase().includes("gtx")) {
                    root.gpuName = root.cleanGpuName(output);
                } else if (output.toLowerCase().includes("rx")) {
                    root.gpuName = root.cleanGpuName(output);
                } else {
                    // Parse lspci output: extract name from brackets or after colon
                    // Handles cases like [AMD/ATI] Navi 21 [Radeon RX 6800/6800 XT / 6900 XT] (rev c0)
                    const bracketMatch = output.match(/\[([^\]]+)\][^\[]*$/);
                    if (bracketMatch) {
                        root.gpuName = root.cleanGpuName(bracketMatch[1]);
                    } else {
                        const colonMatch = output.match(/:\s*(.+)/);
                        if (colonMatch)
                            root.gpuName = root.cleanGpuName(colonMatch[1]);
                    }
                }
            }
        }
    }

    Process {
        id: gpuTypeCheck

        running: !GlobalConfig.services.gpuType
        command: ["sh", "-c", "if command -v nvidia-smi &>/dev/null && nvidia-smi -L &>/dev/null; then echo NVIDIA; elif ls /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | grep -q .; then echo GENERIC; else echo NONE; fi"]
        stdout: StdioCollector {
            onStreamFinished: root.autoGpuType = text.trim()
        }
    }

    Process {
        id: gpuUsage

        command: root.gpuType === "GENERIC" ? ["sh", "-c", "cat /sys/class/drm/card*/device/gpu_busy_percent"] : root.gpuType === "NVIDIA" ? ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits"] : ["echo"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.gpuType === "GENERIC") {
                    const percs = text.trim().split("\n");
                    const sum = percs.reduce((acc, d) => acc + parseInt(d, 10), 0);
                    root.gpuPerc = sum / percs.length / 100;
                } else if (root.gpuType === "NVIDIA") {
                    const [usage, temp] = text.trim().split(",");
                    root.gpuPerc = parseInt(usage, 10) / 100;
                    root.gpuTemp = parseInt(temp, 10);
                } else {
                    root.gpuPerc = 0;
                    root.gpuTemp = 0;
                }
                root._pushGpu();
            }
        }
    }

    Process {
        id: sensors

        command: ["sensors"]
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })
        stdout: StdioCollector {
            onStreamFinished: {
                let cpuTemp = text.match(/(?:Package id [0-9]+|Tdie):\s+((\+|-)[0-9.]+)(°| )C/);
                if (!cpuTemp)
                    // If AMD Tdie pattern failed, try fallback on Tctl
                    cpuTemp = text.match(/Tctl:\s+((\+|-)[0-9.]+)(°| )C/);

                if (cpuTemp)
                    root.cpuTemp = parseFloat(cpuTemp[1]);

                if (root.gpuType !== "GENERIC")
                    return;

                let eligible = false;
                let sum = 0;
                let count = 0;

                for (const line of text.trim().split("\n")) {
                    if (line === "Adapter: PCI adapter")
                        eligible = true;
                    else if (line === "")
                        eligible = false;
                    else if (eligible) {
                        let match = line.match(/^(temp[0-9]+|GPU core|edge)+:\s+\+([0-9]+\.[0-9]+)(°| )C/);
                        if (!match)
                            // Fall back to junction/mem if GPU doesn't have edge temp (for AMD GPUs)
                            match = line.match(/^(junction|mem)+:\s+\+([0-9]+\.[0-9]+)(°| )C/);

                        if (match) {
                            sum += parseFloat(match[2]);
                            count++;
                        }
                    }
                }

                root.gpuTemp = count > 0 ? sum / count : 0;
            }
        }
    }
}

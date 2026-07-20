import { performance } from 'node:perf_hooks';

function mib(bytes) { return Math.round(bytes / 1024 / 1024); }

export class BrokerHealthMonitor {
  snapshot() {
    const memory = process.memoryUsage();
    const cpu = process.cpuUsage();
    const eventLoop = performance.eventLoopUtilization();
    const heapUsageRatio = memory.heapTotal === 0 ? 0 : memory.heapUsed / memory.heapTotal;
    const status = heapUsageRatio > .85 || eventLoop.utilization > .90 ? 'degraded' : 'healthy';
    return {
      status,
      checkedAt: new Date().toISOString(),
      uptimeSeconds: Math.floor(process.uptime()),
      memory: {
        rssMiB: mib(memory.rss), heapUsedMiB: mib(memory.heapUsed),
        heapTotalMiB: mib(memory.heapTotal), heapUsageRatio: Number(heapUsageRatio.toFixed(3)),
      },
      cpu: { userMs: Math.round(cpu.user / 1_000), systemMs: Math.round(cpu.system / 1_000) },
      eventLoop: { utilization: Number(eventLoop.utilization.toFixed(3)) },
    };
  }
}

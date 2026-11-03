import { runMissionWorker } from './mission/worker.mjs';

process.on('unhandledRejection', (reason) => {
  console.error(JSON.stringify({
    evt: 'mission_worker.unhandled_rejection',
    error: reason instanceof Error ? reason.name : 'unknown',
  }));
  process.exitCode = 1;
});

await runMissionWorker();

import { fileURLToPath } from 'node:url';

import { AdminAuthService } from './auth.mjs';

export async function runAdminCli({
  argv = process.argv.slice(2),
  environment = process.env,
  output = console.log,
} = {}) {
  const [command] = argv;
  if (command !== 'reset-password') throw new Error('Supported command: reset-password');
  const password = environment.LUMANEST_ADMIN_RESET_PASSWORD;
  if (!password) throw new Error('LUMANEST_ADMIN_RESET_PASSWORD is required');
  const dataDirectory = environment.LUMANEST_DATA_DIR?.trim() || '/var/lib/lumanest';
  const auth = new AdminAuthService({
    filePath: `${dataDirectory}/admin-auth.json`,
    bootstrapPassword: password,
  });
  await auth.initialize();
  await auth.changePassword(password);
  output('Administrator password updated; all sessions were invalidated.');
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    process.exitCode = await runAdminCli();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

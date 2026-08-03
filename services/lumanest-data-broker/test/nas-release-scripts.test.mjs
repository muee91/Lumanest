import assert from 'node:assert/strict';
import { chmod, mkdir, mkdtemp, readFile, realpath, symlink, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const scripts = [
  new URL('../scripts/nas-deploy.sh', import.meta.url),
  new URL('../scripts/nas-rollback.sh', import.meta.url),
];

test('cached NAS builds reuse application images without reinstalling dependencies', async () => {
  const brokerDockerfile = await readFile(
    new URL('../Dockerfile.cached', import.meta.url),
    'utf8',
  );
  const contextDockerfile = await readFile(
    new URL('../../lumanest-context-service/Dockerfile.cached', import.meta.url),
    'utf8',
  );
  const compose = await readFile(new URL('../compose.yaml', import.meta.url), 'utf8');

  assert.match(
    brokerDockerfile,
    /ARG BROKER_BASE_IMAGE=qweather-token-broker-qweather-token-broker:latest\nFROM \$\{BROKER_BASE_IMAGE\}/,
  );
  assert.match(brokerDockerfile, /COPY src \.\/src/);
  assert.doesNotMatch(brokerDockerfile, /npm (?:ci|install)|package-lock\.json/);

  assert.match(
    contextDockerfile,
    /ARG CONTEXT_BASE_IMAGE=qweather-token-broker-context-service:latest\nFROM \$\{CONTEXT_BASE_IMAGE\}/,
  );
  assert.match(contextDockerfile, /COPY alembic \.\/alembic/);
  assert.match(contextDockerfile, /COPY app \.\/app/);
  assert.doesNotMatch(contextDockerfile, /pip install|pyproject\.toml/);

  assert.match(compose, /dockerfile: \$\{BROKER_DOCKERFILE:-Dockerfile\}/);
  assert.match(compose, /dockerfile: \$\{CONTEXT_DOCKERFILE:-Dockerfile\}/);
  assert.equal(
    compose.match(/DISCOVERY_BASE_IMAGE: \$\{DISCOVERY_BASE_IMAGE:-qweather-token-broker-context-service:latest\}/g)?.length,
    2,
  );
  assert.match(
    compose,
    /discovery-worker:[\s\S]*?depends_on:\n\s+qweather-token-broker:\n\s+condition: service_healthy/,
  );
  assert.match(
    compose,
    /NO_PROXY: [^\n]*lumanest-raster-service,lumanest-terrain-service/,
  );
  assert.match(compose, /HTTP_PROXY: \$\{LUMANEST_BUILD_PROXY_URL:-\}/);
  assert.match(compose, /host\.docker\.internal:host-gateway/);
});

test('Debian package builds use HTTPS with bounded network recovery', async () => {
  const dockerfiles = [
    new URL('../../lumanest-raster-service/Dockerfile', import.meta.url),
    new URL('../../lumanest-terrain-service/Dockerfile', import.meta.url),
    new URL('../../lumanest-discovery-service/Dockerfile.crawler', import.meta.url),
  ];

  for (const dockerfile of dockerfiles) {
    const source = await readFile(dockerfile, 'utf8');
    assert.match(source, /s\|http:\/\/deb\.debian\.org\|https:\/\/deb\.debian\.org\|g/);
    assert.match(source, /Acquire::Retries "5";/);
    assert.match(source, /Acquire::ForceIPv4 "true";/);
    assert.match(source, /Acquire::http::Timeout "60";/);
    assert.match(source, /Acquire::https::Timeout "60";/);
  }

  const crawler = await readFile(dockerfiles[2], 'utf8');
  assert.match(crawler, /PLAYWRIGHT_DOWNLOAD_CONNECTION_TIMEOUT=120000/);
});

test('production images pin base digests and hashed Python dependency locks', async () => {
  const pythonServices = [
    '../../lumanest-context-service',
    '../../lumanest-discovery-service',
    '../../lumanest-raster-service',
    '../../lumanest-terrain-service',
  ];
  const pythonDigest = /ARG PYTHON_IMAGE=python:3\.12-slim@sha256:[a-f0-9]{64}\nFROM \$\{PYTHON_IMAGE\}/;

  for (const service of pythonServices) {
    const dockerfile = await readFile(new URL(`${service}/Dockerfile`, import.meta.url), 'utf8');
    const lock = await readFile(new URL(`${service}/requirements.prod.txt`, import.meta.url), 'utf8');
    assert.match(dockerfile, pythonDigest);
    assert.match(dockerfile, /COPY requirements\.prod\.txt \.\//);
    assert.match(dockerfile, /--require-hashes --only-binary=:all: -r requirements\.prod\.txt/);
    assert.match(dockerfile, /--no-deps --no-build-isolation \./);
    assert.match(lock, /setuptools==\d+\.\d+\.\d+ \\\n\s+--hash=sha256:/);
    assert.match(lock, /wheel==\d+\.\d+\.\d+ \\\n\s+--hash=sha256:/);
  }

  const crawler = await readFile(
    new URL('../../lumanest-discovery-service/Dockerfile.crawler', import.meta.url),
    'utf8',
  );
  const broker = await readFile(new URL('../Dockerfile', import.meta.url), 'utf8');
  const compose = await readFile(new URL('../compose.yaml', import.meta.url), 'utf8');
  assert.match(crawler, pythonDigest);
  assert.match(crawler, /--require-hashes --only-binary=:all: -r requirements\.prod\.txt/);
  assert.match(crawler, /--no-deps --no-build-isolation \./);
  assert.match(broker, /ARG NODE_IMAGE=node:22-alpine@sha256:[a-f0-9]{64}/);
  assert.match(compose, /image: postgis\/postgis:17-3\.5@sha256:[a-f0-9]{64}/);
  assert.match(compose, /image: redis:7\.4-alpine@sha256:[a-f0-9]{64}/);
  for (const script of scripts) {
    assert.match(
      await readFile(script, 'utf8'),
      /BACKUP_HELPER_IMAGE=\$\{BACKUP_HELPER_IMAGE:-redis:7\.4-alpine@sha256:[a-f0-9]{64}\}/,
    );
  }
});

test('NAS release scripts are POSIX-valid and never require host root volume access', async () => {
  for (const script of scripts) {
    const path = fileURLToPath(script);
    const syntax = spawnSync('sh', ['-n', path], { encoding: 'utf8' });
    assert.equal(syntax.status, 0, syntax.stderr);
    const source = await readFile(path, 'utf8');
    assert.doesNotMatch(source, /Run this script with sudo|Mountpoint|mountpoint=/);
    assert.match(source, /docker info/);
    assert.match(source, /--network none --read-only --cap-drop ALL/);
    assert.match(source, /--security-opt no-new-privileges/);
  }
  const deploy = await readFile(scripts[0], 'utf8');
  const rollback = await readFile(scripts[1], 'utf8');
  assert.equal(
    deploy.match(/--cap-add DAC_OVERRIDE --cap-add FOWNER --cap-add CHOWN/g)?.length,
    2,
  );
  assert.match(rollback, /--cap-add DAC_OVERRIDE --cap-add FOWNER --cap-add CHOWN/);
});

test('rollback remains explicitly confirmed before destructive volume restore', async () => {
  const source = await readFile(scripts[1], 'utf8');
  assert.match(source, /CONFIRM_ROLLBACK/);
  assert.match(source, /Unsafe Docker volume name/);
  assert.match(source, /tar -C "\$staging" -xzf/);
  assert.match(source, /find \/target -mindepth 1/);
  assert.ok(source.indexOf('tar -C "$staging" -xzf') < source.indexOf('find /target -mindepth 1'));
});

test('deployment recovery restores archived volumes before starting the previous stack', async () => {
  const fixture = await deploymentFixture();
  const result = spawnSync('sh', [fixture.deployScript], {
    cwd: dirname(fixture.deployScript),
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${fixture.binDir}:${process.env.PATH}`,
      LUMANEST_ROOT: fixture.root,
      HEALTHCHECK_ATTEMPTS: '1',
      HEALTHCHECK_INTERVAL_SECONDS: '1',
      TEST_LOG: fixture.logFile,
      TEST_STATE: fixture.stateFile,
      TEST_VOLUME_SOURCE: fixture.volumeSource,
    },
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Previous stack, archived volumes, and application images restored successfully/);
  const log = await readFile(fixture.logFile, 'utf8');
  assert.match(log, /image save -o .*application-images\.tar/);
  assert.match(log, /image load -i .*application-images\.tar/);
  assert.match(log, /up -d --no-build --remove-orphans/);
  const buildIndex = log.split('\n').findIndex(
    (line) => line.startsWith('compose ') && line.endsWith(' build'),
  );
  const stopIndex = log.split('\n').findIndex((line) => line.startsWith('compose-stop:'));
  assert.ok(buildIndex >= 0, log);
  assert.ok(stopIndex > buildIndex, log);
  const restoreIndex = log.indexOf('restore-volume:');
  const previousStartIndex = log.indexOf(`compose-up:${fixture.previousRelease}`);
  assert.ok(restoreIndex >= 0, log);
  assert.ok(previousStartIndex > restoreIndex, log);
  assert.equal((await readFile(join(fixture.root, 'current-release'), 'utf8')).trim(), fixture.previousRelease);
  assert.match(await readFile(join(fixture.releaseDir, 'qweather-token-broker.env'), 'utf8'), /TEST_ONLY=1/);
});

test('deployment refuses a concurrent release before touching Docker', async () => {
  const fixture = await deploymentFixture();
  await mkdir(join(fixture.root, '.lumanest-deploy.lock'));
  const result = spawnSync('sh', [fixture.deployScript], {
    cwd: dirname(fixture.deployScript),
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${fixture.binDir}:${process.env.PATH}`,
      LUMANEST_ROOT: fixture.root,
      TEST_LOG: fixture.logFile,
    },
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Another LumaNest deployment is active/);
  assert.equal(await readFile(fixture.logFile, 'utf8'), '');
});

test('deployment derives a host-gateway BuildKit proxy from the protected Mihomo URL', async () => {
  const fixture = await deploymentFixture();
  await writeFile(
    join(fixture.previousRelease, 'qweather-token-broker.env'),
    'LUMANEST_OUTBOUND_NETWORK_MODE=mihomo\n' +
      'LUMANEST_OUTBOUND_PROXY_URL=http://mihomo:7890\n' +
      'LUMANEST_NETWORK_CONTROLLER_TOKEN=0123456789abcdef0123456789abcdef\n',
  );
  const result = spawnSync('sh', [fixture.deployScript], {
    cwd: dirname(fixture.deployScript),
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${fixture.binDir}:${process.env.PATH}`,
      LUMANEST_ROOT: fixture.root,
      SKIP_BUILD: '1',
      HEALTHCHECK_ATTEMPTS: '1',
      HEALTHCHECK_INTERVAL_SECONDS: '1',
      TEST_LOG: fixture.logFile,
      TEST_STATE: fixture.stateFile,
      TEST_VOLUME_SOURCE: fixture.volumeSource,
    },
  });

  assert.notEqual(result.status, 0);
  const environment = await readFile(
    join(fixture.releaseDir, 'qweather-token-broker.env'),
    'utf8',
  );
  assert.match(environment, /LUMANEST_BUILD_PROXY_URL=http:\/\/host\.docker\.internal:7890/);
  assert.match(await readFile(fixture.logFile, 'utf8'), /port mihomo 7890\/tcp/);
});

test('rollback health failure does not publish the restored release pointer', async () => {
  const fixture = await rollbackFixture();
  const result = spawnSync('sh', [fileURLToPath(scripts[1]), fixture.backupDir], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${fixture.binDir}:${process.env.PATH}`,
      CONFIRM_ROLLBACK: 'yes',
      LUMANEST_ROOT: fixture.root,
      HEALTHCHECK_ATTEMPTS: '1',
      HEALTHCHECK_INTERVAL_SECONDS: '1',
      TEST_LOG: fixture.logFile,
      TEST_CURL_MODE: 'fail',
    },
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /ROLLBACK FAILED/);
  assert.equal((await readFile(join(fixture.root, 'current-release'), 'utf8')).trim(), fixture.currentRelease);
  const log = await readFile(fixture.logFile, 'utf8');
  assert.match(log, new RegExp(`compose-down:${escapeRegex(fixture.currentRelease)}`));
  assert.match(log, new RegExp(`compose-up:${escapeRegex(fixture.liveDir)}`));
});

test('rollback rejects a backup path that resolves outside the backup root', async () => {
  const root = await mkdtemp(join(tmpdir(), 'lumanest-rollback-path-'));
  const outside = await mkdtemp(join(tmpdir(), 'lumanest-rollback-outside-'));
  await mkdir(join(root, 'backups'), { recursive: true });
  await symlink(outside, join(root, 'backups', 'escape'));

  const result = spawnSync('sh', [fileURLToPath(scripts[1]), join(root, 'backups', 'escape')], {
    encoding: 'utf8',
    env: { ...process.env, CONFIRM_ROLLBACK: 'yes', LUMANEST_ROOT: root },
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Backup must resolve under/);
});

test('rollback refuses to apply an older backup across a later active release', async () => {
  const fixture = await rollbackFixture();
  const laterRelease = join(fixture.root, 'releases', 'later', 'qweather-token-broker');
  await mkdir(laterRelease, { recursive: true });
  await Promise.all([
    writeFile(join(laterRelease, 'compose.yaml'), 'services: {}\n'),
    writeFile(join(laterRelease, 'qweather-token-broker.env'), 'TEST_ONLY=later\n'),
    writeFile(join(fixture.root, 'current-release'), `${laterRelease}\n`),
  ]);

  const result = spawnSync('sh', [fileURLToPath(scripts[1]), fixture.backupDir], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${fixture.binDir}:${process.env.PATH}`,
      CONFIRM_ROLLBACK: 'yes',
      LUMANEST_ROOT: fixture.root,
      TEST_LOG: fixture.logFile,
    },
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /This backup belongs to/);
  assert.equal(await readFile(fixture.logFile, 'utf8'), '');
});

test('release state writes and recovery failures remain explicit', async () => {
  const deploy = await readFile(scripts[0], 'utf8');
  const rollback = await readFile(scripts[1], 'utf8');
  assert.match(deploy, /restore_backup_volumes/);
  assert.match(deploy, /AUTOMATIC RECOVERY FAILED/);
  assert.doesNotMatch(deploy, /up -d --build \|\| true/);
  assert.match(deploy, /atomic_write "\$LUMANEST_ROOT\/current-release"/);
  assert.match(deploy, /application-images\.tar/);
  assert.match(deploy, /<title>栖光 · 管理台<\/title>/);
  assert.match(deploy, /verify_release_discovery_worker/);
  assert.match(deploy, /Discovery worker heartbeat check timed out/);
  assert.match(
    deploy,
    /while ! compose_release exec -T discovery-worker python -c/,
  );
  assert.match(deploy, /verify_release_feed_worker/);
  assert.match(deploy, /Discovery feed worker heartbeat check timed out/);
  assert.match(
    deploy,
    /while ! compose_release exec -T discovery-feed-worker python -c/,
  );
  assert.match(deploy, /sky_data_ready/);
  assert.match(deploy, /derive_build_proxy_url/);
  assert.match(deploy, /verify_build_proxy_endpoint/);
  assert.ok(deploy.indexOf('compose_release build') < deploy.indexOf('compose_previous stop'));
  assert.match(deploy, /Sky data profile disabled; Broker will keep sky facts unavailable/);
  assert.match(deploy, /acquire_deploy_lock/);
  assert.match(deploy, /release_deploy_lock/);
  assert.match(rollback, /verify_http_boundary/);
  assert.match(rollback, /atomic_write "\$LUMANEST_ROOT\/current-release"/);
});

test('deployment validates selected Dockerfiles before stopping the previous stack', async () => {
  const source = await readFile(scripts[0], 'utf8');
  const brokerRequirement = 'require_file "$RELEASE_DIR/$BROKER_DOCKERFILE"';
  const contextRequirement =
    'require_file "$RELEASE_DIR/../lumanest-context-service/$CONTEXT_DOCKERFILE"';
  const rasterRequirement =
    'require_file "$RELEASE_DIR/../lumanest-raster-service/$RASTER_DOCKERFILE"';
  const terrainRequirement =
    'require_file "$RELEASE_DIR/../lumanest-terrain-service/$TERRAIN_DOCKERFILE"';
  const stopPrevious = 'compose_previous stop';

  assert.match(source, /valid_identifier "\$BROKER_DOCKERFILE"/);
  assert.match(source, /valid_identifier "\$CONTEXT_DOCKERFILE"/);
  assert.ok(source.indexOf(brokerRequirement) >= 0);
  assert.ok(source.indexOf(contextRequirement) >= 0);
  assert.ok(source.indexOf(rasterRequirement) >= 0);
  assert.ok(source.indexOf(terrainRequirement) >= 0);
  assert.ok(source.indexOf(brokerRequirement) < source.indexOf(stopPrevious));
  assert.ok(source.indexOf(contextRequirement) < source.indexOf(stopPrevious));
  assert.ok(source.indexOf(rasterRequirement) < source.indexOf(stopPrevious));
  assert.ok(source.indexOf(terrainRequirement) < source.indexOf(stopPrevious));
});

async function deploymentFixture() {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'lumanest-deploy-')));
  const previousRelease = join(root, 'releases', 'old', 'qweather-token-broker');
  const releaseDir = join(root, 'releases', 'new', 'qweather-token-broker');
  const contextDir = join(root, 'releases', 'new', 'lumanest-context-service');
  const rasterDir = join(root, 'releases', 'new', 'lumanest-raster-service');
  const terrainDir = join(root, 'releases', 'new', 'lumanest-terrain-service');
  const deployScript = join(releaseDir, 'scripts', 'nas-deploy.sh');
  const binDir = join(root, 'test-bin');
  const volumeSource = join(root, 'volume-source');
  const logFile = join(root, 'commands.log');
  const stateFile = join(root, 'stack-state');

  await Promise.all([
    mkdir(join(previousRelease), { recursive: true }),
    mkdir(join(releaseDir, 'scripts'), { recursive: true }),
    mkdir(contextDir, { recursive: true }),
    mkdir(rasterDir, { recursive: true }),
    mkdir(terrainDir, { recursive: true }),
    mkdir(binDir, { recursive: true }),
    mkdir(volumeSource, { recursive: true }),
  ]);
  await Promise.all([
    writeFile(join(previousRelease, 'compose.yaml'), 'services: {}\n'),
    writeFile(join(previousRelease, 'qweather-token-broker.env'), 'TEST_ONLY=1\n'),
    writeFile(join(releaseDir, 'compose.yaml'), 'services: {}\n'),
    writeFile(join(releaseDir, 'Dockerfile'), 'FROM scratch\n'),
    writeFile(join(contextDir, 'Dockerfile'), 'FROM scratch\n'),
    writeFile(join(rasterDir, 'Dockerfile'), 'FROM scratch\n'),
    writeFile(join(terrainDir, 'Dockerfile'), 'FROM scratch\n'),
    writeFile(join(root, 'current-release'), `${previousRelease}\n`),
    writeFile(join(volumeSource, 'data.txt'), 'pre-migration\n'),
    writeFile(logFile, ''),
    writeFile(stateFile, 'old\n'),
    writeFile(deployScript, await readFile(scripts[0], 'utf8')),
  ]);
  await chmod(deployScript, 0o755);
  await writeExecutable(join(binDir, 'docker'), dockerStub());
  await writeExecutable(join(binDir, 'curl'), curlStub());

  return { root, previousRelease, releaseDir, deployScript, binDir, volumeSource, logFile, stateFile };
}

async function rollbackFixture() {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'lumanest-rollback-')));
  const currentRelease = join(root, 'releases', 'current', 'qweather-token-broker');
  const liveDir = join(root, 'releases', 'old', 'qweather-token-broker');
  const backupDir = join(root, 'backups', '20260715T000000Z');
  const volumeSource = join(root, 'volume-source');
  const binDir = join(root, 'test-bin');
  const logFile = join(root, 'commands.log');
  const volume = 'qweather-token-broker_lumanest-data';

  await Promise.all([
    mkdir(currentRelease, { recursive: true }),
    mkdir(liveDir, { recursive: true }),
    mkdir(join(backupDir, 'volumes'), { recursive: true }),
    mkdir(volumeSource, { recursive: true }),
    mkdir(binDir, { recursive: true }),
  ]);
  await Promise.all([
    writeFile(join(currentRelease, 'compose.yaml'), 'services: {}\n'),
    writeFile(join(currentRelease, 'qweather-token-broker.env'), 'TEST_ONLY=current\n'),
    writeFile(join(liveDir, 'compose.yaml'), 'services: {}\n'),
    writeFile(join(liveDir, 'qweather-token-broker.env'), 'TEST_ONLY=old\n'),
    writeFile(join(root, 'current-release'), `${currentRelease}\n`),
    writeFile(join(backupDir, 'manifest.env'), `PROJECT_NAME=qweather-token-broker\nLIVE_DIR=${liveDir}\nRELEASE_DIR=${currentRelease}\nCREATED_AT=20260715T000000Z\n`),
    writeFile(join(backupDir, 'volumes.txt'), `${volume}\n`),
    writeFile(join(volumeSource, 'data.txt'), 'pre-migration\n'),
    writeFile(logFile, ''),
  ]);
  createArchive(join(backupDir, 'volumes', `${volume}.tar.gz`), volumeSource, '.');
  createArchive(join(backupDir, 'live-source.tar.gz'), root, liveDir.slice(root.length + 1));
  await writeExecutable(join(binDir, 'docker'), dockerStub());
  await writeExecutable(join(binDir, 'curl'), curlStub());

  return { root, currentRelease, liveDir, backupDir, binDir, logFile };
}

function createArchive(destination, cwd, entry) {
  const result = spawnSync('tar', ['-C', cwd, '-czf', destination, entry], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
}

async function writeExecutable(path, source) {
  await writeFile(path, source);
  await chmod(path, 0o755);
}

function dockerStub() {
  return `#!/bin/sh
set -eu
printf '%s\\n' "$*" >> "$TEST_LOG"

if [ "$1" = "info" ]; then exit 0; fi
if [ "$1" = "port" ]; then printf '%s\n' '0.0.0.0:7890'; exit 0; fi
if [ "$1" = "inspect" ]; then
  case "$*" in
    *'{{.Config.Image}}'*) printf '%s\\n' 'qweather-token-broker-qweather-token-broker' ;;
    *) printf '%s\\n' 'sha256:test-image' ;;
  esac
  exit 0
fi
if [ "$1" = "image" ]; then
  if [ "$2" = "save" ]; then
    previous=''
    destination=''
    for argument in "$@"; do
      if [ "$previous" = "-o" ]; then destination=$argument; fi
      previous=$argument
    done
    printf 'test-image-archive\\n' > "$destination"
  fi
  exit 0
fi
if [ "$1" = "volume" ] && [ "$2" = "ls" ]; then
  printf '%s\\n' 'qweather-token-broker_lumanest-data'
  exit 0
fi
if [ "$1" = "volume" ]; then exit 0; fi

if [ "$1" = "run" ]; then
  archive=''
  backup=''
  restore=0
  for argument in "$@"; do
    case "$argument" in
      ARCHIVE=*) archive=\${argument#ARCHIVE=} ;;
      *:/backup) backup=\${argument%:/backup} ;;
      *:/backup:ro) backup=\${argument%:/backup:ro}; restore=1 ;;
    esac
  done
  if [ "$restore" -eq 1 ]; then
    printf 'restore-volume:%s\\n' "$archive" >> "$TEST_LOG"
  else
    tar -C "$TEST_VOLUME_SOURCE" -czf "$backup/$archive" .
    printf 'backup-volume:%s\\n' "$archive" >> "$TEST_LOG"
  fi
  exit 0
fi

if [ "$1" = "compose" ]; then
  compose_file=''
  previous=''
  for argument in "$@"; do
    if [ "$previous" = "-f" ]; then compose_file=$argument; fi
    previous=$argument
  done
  release_dir=\${compose_file%/compose.yaml}
  case "$*" in
    *' config --services') printf '%s\\n' 'qweather-token-broker'; exit 0 ;;
    *' config --quiet') exit 0 ;;
    *' ps -q qweather-token-broker') printf '%s\\n' 'test-broker-container'; exit 0 ;;
    *' stop') printf 'compose-stop:%s\\n' "$release_dir" >> "$TEST_LOG"; exit 0 ;;
    *' down --remove-orphans') printf 'compose-down:%s\\n' "$release_dir" >> "$TEST_LOG"; [ -n "\${TEST_STATE:-}" ] && printf 'down\\n' > "$TEST_STATE"; exit 0 ;;
    *' up -d --build --remove-orphans') printf 'compose-up:%s\\n' "$release_dir" >> "$TEST_LOG"; [ -n "\${TEST_STATE:-}" ] && printf '%s\\n' "$release_dir" > "$TEST_STATE"; exit 0 ;;
    *' up -d --no-build --remove-orphans') printf 'compose-up:%s\\n' "$release_dir" >> "$TEST_LOG"; [ -n "\${TEST_STATE:-}" ] && printf '%s\\n' "$release_dir" > "$TEST_STATE"; exit 0 ;;
    *' exec -T context-service '*) exit 0 ;;
    *' ps') exit 0 ;;
  esac
fi

exit 0
`;
}

function curlStub() {
  return `#!/bin/sh
set -eu
url=''
for argument in "$@"; do url=$argument; done
printf 'curl:%s\\n' "$url" >> "$TEST_LOG"

if [ "\${TEST_CURL_MODE:-}" = "fail" ]; then exit 22; fi
state=$(cat "$TEST_STATE" 2>/dev/null || true)
case "$state" in
  *'/releases/new/'*) exit 22 ;;
esac
case "$url" in
  *:8787/healthz) exit 0 ;;
  *:8788/admin) printf '200'; exit 0 ;;
  *:8787/admin) printf '404'; exit 0 ;;
esac
exit 22
`;
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

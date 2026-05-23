import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { careloopApiRoot, resolveCareLoopXcodeProject } from "./careloop-paths.js";

const bundleId = "com.careloop.ios";
const developerDir = process.env.DEVELOPER_DIR || "/Applications/Xcode.app/Contents/Developer";
const apiBaseUrl = process.env.CARELOOP_API_BASE_URL || "http://127.0.0.1:3000";
const manifestPath = path.join(os.tmpdir(), "careloop-demo-seed.json");
const derivedDataPath = path.join(os.tmpdir(), "careloop-demo-derived-data");
const apiLogPath = path.join(os.tmpdir(), "careloop-demo-api.log");
const careloopIOSProject = resolveCareLoopXcodeProject();

const preferredDeviceTargets = [
  { runtime: "iOS 26.5", name: "iPhone 17 Pro Max" },
  { runtime: "iOS 26.5", name: "iPhone 17e" },
  { runtime: "iOS 26.5", name: "iPhone Air" },
  { runtime: "iOS 26.5", name: "iPhone 17 Pro" },
];

function normalizeRuntimeLabel(value) {
  return value.replace(/[^a-z0-9]+/gi, "").toLowerCase();
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? careloopApiRoot,
    env: options.env ?? process.env,
    encoding: "utf8",
    stdio: options.stdio ?? "pipe",
    timeout: options.timeoutMs ?? 0,
  });

  if (result.status !== 0 && !options.allowFailure) {
    const stderr = (result.stderr || "").trim();
    const stdout = (result.stdout || "").trim();
    const errorSuffix = result.error?.code === "ETIMEDOUT"
      ? `\n\ntimeout:\nCommand exceeded ${options.timeoutMs}ms`
      : "";
    throw new Error(
      [
        `Command failed: ${command} ${args.join(" ")}`,
        stdout ? `stdout:\n${stdout}` : null,
        stderr ? `stderr:\n${stderr}` : null,
      ].filter(Boolean).join("\n\n") + errorSuffix,
    );
  }

  return result.stdout ?? "";
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}`);
  }
  return response.json();
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`${response.status} ${response.statusText}: ${text}`);
  }

  return response.json();
}

async function waitForHealth(timeoutMs = 30000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    try {
      const payload = await fetchJson(`${apiBaseUrl}/health`);
      if (payload?.status === "ok") return true;
    } catch {
      // keep polling
    }
    await delay(1000);
  }
  return false;
}

async function ensureApiRunning() {
  if (await waitForHealth(2000)) return { started: false, logPath: null };

  const logStream = fs.openSync(apiLogPath, "a");
  const child = spawn("npm", ["run", "start"], {
    cwd: careloopApiRoot,
    env: process.env,
    detached: true,
    stdio: ["ignore", logStream, logStream],
  });
  fs.closeSync(logStream);
  child.unref();

  const healthy = await waitForHealth(45000);
  if (!healthy) {
    throw new Error(`CareLoop API did not become healthy. Check ${apiLogPath}`);
  }

  return { started: true, logPath: apiLogPath };
}

function developerEnv(extra = {}) {
  return {
    ...process.env,
    DEVELOPER_DIR: developerDir,
    ...extra,
  };
}

function seedManifest() {
  const raw = run("node", [path.join(careloopApiRoot, "scripts", "seed-demo-showcase.js")]);
  fs.writeFileSync(manifestPath, raw, "utf8");
  return JSON.parse(raw);
}

async function refreshManifestTokens(manifest) {
  const password = manifest.defaultPassword;
  const emails = [...new Set(manifest.launchProfiles.map((profile) => profile.email))];
  const tokensByEmail = new Map();

  for (const email of emails) {
    const payload = await postJson(`${apiBaseUrl}/auth/login`, { email, password });
    tokensByEmail.set(email, payload.accessToken);
  }

  for (const user of Object.values(manifest.users ?? {})) {
    user.token = tokensByEmail.get(user.email) ?? user.token;
  }

  manifest.launchProfiles = manifest.launchProfiles.map((profile) => ({
    ...profile,
    token: tokensByEmail.get(profile.email) ?? profile.token,
  }));

  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  return manifest;
}

function appBundleId(appPath) {
  const infoPlistPath = path.join(appPath, "Info.plist");
  if (!fs.existsSync(infoPlistPath)) return null;

  const result = spawnSync("defaults", ["read", infoPlistPath.replace(/\.plist$/, ""), "CFBundleIdentifier"], {
    env: developerEnv(),
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });

  if (result.status !== 0) return null;
  return (result.stdout ?? "").trim() || null;
}

function buildIOSApp() {
  const appPath = path.join(derivedDataPath, "Build", "Products", "Debug-iphonesimulator", "CareLoop.app");
  const forceBuild = process.env.CARELOOP_DEMO_FORCE_BUILD === "1";
  const validExistingBuild = fs.existsSync(appPath) && appBundleId(appPath) === bundleId;

  if (forceBuild || !validExistingBuild) {
    if (!forceBuild) return null;
    fs.rmSync(derivedDataPath, { recursive: true, force: true });
    run(
      "xcodebuild",
      [
        "-project",
        careloopIOSProject,
        "-scheme",
        "CareLoop",
        "-destination",
        "generic/platform=iOS Simulator",
        "-derivedDataPath",
        derivedDataPath,
        "build",
      ],
      {
        env: developerEnv(),
        stdio: "pipe",
        timeoutMs: 300000,
      },
    );
  }

  return appPath;
}

function selectSimulatorDevices(requiredCount) {
  const raw = run("xcrun", ["simctl", "list", "devices", "available", "-j"], {
    env: developerEnv(),
  });
  const payload = JSON.parse(raw);
  const candidates = Object.entries(payload.devices ?? {})
    .flatMap(([runtime, devices]) =>
      devices.map((device) => ({
        ...device,
        runtime,
      })),
    )
    .filter((device) => device.isAvailable !== false)
    .filter((device) => preferredDeviceTargets.some((target) => target.name === device.name));

  const selected = [];
  for (const target of preferredDeviceTargets) {
    const normalizedTargetRuntime = normalizeRuntimeLabel(target.runtime);
    const match = candidates.find((device) =>
      device.name === target.name
      && normalizeRuntimeLabel(device.runtime).includes(normalizedTargetRuntime),
    );
    if (!match) continue;
    if (selected.some((device) => device.udid === match.udid)) continue;
    selected.push(match);
    if (selected.length === requiredCount) break;
  }

  if (selected.length < requiredCount) {
    throw new Error(`Only found ${selected.length} suitable simulators, but ${requiredCount} are required.`);
  }

  return selected;
}

function resetSimulatorWorkspace() {
  run("pkill", ["-f", "Simulator.app/Contents/MacOS/Simulator"], {
    env: process.env,
    allowFailure: true,
  });
  run("pkill", ["-f", "com.apple.CoreSimulator.CoreSimulatorService"], {
    env: process.env,
    allowFailure: true,
  });
  run("xcrun", ["simctl", "shutdown", "all"], {
    env: developerEnv(),
    stdio: "pipe",
    allowFailure: true,
  });
}

async function bootDevice(device) {
  run("xcrun", ["simctl", "boot", device.udid], {
    env: developerEnv(),
    stdio: "pipe",
    allowFailure: true,
  });
  run("xcrun", ["simctl", "bootstatus", device.udid, "-b"], {
    env: developerEnv(),
    stdio: "pipe",
    timeoutMs: 120000,
  });
}

function installedAppPath(device) {
  const appContainer = run("xcrun", ["simctl", "get_app_container", device.udid, bundleId, "app"], {
    env: developerEnv(),
    stdio: "pipe",
    allowFailure: true,
    timeoutMs: 15000,
  }).trim();

  return appContainer.length > 0 && fs.existsSync(appContainer) ? appContainer : null;
}

function hasInstalledApp(device) {
  return installedAppPath(device) !== null;
}

function resolveInstallSourceAppPath(devices, builtAppPath) {
  if (builtAppPath && appBundleId(builtAppPath) === bundleId) {
    return builtAppPath;
  }

  for (const device of devices) {
    const candidate = installedAppPath(device);
    if (candidate && appBundleId(candidate) === bundleId) {
      return candidate;
    }
  }

  return null;
}

async function installApp(device, appPath) {
  const forceInstall = process.env.CARELOOP_DEMO_FORCE_INSTALL === "1";
  if (!forceInstall && hasInstalledApp(device)) return;

  run("xcrun", ["simctl", "uninstall", device.udid, bundleId], {
    env: developerEnv(),
    stdio: "pipe",
    allowFailure: true,
    timeoutMs: 15000,
  });

  try {
    run("xcrun", ["simctl", "install", device.udid, appPath], {
      env: developerEnv(),
      stdio: "pipe",
      timeoutMs: 45000,
    });
  } catch {
    run("xcrun", ["simctl", "shutdown", device.udid], {
      env: developerEnv(),
      stdio: "pipe",
      allowFailure: true,
      timeoutMs: 15000,
    });
    await bootDevice(device);
    run("xcrun", ["simctl", "install", device.udid, appPath], {
      env: developerEnv(),
      stdio: "pipe",
      timeoutMs: 45000,
    });
  }
}

function launchProfile(device, profile) {
  const env = developerEnv({
    SIMCTL_CHILD_CARELOOP_DEMO_ACCESS_TOKEN: profile.token,
  });

  if (profile.circleId) {
    env.SIMCTL_CHILD_CARELOOP_DEMO_CIRCLE_ID = profile.circleId;
    env.SIMCTL_CHILD_CARELOOP_DEMO_AUTO_ACTIVATE = "1";
  }

  const output = run(
    "xcrun",
    [
      "simctl",
      "launch",
      "--terminate-running-process",
      device.udid,
      bundleId,
      "-careloop-ui-reset-session",
    ],
    {
      env,
      stdio: "pipe",
    },
  );
  return output.trim();
}

function openSimulatorWindowsForBootedDevices() {
  run("open", ["-a", "Simulator", "--args", "-AttachBootedOnStart", "YES"], {
    env: developerEnv(),
    stdio: "pipe",
  });
}

function simulatorWindowCount() {
  const script = `
import CoreGraphics
import Foundation

let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let rows = info.filter { ($0[kCGWindowOwnerName as String] as? String) == "Simulator" }
print(rows.count)
`;

  const result = spawnSync("swift", ["-"], {
    env: developerEnv(),
    input: script,
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
  });
  if (result.status !== 0) return null;
  return Number.parseInt((result.stdout || "").trim(), 10);
}

async function validateProfile(profile) {
  const headers = { Authorization: `Bearer ${profile.token}` };
  const currentUser = await fetchJson(`${apiBaseUrl}/users/me`, { headers });
  if (!currentUser?.id) {
    throw new Error(`Profile ${profile.title} could not fetch /users/me`);
  }
  if (profile.circleId) {
    const circle = await fetchJson(`${apiBaseUrl}/circles/${profile.circleId}`, { headers });
    if (!circle?.id) {
      throw new Error(`Profile ${profile.title} could not fetch circle ${profile.circleId}`);
    }
  }
}

async function main() {
  const api = await ensureApiRunning();
  const manifest = await refreshManifestTokens(seedManifest());
  const profiles = manifest.launchProfiles;

  for (const profile of profiles) {
    await validateProfile(profile);
  }

  const devices = selectSimulatorDevices(profiles.length);
  resetSimulatorWorkspace();
  await delay(2000);

  for (const device of devices) {
    await bootDevice(device);
  }

  const appPath = resolveInstallSourceAppPath(devices, buildIOSApp());
  if (!appPath) {
    throw new Error(
      "No valid CareLoop.app bundle found. Run with CARELOOP_DEMO_FORCE_BUILD=1 once to rebuild the simulator app.",
    );
  }

  for (const device of devices) {
    await installApp(device, appPath);
  }

  openSimulatorWindowsForBootedDevices();
  await delay(3000);

  const launchedSessions = [];
  for (const [index, profile] of profiles.entries()) {
    const pidOutput = launchProfile(devices[index], profile);
    launchedSessions.push({
      ...profile,
      device: devices[index].name,
      udid: devices[index].udid,
      launchOutput: pidOutput,
    });
    await delay(2000);
  }

  await delay(6000);

  const summary = {
    manifestPath,
    appPath,
    apiStartedByScript: api.started,
    apiLogPath: api.logPath,
    defaultPassword: manifest.defaultPassword,
    simulatorWindowCount: simulatorWindowCount(),
    sessions: launchedSessions.map((session) => ({
      title: session.title,
      email: session.email,
      device: session.device,
      udid: session.udid,
      circleId: session.circleId,
      launchOutput: session.launchOutput,
    })),
  };

  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
}

main().catch((error) => {
  console.error("CareLoop room demo setup failed:", error.message);
  process.exitCode = 1;
});

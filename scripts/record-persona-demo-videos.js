import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { resolveCareLoopIosRoot } from "./careloop-paths.js";

const __filename = fileURLToPath(import.meta.url);
const projectRoot = path.resolve(path.dirname(__filename), "..");
const iosRoot = resolveCareLoopIosRoot();
const developerDir = process.env.DEVELOPER_DIR || "/Applications/Xcode.app/Contents/Developer";
const apiBaseUrl = process.env.CARELOOP_API_BASE_URL || "http://127.0.0.1:3000";
const outputDir = process.env.CARELOOP_RECORDING_OUTPUT_DIR
  || path.join(os.tmpdir(), "careloop-persona-recordings");
const apiLogPath = path.join(os.tmpdir(), "careloop-recording-api.log");
const manifestPath = path.join(outputDir, "careloop-recording-manifest.json");

const recordingPlans = [
  {
    key: "organizer-family-care",
    profileKey: "aging-organizer",
    testName: "test_recordingOrganizerRealWorldJourney",
  },
  {
    key: "caregiver-new-parent",
    profileKey: "new-parent-caregiver",
    testName: "test_recordingCaregiverRealWorldJourney",
  },
  {
    key: "care-receiver-recovery",
    profileKey: "recovery-recipient",
    testName: "test_recordingCareReceiverRealWorldJourney",
  },
  {
    key: "caregiver-memory-care",
    profileKey: "memory-caregiver",
    testName: "test_recordingMemoryCaregiverRealWorldJourney",
  },
];

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? projectRoot,
    env: options.env ?? process.env,
    encoding: "utf8",
    stdio: options.stdio ?? "pipe",
    timeout: options.timeoutMs ?? 0,
  });

  if (result.status !== 0 && !options.allowFailure) {
    throw new Error([
      `Command failed: ${command} ${args.join(" ")}`,
      result.stdout?.trim() ? `stdout:\n${result.stdout.trim()}` : null,
      result.stderr?.trim() ? `stderr:\n${result.stderr.trim()}` : null,
    ].filter(Boolean).join("\n\n"));
  }

  return result.stdout ?? "";
}

function developerEnv(extra = {}) {
  return {
    ...process.env,
    DEVELOPER_DIR: developerDir,
    ...extra,
  };
}

async function waitForHealth(timeoutMs = 30000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    try {
      const response = await fetch(`${apiBaseUrl}/health`);
      if (response.ok) return true;
    } catch {
      // Keep polling.
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  return false;
}

async function ensureApiRunning() {
  if (await waitForHealth(2000)) return;

  const logStream = fs.openSync(apiLogPath, "a");
  const child = spawn("npm", ["run", "start"], {
    cwd: projectRoot,
    env: process.env,
    detached: true,
    stdio: ["ignore", logStream, logStream],
  });
  fs.closeSync(logStream);
  child.unref();

  if (!(await waitForHealth(45000))) {
    throw new Error(`CareLoop API did not become healthy. Check ${apiLogPath}`);
  }
}

function seedManifest() {
  fs.mkdirSync(outputDir, { recursive: true });
  const raw = run("node", ["scripts/seed-demo-showcase.js"], { cwd: projectRoot });
  fs.writeFileSync(manifestPath, raw, "utf8");
  return JSON.parse(raw);
}

function selectedDevice() {
  const raw = run("xcrun", ["simctl", "list", "devices", "available", "-j"], {
    env: developerEnv(),
  });
  const payload = JSON.parse(raw);
  const devices = Object.values(payload.devices ?? {}).flat();
  const preferredName = process.env.CARELOOP_RECORDING_DEVICE || "iPhone 17 Pro";
  const match = devices.find((device) => device.name === preferredName && device.isAvailable !== false)
    ?? devices.find((device) => /^iPhone/.test(device.name) && device.isAvailable !== false);
  if (!match) throw new Error("No available iPhone simulator found for recording.");
  return match;
}

function bootDevice(udid) {
  run("xcrun", ["simctl", "boot", udid], { env: developerEnv(), allowFailure: true });
  run("xcrun", ["simctl", "bootstatus", udid, "-b"], { env: developerEnv(), timeoutMs: 120000 });
  run("open", ["-a", "Simulator"], { env: process.env, allowFailure: true });
}

function startRecording(udid, filePath) {
  fs.rmSync(filePath, { force: true });
  return spawn("xcrun", ["simctl", "io", udid, "recordVideo", "--codec=h264", "--force", filePath], {
    env: developerEnv(),
    stdio: ["ignore", "pipe", "pipe"],
  });
}

async function stopRecording(child) {
  if (child.exitCode !== null) return;
  child.kill("SIGINT");
  await new Promise((resolve) => {
    const timeout = setTimeout(resolve, 5000);
    child.once("exit", () => {
      clearTimeout(timeout);
      resolve();
    });
  });
}

async function recordPlan(plan, profile, udid) {
  const filePath = path.join(outputDir, `${plan.key}.mp4`);
  const recorder = startRecording(udid, filePath);

  try {
    run(
      "xcodebuild",
      [
        "test",
        "-project",
        "CareLoop.xcodeproj",
        "-scheme",
        "CareLoop",
        "-destination",
        `id=${udid}`,
        "-only-testing:CareLoopUITests/CareLoopUITests/" + plan.testName,
      ],
      {
        cwd: iosRoot,
        env: developerEnv({
          CARELOOP_RECORDING_ACCESS_TOKEN: profile.token,
          CARELOOP_RECORDING_CIRCLE_ID: profile.circleId,
        }),
        timeoutMs: 300000,
      },
    );
  } finally {
    await stopRecording(recorder);
  }

  return filePath;
}

async function main() {
  await ensureApiRunning();
  const manifest = seedManifest();
  const device = selectedDevice();
  bootDevice(device.udid);

  const profileByKey = new Map(manifest.launchProfiles.map((profile) => [profile.key, profile]));
  const recordings = [];

  for (const plan of recordingPlans) {
    const profile = profileByKey.get(plan.profileKey);
    if (!profile) throw new Error(`Missing launch profile ${plan.profileKey}`);
    const filePath = await recordPlan(plan, profile, device.udid);
    recordings.push({
      key: plan.key,
      profile: profile.title,
      person: profile.name,
      email: profile.email,
      filePath,
    });
  }

  console.log(JSON.stringify({
    outputDir,
    manifestPath,
    recordings,
  }, null, 2));
}

main().catch((error) => {
  console.error("CareLoop persona recording failed:", error);
  process.exitCode = 1;
});

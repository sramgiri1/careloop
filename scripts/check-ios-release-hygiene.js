import fs from "node:fs";
import path from "node:path";
import { resolveCareLoopIosRoot } from "./careloop-paths.js";

const iosRoot = resolveCareLoopIosRoot();

const files = {
  pbxproj: path.join(iosRoot, "CareLoop.xcodeproj", "project.pbxproj"),
  app: path.join(iosRoot, "CareLoop", "App", "CareLoopApp.swift"),
  appState: path.join(iosRoot, "CareLoop", "App", "AppState.swift"),
  uiTestScenario: path.join(iosRoot, "CareLoop", "App", "UITestScenario.swift"),
  demoLaunch: path.join(iosRoot, "CareLoop", "App", "DemoLaunchSession.swift"),
  paywall: path.join(iosRoot, "CareLoop", "Views", "PaywallView.swift"),
  infoPlist: path.join(iosRoot, "CareLoop", "Resources", "Info.plist"),
  storeKit: path.join(iosRoot, "CareLoop", "Configuration", "CareLoop.storekit"),
};

const source = Object.fromEntries(
  Object.entries(files).map(([key, file]) => [key, fs.readFileSync(file, "utf8")]),
);

const failures = [];
const warnings = [];

function check(condition, message) {
  if (!condition) failures.push(message);
}

function warn(condition, message) {
  if (!condition) warnings.push(message);
}

check(source.pbxproj.includes("UITestScenario.swift in Sources"), "Xcode target membership audit must see UITestScenario.swift in the app target");
check(source.pbxproj.includes("DemoLaunchSession.swift in Sources"), "Xcode target membership audit must see DemoLaunchSession.swift in the app target");
check(source.uiTestScenario.startsWith("import Foundation\n\n#if DEBUG"), "UITestScenario must be compiled only in DEBUG");
check(source.uiTestScenario.includes("extension AppState") && source.uiTestScenario.indexOf("extension AppState") > source.uiTestScenario.indexOf("#if DEBUG"), "UITestScenario AppState fixture initializer must be inside the top-level DEBUG gate");
check(source.uiTestScenario.includes("private struct UITestScenarioFixture") && source.uiTestScenario.indexOf("private struct UITestScenarioFixture") > source.uiTestScenario.indexOf("#if DEBUG"), "UITestScenario fixture data must be inside the top-level DEBUG gate");
check(source.demoLaunch.startsWith("import Foundation\n\n#if DEBUG"), "DemoLaunchSession must be compiled only in DEBUG");
check(source.appState.includes("#if DEBUG\n    private let launchSession"), "AppState demo launch session storage must be DEBUG-gated");
check(source.appState.includes("#if DEBUG\n        if let launchSession"), "AppState demo token activation must be DEBUG-gated");
check(source.app.includes("#if DEBUG\n        if ProcessInfo.processInfo.arguments.contains(LaunchArguments.resetSession)") && source.app.includes("if let scenario = UITestScenario.current"), "CareLoopApp must only activate UI-test scenarios in DEBUG");
check(source.app.includes("if let launchSession = DemoLaunchSession.current"), "CareLoopApp must keep demo launch session path explicit");
check(source.app.includes("#endif\n        _appState = StateObject(wrappedValue: AppState())"), "CareLoopApp must fall back to production AppState outside DEBUG");
check(source.paywall.includes("#if DEBUG\n        ProcessInfo.processInfo.arguments.contains(\"-careloop-ui-simulate-premium-sync\")"), "Paywall simulated premium sync must be DEBUG-gated");
check(!source.infoPlist.includes("<key>API_KEY</key>"), "Info.plist must not ship a shared API_KEY; app traffic must use per-user bearer tokens");
check(source.infoPlist.includes("<string>$(CARELOOP_API_BASE_URL)</string>"), "Info.plist API_BASE_URL must come from CARELOOP_API_BASE_URL build settings");
check(!source.infoPlist.includes("http://localhost:3000"), "Info.plist must not hardcode localhost API_BASE_URL");
check(source.pbxproj.includes("CARELOOP_API_BASE_URL"), "Xcode project must define CARELOOP_API_BASE_URL build settings for the app target");
check(!source.pbxproj.includes("http://localhost:3000"), "Xcode project must not use localhost API_BASE_URL; use 127.0.0.1 for Debug local networking and a hosted HTTPS origin for Release");
check(!/organizer@careloop\.test|caregiver@careloop\.test|mom@careloop\.test/.test(source.app), "CareLoopApp must not contain fixture accounts");
check(!/CARELOOP_DEMO_ACCESS_TOKEN/.test(source.app), "CareLoopApp must not directly read demo tokens");
check(!/careloop-ui-scenario/.test(source.app), "CareLoopApp must not directly parse UI-test scenario arguments");

const releaseAppPath = process.env.CARELOOP_RELEASE_APP_PATH || findLatestReleaseAppPath();
const requiresReleaseApp = process.env.CARELOOP_REQUIRE_RELEASE_APP === "1" || process.argv.includes("--require-release-app");
if (releaseAppPath) {
  scanReleaseApp(releaseAppPath);
} else if (requiresReleaseApp) {
  failures.push("Release app artifact not found; build Release first or set CARELOOP_RELEASE_APP_PATH");
} else {
  warnings.push("Release app artifact not found; H3 archive scan did not run");
}

function findLatestReleaseAppPath() {
  const derivedDataRoot = path.join(process.env.HOME || "", "Library", "Developer", "Xcode", "DerivedData");
  if (!fs.existsSync(derivedDataRoot)) return null;
  const candidates = [];
  for (const entry of fs.readdirSync(derivedDataRoot, { withFileTypes: true })) {
    if (!entry.isDirectory() || !entry.name.startsWith("CareLoop-")) continue;
    const appPath = path.join(derivedDataRoot, entry.name, "Build", "Products", "Release-iphonesimulator", "CareLoop.app");
    if (!fs.existsSync(appPath)) continue;
    candidates.push({ appPath, mtimeMs: fs.statSync(appPath).mtimeMs });
  }
  candidates.sort((left, right) => right.mtimeMs - left.mtimeMs);
  return candidates[0]?.appPath ?? null;
}

function scanReleaseApp(appPath) {
  const forbiddenNames = [/\.storekit$/i, /seed-demo/i, /demo-showcase/i, /fixture/i];
  const forbiddenStrings = [
    "API_KEY",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "@careloop.test",
    "@careloop.local",
    "CARELOOP_DEMO_ACCESS_TOKEN",
    "CARELOOP_DEMO_CIRCLE_ID",
    "CARELOOP_DEMO_AUTO_ACTIVATE",
    "-careloop-ui-scenario",
    "-careloop-ui-pending-task",
    "-careloop-ui-pending-circle",
    "-careloop-ui-reset-session",
    "-careloop-ui-simulate-premium-sync",
    "careloop-local-storekit",
    "seed-demo-showcase",
    "UITestScenarioFixture",
    "DemoLaunchSession",
  ];

  for (const file of walkFiles(appPath)) {
    const relative = path.relative(appPath, file);
    if (forbiddenNames.some((pattern) => pattern.test(relative))) {
      failures.push(`Release app artifact contains forbidden demo/test file: ${relative}`);
      continue;
    }

    const size = fs.statSync(file).size;
    if (size > 75 * 1024 * 1024) continue;
    const text = fs.readFileSync(file).toString("latin1");
    for (const forbidden of forbiddenStrings) {
      if (text.includes(forbidden)) {
        failures.push(`Release app artifact contains forbidden demo/test string "${forbidden}" in ${relative}`);
      }
    }
  }
}

function walkFiles(dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walkFiles(fullPath));
    } else if (entry.isFile()) {
      files.push(fullPath);
    }
  }
  return files;
}

if (failures.length || warnings.length) {
  if (failures.length) {
    console.error("CareLoop iOS release hygiene check failed:");
    for (const failure of failures) console.error(`- ${failure}`);
  }
  if (warnings.length) {
    console.error("CareLoop iOS release hygiene warnings:");
    for (const warning of warnings) console.error(`- ${warning}`);
  }
}

if (failures.length) process.exit(1);
console.log("CareLoop iOS release hygiene check passed.");

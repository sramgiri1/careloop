import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolveCareLoopIosRoot } from "./careloop-paths.js";

const __filename = fileURLToPath(import.meta.url);
const projectRoot = path.resolve(path.dirname(__filename), "..");
const iosRoot = resolveCareLoopIosRoot();

const packageJson = JSON.parse(fs.readFileSync(path.join(projectRoot, "package.json"), "utf8"));
const seedPath = path.join(projectRoot, "scripts", "seed-demo-showcase.js");
const launcherPath = path.join(projectRoot, "scripts", "careloop-demo-room-setup.js");
const storeKitPath = path.join(iosRoot, "CareLoop", "Configuration", "CareLoop.storekit");
const subscriptionManagerPath = path.join(iosRoot, "CareLoop", "App", "SubscriptionManager.swift");

const seed = fs.readFileSync(seedPath, "utf8");
const launcher = fs.readFileSync(launcherPath, "utf8");
const storeKit = JSON.parse(fs.readFileSync(storeKitPath, "utf8"));
const subscriptionManager = fs.readFileSync(subscriptionManagerPath, "utf8");

const failures = [];

function check(condition, message) {
  if (!condition) failures.push(message);
}

function countMatches(pattern) {
  return [...seed.matchAll(pattern)].length;
}

function scenarioBlock(key) {
  const start = seed.indexOf(`key: "${key}"`);
  if (start === -1) return "";
  const next = seed.indexOf("\n  },\n  {", start);
  return seed.slice(start, next === -1 ? seed.length : next);
}

const scenarios = [
  ["aging-parent", "Aging parent support"],
  ["post-surgery", "Post-surgery recovery"],
  ["new-parent", "Postpartum and newborn support"],
  ["memory-care", "Memory care and home safety"],
];

check(packageJson.scripts?.["careloop:demo"] === "node scripts/careloop-demo-room-setup.js", "package.json must expose npm run careloop:demo from the CareLoop repo root");
check(packageJson.scripts?.["qa:seed:showcase"] === "node scripts/seed-demo-showcase.js", "package.json must expose qa:seed:showcase");
check(packageJson.scripts?.["check:demo-showcase"] === "node scripts/check-demo-showcase-readiness.js", "package.json must expose check:demo-showcase");
check(packageJson.scripts?.["check:careloop-demo-readiness"] === "node scripts/check-demo-showcase-readiness.js", "package.json must expose check:careloop-demo-readiness");
check(fs.existsSync(launcherPath), "one-command launcher script must exist");
check(launcher.includes("CARELOOP_API_BASE_URL") && launcher.includes("http://127.0.0.1:3000"), "launcher must target the local CareLoop API by default and allow override");
check(launcher.includes("ensureApiRunning()"), "launcher must start or reuse the local API");
check(launcher.includes("seedManifest()"), "launcher must reseed showcase data before launch");
check(launcher.includes("selectSimulatorDevices(profiles.length)"), "launcher must open one simulator per launch profile");
check(launcher.includes("CARELOOP_DEMO_FORCE_BUILD"), "launcher must support force rebuild for fresh demo installs");
check(launcher.includes("CARELOOP_DEMO_FORCE_INSTALL"), "launcher must support force install for clean simulator demos");
check(launcher.includes("refreshManifestTokens"), "launcher must refresh demo tokens after seeding");
check(launcher.includes("SIMCTL_CHILD_CARELOOP_DEMO_ACCESS_TOKEN"), "launcher must pass demo tokens through simulator environment");
check(launcher.includes("SIMCTL_CHILD_CARELOOP_DEMO_CIRCLE_ID"), "launcher must pass active circle context through simulator environment");
check(launcher.includes("openSimulatorWindowsForBootedDevices()"), "launcher must open simulator windows for room demos");
check(launcher.includes("manifestPath") && launcher.includes("sessions:"), "launcher summary must include manifest path and launched sessions");

for (const [key, useCase] of scenarios) {
  check(seed.includes(`key: "${key}"`), `demo seed missing scenario ${key}`);
  check(seed.includes(`useCase: "${useCase}"`), `demo seed missing use case label ${useCase}`);
  const block = scenarioBlock(key);
  check(/caregivers:\s*\[/.test(block), `demo scenario ${key} must include caregivers`);
  check(/tasks:\s*\[/.test(block), `demo scenario ${key} must include tasks`);
  check(/status:\s*"PENDING"/.test(block), `demo scenario ${key} must include a pending task`);
  check(/status:\s*"DONE"/.test(block), `demo scenario ${key} must include task history`);
  check(/comments:\s*\[/.test(block), `demo scenario ${key} must include task comments/history`);
}

check(/key:\s*"aging-parent"[\s\S]*activationStatus:\s*"PROXY_ACTIVE"/.test(seed), "aging-parent scenario must include proxy-activated receiver");
check(/key:\s*"post-surgery"[\s\S]*premiumRequests:\s*\[/.test(seed), "post-surgery scenario must include premium request state");
check(/key:\s*"new-parent"[\s\S]*com\.careloop\.ios\.premium\.yearly/.test(seed), "new-parent scenario must include active premium state");
check(/key:\s*"memory-care"[\s\S]*expiresAtHoursFromNow:\s*-/.test(seed), "memory-care scenario must include expired premium state");

check(countMatches(/accessTo:\s*\[/g) >= 8, "demo seed must grant caregiver receiver access across scenarios");
check(countMatches(/pendingInvites:\s*\[/g) >= 4, "demo seed must include pending invites across scenarios");
check(countMatches(/status:\s*"PENDING"/g) >= 8, "demo seed must include pending tasks");
check(countMatches(/status:\s*"IN_PROGRESS"/g) >= 3, "demo seed must include in-progress tasks");
check(countMatches(/status:\s*"DONE"/g) >= 4, "demo seed must include completed task history");
check(countMatches(/status:\s*"SKIPPED"/g) >= 2, "demo seed must include skipped task history");
check(countMatches(/status:\s*"ESCALATED"/g) >= 2, "demo seed must include escalated reminders");
check(countMatches(/status:\s*"SNOOZED"/g) >= 2, "demo seed must include snoozed reminders");
check(countMatches(/comments:\s*\[/g) >= 8, "demo seed must include task history comments");
check(seed.includes("premiumRequests:"), "demo seed must include premium upgrade request moments");
check(seed.includes("expiresAtHoursFromNow: -"), "demo seed must include expired premium state");
check(seed.includes('source: "MANUAL"'), "demo seed must include non-App-Store/manual premium state for demo flexibility");
check(seed.includes("com.careloop.ios.premium.monthly"), "demo seed must include monthly premium product id");
check(seed.includes("com.careloop.ios.premium.yearly"), "demo seed must include yearly premium product id");
check(!/demo\.[^"@\s]+@(gmail|yahoo|outlook|hotmail|icloud)\.com/i.test(seed), "demo seed must not use real consumer email domains");
check(/anita\.ramgiri@example\.com/.test(seed), "demo seed must use realistic reserved-domain organizer identities");
check(!/email:\s*"demo\./.test(seed), "visible seeded users and pending invites must not use demo-prefixed emails");
check(!/email:\s*"[^"]+@careloop\.local"/.test(seed), "visible seeded users and pending invites must not use internal CareLoop-local emails");

const launchProfileKeys = [
  "aging-organizer",
  "recovery-recipient",
  "new-parent-caregiver",
  "memory-caregiver",
];
for (const key of launchProfileKeys) {
  check(seed.includes(`key: "${key}"`), `manifest missing launch profile ${key}`);
}
check(seed.includes('userKey: "organizer"'), "launch profiles must include organizer persona");
check(seed.includes('userKey: "recoveryRecipient"'), "launch profiles must include care receiver persona");
check(seed.includes('userKey: "newParentCaregiver"') && seed.includes('userKey: "memoryCaregiver"'), "launch profiles must include caregiver personas");

const subscriptions = (storeKit.subscriptionGroups ?? []).flatMap((group) => group.subscriptions ?? []);
const productIds = subscriptions.map((subscription) => subscription.productID);
const monthlyID = subscriptionManager.match(/static let monthlyID\s*=\s*"([^"]+)"/)?.[1];
const yearlyID = subscriptionManager.match(/static let yearlyID\s*=\s*"([^"]+)"/)?.[1];

check(productIds.includes(monthlyID), "StoreKit config missing monthly product id from SubscriptionManager");
check(productIds.includes(yearlyID), "StoreKit config missing yearly product id from SubscriptionManager");
check(subscriptions.find((item) => item.productID === monthlyID)?.recurringSubscriptionPeriod === "P1M", "monthly StoreKit product must recur monthly");
check(subscriptions.find((item) => item.productID === yearlyID)?.recurringSubscriptionPeriod === "P1Y", "yearly StoreKit product must recur yearly");

if (failures.length) {
  console.error("CareLoop demo showcase readiness failed:");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("CareLoop demo showcase readiness passed.");

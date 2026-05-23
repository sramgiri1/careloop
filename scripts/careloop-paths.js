import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
export const careloopApiRoot = path.resolve(path.dirname(__filename), "..");

function existingDir(candidate) {
  return candidate && fs.existsSync(candidate) && fs.statSync(candidate).isDirectory()
    ? candidate
    : null;
}

export function resolveCareLoopIosRoot() {
  const candidates = [
    process.env.CARELOOP_IOS_ROOT,
    path.join(careloopApiRoot, "ios"),
    path.join(careloopApiRoot, "..", "careloop-ios"),
    path.join(careloopApiRoot, "..", "ios"),
  ];

  for (const candidate of candidates) {
    const resolved = existingDir(candidate);
    if (resolved) return resolved;
  }

  throw new Error(
    [
      "CareLoop iOS project not found.",
      "Set CARELOOP_IOS_ROOT to the folder containing CareLoop.xcodeproj,",
      "or place the iOS app at ./ios, ../careloop-ios, or ../ios.",
    ].join(" "),
  );
}

export function resolveCareLoopXcodeProject() {
  return path.join(resolveCareLoopIosRoot(), "CareLoop.xcodeproj");
}

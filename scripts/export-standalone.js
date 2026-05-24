import fs from "node:fs";
import path from "node:path";
import { careloopApiRoot, resolveCareLoopIosRoot } from "./careloop-paths.js";

const DEFAULT_DESTINATION = path.join(careloopApiRoot, ".tmp", "standalone-export");

const backendEntries = [
  ".env.example",
  ".gitignore",
  "README.md",
  "docs",
  "package-lock.json",
  "package.json",
  "prisma",
  "railway.json",
  "scripts",
  "src",
  "test",
];

const excludedNames = new Set([
  ".DS_Store",
  ".env",
  ".env.local",
  ".env.prod",
  ".tmp",
  "DerivedData",
  "build",
  "node_modules",
  "videos",
  "xcuserdata",
]);

function parseArgs(argv) {
  const args = {
    destination: process.env.CARELOOP_EXPORT_DIR || DEFAULT_DESTINATION,
    clean: false,
    dryRun: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--to") {
      args.destination = argv[index + 1];
      index += 1;
    } else if (arg.startsWith("--to=")) {
      args.destination = arg.slice("--to=".length);
    } else if (arg === "--clean") {
      args.clean = true;
    } else if (arg === "--dry-run") {
      args.dryRun = true;
    } else if (arg === "--help" || arg === "-h") {
      printUsage();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return {
    ...args,
    destination: path.resolve(args.destination),
  };
}

function printUsage() {
  console.log(`Usage:
  npm run standalone:export -- --to /path/to/careloop [--clean]
  npm run check:standalone-export

Options:
  --to <path>   Destination folder. Defaults to .tmp/standalone-export.
  --clean       Remove destination before copying. Guarded against unsafe paths.
  --dry-run     Validate export inputs and print the manifest without copying.`);
}

function assertSafeDestination(destination) {
  const home = process.env.HOME ? path.resolve(process.env.HOME) : null;
  const iosRoot = path.resolve(resolveCareLoopIosRoot());
  const unsafe = new Set([
    path.parse(destination).root,
    home,
    careloopApiRoot,
    iosRoot,
    path.resolve(careloopApiRoot, ".."),
  ].filter(Boolean));

  if (unsafe.has(destination)) {
    throw new Error(`Refusing unsafe export destination: ${destination}`);
  }

  if (destination.startsWith(`${careloopApiRoot}${path.sep}`) && !destination.startsWith(`${path.join(careloopApiRoot, ".tmp")}${path.sep}`)) {
    throw new Error("Export destination inside CareLoop must be under .tmp.");
  }
}

function shouldExclude(entryName) {
  if (excludedNames.has(entryName)) return true;
  if (entryName.startsWith("NEXUS_")) return true;
  if (entryName.endsWith(".mov") || entryName.endsWith(".mp4")) return true;
  if (entryName.endsWith(".xcuserstate")) return true;
  if (entryName.endsWith(".xcresult")) return true;
  return false;
}

function copyEntry(source, destination, counters) {
  const entryName = path.basename(source);
  if (shouldExclude(entryName)) return;

  const stat = fs.statSync(source);
  if (stat.isDirectory()) {
    fs.mkdirSync(destination, { recursive: true });
    counters.directories += 1;
    for (const child of fs.readdirSync(source)) {
      copyEntry(path.join(source, child), path.join(destination, child), counters);
    }
    return;
  }

  if (!stat.isFile()) return;
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(source, destination);
  counters.files += 1;
}

function collectFiles(root) {
  const files = [];
  if (!fs.existsSync(root)) return files;
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const fullPath = path.join(root, entry.name);
    if (shouldExclude(entry.name)) continue;
    if (entry.isDirectory()) {
      files.push(...collectFiles(fullPath));
    } else if (entry.isFile()) {
      files.push(fullPath);
    }
  }
  return files;
}

function validateExport(destination) {
  const required = [
    "package.json",
    "railway.json",
    "src/index.js",
    "prisma/schema.prisma",
    "scripts/careloop-demo-room-setup.js",
    "scripts/careloop-paths.js",
    "test/sprint2.test.js",
    "ios/CareLoop.xcodeproj/project.pbxproj",
    "ios/CareLoopUITests/CareLoopUITests.swift",
  ];
  const missing = required.filter((relativePath) => !fs.existsSync(path.join(destination, relativePath)));
  if (missing.length > 0) {
    throw new Error(`Standalone export missing required files: ${missing.join(", ")}`);
  }

  const forbidden = collectFiles(destination).filter((file) => {
    const relativePath = path.relative(destination, file);
    return relativePath === ".env"
      || relativePath === ".env.prod"
      || relativePath.includes(`${path.sep}node_modules${path.sep}`)
      || relativePath.startsWith(`..${path.sep}`)
      || relativePath.startsWith(`reports${path.sep}`)
      || relativePath.startsWith(`dashboard${path.sep}`)
      || relativePath.startsWith(`os-roadmap${path.sep}`)
      || relativePath.startsWith(`contracts${path.sep}`);
  });

  if (forbidden.length > 0) {
    throw new Error(`Standalone export contains forbidden files: ${forbidden.slice(0, 8).join(", ")}`);
  }
}

function buildManifest({ destination, dryRun, iosRoot, counters }) {
  return {
    generatedAt: new Date().toISOString(),
    dryRun,
    destination,
    source: {
      backend: careloopApiRoot,
      ios: iosRoot,
    },
    layout: {
      backend: ".",
      ios: "ios",
    },
    includedBackendEntries: backendEntries,
    excludedNames: [...excludedNames].sort(),
    counts: counters,
    nextCommands: [
      "npm install",
      "npm test",
      "npm run check:demo-showcase",
      "npm run check:production-env -- --env-file .env.prod",
      "npm run check:ios-release-hygiene",
      "npm run test:ios:api",
    ],
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  assertSafeDestination(args.destination);

  const iosRoot = path.resolve(resolveCareLoopIosRoot());
  const counters = { files: 0, directories: 0 };

  if (!fs.existsSync(path.join(iosRoot, "CareLoop.xcodeproj"))) {
    throw new Error(`CareLoop iOS project is invalid: ${iosRoot}`);
  }

  if (!args.dryRun) {
    if (fs.existsSync(args.destination)) {
      if (!args.clean) {
        throw new Error(`Export destination already exists. Re-run with --clean to replace: ${args.destination}`);
      }
      fs.rmSync(args.destination, { recursive: true, force: true });
    }
    fs.mkdirSync(args.destination, { recursive: true });

    for (const entry of backendEntries) {
      copyEntry(path.join(careloopApiRoot, entry), path.join(args.destination, entry), counters);
    }
    copyEntry(iosRoot, path.join(args.destination, "ios"), counters);
    validateExport(args.destination);
  }

  const manifest = buildManifest({
    destination: args.destination,
    dryRun: args.dryRun,
    iosRoot,
    counters: args.dryRun ? { files: 0, directories: 0 } : counters,
  });

  if (!args.dryRun) {
    fs.writeFileSync(path.join(args.destination, "standalone-export-manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
  }

  console.log(JSON.stringify(manifest, null, 2));
}

main();

#!/usr/bin/env node
import { execFileSync, spawn } from "child_process";

const port = parseInt(process.env.PORT || "3000", 10);

function findListeningPids(targetPort) {
  try {
    const output = execFileSync("lsof", ["-nP", `-iTCP:${targetPort}`, "-sTCP:LISTEN", "-t"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    return output ? output.split("\n").map((value) => parseInt(value, 10)).filter(Boolean) : [];
  } catch {
    return [];
  }
}

function readCommand(pid) {
  try {
    return execFileSync("ps", ["-p", String(pid), "-o", "command="], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

function stopStaleCareLoopProcess(targetPort) {
  const pids = findListeningPids(targetPort);
  for (const pid of pids) {
    if (pid === process.pid) continue;
    const command = readCommand(pid);
    if (!command.includes("src/index.js")) {
      console.error(`[careloop:dev] Port ${targetPort} is already in use by: ${command || `pid ${pid}`}`);
      console.error("[careloop:dev] Stop that process or launch CareLoop with a different PORT.");
      process.exit(1);
    }
    console.log(`[careloop:dev] Stopping stale watcher on port ${targetPort} (pid=${pid})`);
    try {
      process.kill(pid, "SIGTERM");
    } catch {
      // Ignore races where the process exits between discovery and kill.
    }
  }
}

stopStaleCareLoopProcess(port);

const child = spawn(process.execPath, ["--watch", "src/index.js"], {
  cwd: process.cwd(),
  env: process.env,
  stdio: "inherit",
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 0);
});


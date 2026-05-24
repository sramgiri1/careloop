#!/usr/bin/env node
import dotenv from "dotenv";
import { validateProductionEnvironment } from "../src/lib/env.js";

const args = process.argv.slice(2);
const envFileIndex = args.indexOf("--env-file");

if (envFileIndex >= 0) {
  const envFile = args[envFileIndex + 1];
  if (!envFile) {
    console.error("Usage: npm run check:production-env -- --env-file .env.prod");
    process.exit(1);
  }
  const result = dotenv.config({ path: envFile, override: false });
  if (result.error) {
    console.error(`Unable to load env file: ${envFile}`);
    process.exit(1);
  }
}

const report = validateProductionEnvironment(process.env);

if (report.errors.length > 0) {
  console.error("CareLoop production environment check failed:");
  for (const error of report.errors) console.error(`- ${error}`);
}

if (report.warnings.length > 0) {
  console.error("CareLoop production environment warnings:");
  for (const warning of report.warnings) console.error(`- ${warning}`);
}

if (report.errors.length > 0) process.exit(1);

console.log("CareLoop production environment check passed.");

import { networkInterfaces } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Bonjour } from "bonjour-service";
import { buildApp } from "./app.js";

const PORT = 8787;
const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const scansDir = join(repoRoot, "scans");

const app = buildApp({ scansDir });
await app.listen({ host: "0.0.0.0", port: PORT });

const urls = Object.values(networkInterfaces())
  .flat()
  .filter((n) => n && n.family === "IPv4" && !n.internal)
  .map((n) => `http://${n!.address}:${PORT}`);

console.log(`iScan server listening. Scans are saved to ${scansDir}`);
console.log("Enter one of these in the iScan app's Settings if it isn't discovered automatically:");
for (const u of urls) console.log(`  ${u}`);
console.log("\nIf the phone can't connect, run these once in an admin PowerShell:");
console.log('  New-NetFirewallRule -DisplayName "iScan TCP 8787" -Direction Inbound -Protocol TCP -LocalPort 8787 -Action Allow -Profile Private');
console.log('  New-NetFirewallRule -DisplayName "iScan mDNS" -Direction Inbound -Protocol UDP -LocalPort 5353 -Action Allow -Profile Private');

try {
  const bonjour = new Bonjour({}, (err: unknown) => console.warn(`Bonjour error (use the manual URL): ${String(err)}`));
  bonjour.publish({ name: "iScan", type: "iscan", port: PORT });
  const shutdown = () => bonjour.unpublishAll(() => bonjour.destroy(() => process.exit(0)));
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
} catch (err) {
  console.warn(`Bonjour unavailable (use the manual URL): ${String(err)}`);
}

import { readdir, stat } from "node:fs/promises";
import { join, resolve, sep } from "node:path";

const SCAN_ID = /^\d{8}-\d{6}$/;
const SEGMENT = /^[A-Za-z0-9_-][A-Za-z0-9._-]*$/;
const MAX_DEPTH = 3;

export interface FileEntry {
  path: string;
  size: number;
}

export function isValidScanId(id: string): boolean {
  return SCAN_ID.test(id);
}

/** Absolute path for `rel` inside `scansDir/id`, or null if either is unsafe. */
export function resolveScanPath(scansDir: string, id: string, rel: string): string | null {
  if (!isValidScanId(id)) return null;
  const segments = rel.split("/");
  if (segments.length > MAX_DEPTH || !segments.every((s) => SEGMENT.test(s))) return null;
  const scanDir = resolve(scansDir, id);
  const full = resolve(scanDir, ...segments);
  return full.startsWith(scanDir + sep) ? full : null;
}

/** Uploaded files under `scanDir`, as sorted posix-relative paths. Skips dotfiles and `.partial` files. */
export async function listFiles(scanDir: string): Promise<FileEntry[]> {
  const out: FileEntry[] = [];
  async function walk(dir: string, prefix: string): Promise<void> {
    let entries;
    try {
      entries = await readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (e.name.startsWith(".") || e.name.endsWith(".partial")) continue;
      const rel = prefix ? `${prefix}/${e.name}` : e.name;
      if (e.isDirectory()) await walk(join(dir, e.name), rel);
      else if (e.isFile()) out.push({ path: rel, size: (await stat(join(dir, e.name))).size });
    }
  }
  await walk(scanDir, "");
  return out.sort((a, b) => a.path.localeCompare(b.path));
}

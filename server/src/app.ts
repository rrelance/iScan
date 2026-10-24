import Fastify, { type FastifyInstance } from "fastify";
import { createWriteStream, existsSync } from "node:fs";
import { mkdir, readdir, rename, stat, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { pipeline } from "node:stream/promises";
import type { Readable } from "node:stream";
import { isValidScanId, listFiles, resolveScanPath, type FileEntry } from "./scans.js";

export interface AppOptions {
  scansDir: string;
}

export function buildApp({ scansDir }: AppOptions): FastifyInstance {
  const app = Fastify({ bodyLimit: 1_000_000_000 });

  app.addContentTypeParser("application/octet-stream", (_req, payload, done) => done(null, payload));

  app.get("/api/health", async () => ({ ok: true, name: "iscan" }));

  app.get("/api/scans", async () => {
    let names: string[] = [];
    try {
      names = await readdir(scansDir);
    } catch {
      return [];
    }
    const scans = [];
    for (const id of names.filter(isValidScanId).sort()) {
      const dir = join(scansDir, id);
      scans.push({ id, complete: existsSync(join(dir, ".complete")), fileCount: (await listFiles(dir)).length });
    }
    return scans;
  });

  app.get<{ Params: { id: string } }>("/api/scans/:id/status", async (req, reply) => {
    if (!isValidScanId(req.params.id)) return reply.code(400).send({ error: "invalid scan id" });
    return { files: await listFiles(join(scansDir, req.params.id)) };
  });

  app.put<{ Params: { id: string; "*": string } }>("/api/scans/:id/files/*", async (req, reply) => {
    const target = resolveScanPath(scansDir, req.params.id, req.params["*"]);
    if (!target) return reply.code(400).send({ error: "invalid scan id or path" });
    await mkdir(dirname(target), { recursive: true });
    const partial = `${target}.partial`;
    await pipeline(req.body as Readable, createWriteStream(partial));
    await rename(partial, target);
    return { ok: true, size: (await stat(target)).size };
  });

  app.post<{ Params: { id: string }; Body: { files?: FileEntry[] } }>("/api/scans/:id/complete", async (req, reply) => {
    const { id } = req.params;
    const declared = req.body?.files;
    if (!isValidScanId(id) || !Array.isArray(declared)) return reply.code(400).send({ error: "invalid request" });
    if (declared.some((f) => !resolveScanPath(scansDir, id, String(f.path)))) {
      return reply.code(400).send({ error: "invalid path" });
    }
    const dir = join(scansDir, id);
    const present = new Map((await listFiles(dir)).map((f) => [f.path, f.size]));
    const missing = declared.filter((f) => present.get(f.path) !== f.size).map((f) => f.path);
    if (missing.length > 0) return reply.code(409).send({ missing });
    await writeFile(join(dir, ".complete"), new Date().toISOString());
    return { ok: true, fileCount: declared.length };
  });

  return app;
}

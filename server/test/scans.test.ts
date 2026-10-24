import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { mkdtemp, readdir, rm, stat, writeFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/app.js";

const ID = "20261024-140509";
let root: string;
let scansDir: string;
let app: FastifyInstance;

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "iscan-"));
  scansDir = join(root, "scans");
  app = buildApp({ scansDir });
  await app.ready();
});

afterEach(async () => {
  await app.close();
  await rm(root, { recursive: true, force: true });
});

function put(path: string, body: Buffer, id = ID) {
  return app.inject({
    method: "PUT",
    url: `/api/scans/${id}/files/${path}`,
    headers: { "content-type": "application/octet-stream" },
    payload: body,
  });
}

describe("scan upload API", () => {
  it("reports health", async () => {
    const res = await app.inject({ method: "GET", url: "/api/health" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true, name: "iscan" });
  });

  it("stores an uploaded file and lists it in status", async () => {
    const res = await put("frames/0001.jpg", Buffer.alloc(5 * 1024 * 1024, 7));
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true, size: 5242880 });
    const status = await app.inject({ method: "GET", url: `/api/scans/${ID}/status` });
    expect(status.json()).toEqual({ files: [{ path: "frames/0001.jpg", size: 5242880 }] });
  });

  it("returns an empty status for an unknown scan", async () => {
    const status = await app.inject({ method: "GET", url: `/api/scans/${ID}/status` });
    expect(status.json()).toEqual({ files: [] });
  });

  // Dot segments are normalized away before routing (404); everything else must hit the validator (400).
  it.each([
    ["../../evil", [404]],
    ["%2e%2e/evil", [404]],
    ["%2E%2E%2Fevil", [400]],
    ["/abs", [400]],
    [".hidden", [400]],
    ["a/b/c/d/e", [400]],
    ["a%5C..%5Cevil", [400]],
    ["frames/%2e%2e%2f%2e%2e%2fevil", [400]],
  ])("rejects unsafe path %s", async (p, codes) => {
    const res = await put(p as string, Buffer.from("x"));
    expect(codes).toContain(res.statusCode);
    expect(existsSync(join(root, "evil"))).toBe(false);
    expect(existsSync(scansDir) ? await readdir(scansDir) : []).toEqual([]);
  });

  it("rejects an invalid scan id", async () => {
    const res = await put("manifest.json", Buffer.from("{}"), "2026-10-24");
    expect(res.statusCode).toBe(400);
    const status = await app.inject({ method: "GET", url: "/api/scans/..%2F..%2Fx/status" });
    expect(status.statusCode).toBe(400);
  });

  it("does not list leftover partial files", async () => {
    await mkdir(join(scansDir, ID), { recursive: true });
    await writeFile(join(scansDir, ID, "manifest.json.partial"), "half");
    const status = await app.inject({ method: "GET", url: `/api/scans/${ID}/status` });
    expect(status.json()).toEqual({ files: [] });
  });

  it("completes only when every declared file is present with the right size", async () => {
    await put("manifest.json", Buffer.from("{}"));
    const files = [
      { path: "manifest.json", size: 2 },
      { path: "mesh.ply", size: 4 },
    ];
    const missing = await app.inject({ method: "POST", url: `/api/scans/${ID}/complete`, payload: { files } });
    expect(missing.statusCode).toBe(409);
    expect(missing.json()).toEqual({ missing: ["mesh.ply"] });

    await put("mesh.ply", Buffer.from("abcd"));
    const ok = await app.inject({ method: "POST", url: `/api/scans/${ID}/complete`, payload: { files } });
    expect(ok.statusCode).toBe(200);
    expect(ok.json()).toEqual({ ok: true, fileCount: 2 });
    expect(existsSync(join(scansDir, ID, ".complete"))).toBe(true);

    const list = await app.inject({ method: "GET", url: "/api/scans" });
    expect(list.json()).toEqual([{ id: ID, complete: true, fileCount: 2 }]);
  });

  it("treats a wrong-size file as missing", async () => {
    await put("mesh.ply", Buffer.from("ab"));
    const res = await app.inject({
      method: "POST",
      url: `/api/scans/${ID}/complete`,
      payload: { files: [{ path: "mesh.ply", size: 4 }] },
    });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ missing: ["mesh.ply"] });
  });

  it("overwrites a file on re-upload", async () => {
    await put("mesh.ply", Buffer.from("ab"));
    await put("mesh.ply", Buffer.from("abcdef"));
    expect((await stat(join(scansDir, ID, "mesh.ply"))).size).toBe(6);
    expect(await readdir(join(scansDir, ID))).toEqual(["mesh.ply"]);
  });
});

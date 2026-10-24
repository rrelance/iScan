import { describe, expect, it } from "vitest";
import { advertisement } from "../src/bonjour.js";

describe("Bonjour advertisement", () => {
  it("points the SRV record at a resolvable .local host name", () => {
    expect(advertisement("XI-Laptop", 8787)).toEqual({ name: "iScan", type: "iscan", port: 8787, host: "XI-Laptop.local" });
  });

  it("does not double the .local suffix", () => {
    expect(advertisement("gym-pc.local", 8787).host).toBe("gym-pc.local");
  });
});

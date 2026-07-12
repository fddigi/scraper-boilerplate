import { describe, expect, it } from "vitest";
import { parseBearerToken } from "../src/middleware";

describe("parseBearerToken", () => {
  it("extracts the token from a well-formed Authorization header", () => {
    expect(parseBearerToken("Bearer abc.def")).toBe("abc.def");
  });

  it("returns null for a missing header", () => {
    expect(parseBearerToken(null)).toBeNull();
    expect(parseBearerToken(undefined)).toBeNull();
  });

  it("returns null for a header without the Bearer prefix", () => {
    expect(parseBearerToken("abc.def")).toBeNull();
    expect(parseBearerToken("Basic abc.def")).toBeNull();
  });

  it("returns null for 'Bearer ' with no token after it", () => {
    expect(parseBearerToken("Bearer ")).toBeNull();
    expect(parseBearerToken("Bearer    ")).toBeNull();
  });
});

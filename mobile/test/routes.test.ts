import assert from "node:assert/strict";
import test from "node:test";
import { pathForTab, tabForPath, titleForTab } from "../src/routes";

test("maps public paths to tabs", () => {
  assert.equal(tabForPath("/"), "morning");
  assert.equal(tabForPath("/matin"), "morning");
  assert.equal(tabForPath("/soir/"), "evening");
  assert.equal(tabForPath("/alarmes"), "alarms");
  assert.equal(tabForPath("/reveil"), "system");
  assert.equal(tabForPath("/inconnue"), undefined);
});

test("maps tabs to canonical paths and titles", () => {
  assert.equal(pathForTab("morning"), "/");
  assert.equal(pathForTab("evening"), "/soir");
  assert.equal(pathForTab("alarms"), "/alarmes");
  assert.equal(pathForTab("system"), "/reveil");
  assert.equal(titleForTab("system"), "Réveil · Robine Wake");
});

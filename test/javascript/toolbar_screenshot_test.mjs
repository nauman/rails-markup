import assert from "node:assert/strict";
import test from "node:test";
import { createToolbarHarness } from "./support/toolbar_harness.mjs";

function setup(t) {
  const harness = createToolbarHarness();
  t.after(() => harness.reset());
  harness.toolbar.init({ enableScreenshots: true });
  return { ...harness, el: id => harness.window.document.getElementById(id) };
}

test("unsupported native capture offers an attachment fallback", async t => {
  const { toolbar, window, el } = setup(t);
  Object.defineProperty(window.navigator, "mediaDevices", { value: {}, configurable: true });
  await toolbar._attachScreen();
  assert.match(el("rm-screenshot-status").textContent, /Upload or paste/i);
  assert.equal(el("rm-attach-screen").disabled, false);
});

test("cancelled screen permission leaves feedback usable", async t => {
  const { toolbar, window, el } = setup(t);
  Object.defineProperty(window.navigator, "mediaDevices", { value: {
    getDisplayMedia: async () => { throw Object.assign(new Error("Denied"), { name: "NotAllowedError" }); }
  }, configurable: true });
  el("rm-popup-input").value = "Keep my feedback";
  await toolbar._attachScreen();
  assert.match(el("rm-screenshot-status").textContent, /cancelled/);
  assert.equal(el("rm-popup-input").value, "Keep my feedback");
  assert.equal(el("rm-attach-screen").disabled, false);
});

test("screen stream is stopped even when frame acquisition fails", async t => {
  const { toolbar, window, el } = setup(t);
  let stopped = 0;
  Object.defineProperty(window.navigator, "mediaDevices", { value: {
    getDisplayMedia: async () => ({ getTracks: () => [{ stop: () => stopped++ }] })
  }, configurable: true });
  const original = window.HTMLVideoElement.prototype.play;
  window.HTMLVideoElement.prototype.play = async () => { throw new Error("Frame unavailable"); };
  t.after(() => { window.HTMLVideoElement.prototype.play = original; });
  await toolbar._attachScreen();
  assert.equal(stopped, 1);
  assert.equal(el("rm-attach-screen").disabled, false);
  assert.equal(toolbar.root.style.visibility, "");
});

test("attachment validation rejects oversized or unsupported images", async t => {
  const { toolbar, el } = setup(t);
  await toolbar._attachScreenshotFile({ type: "image/svg+xml", size: 10 });
  assert.match(el("rm-screenshot-status").textContent, /PNG, JPEG, or WebP/);
  await toolbar._attachScreenshotFile({ type: "image/png", size: 6 * 1024 * 1024 });
  assert.match(el("rm-screenshot-status").textContent, /under 5 MB/);
  assert.equal(toolbar._currentScreenshot, null);
});

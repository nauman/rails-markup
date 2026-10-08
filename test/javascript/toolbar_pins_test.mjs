import assert from "node:assert/strict";
import test from "node:test";
import { createToolbarHarness } from "./support/toolbar_harness.mjs";

test("edge annotations keep their pins inside a narrow viewport after resize", (t) => {
  const harness = createToolbarHarness();
  t.after(() => harness.reset());
  const { window, toolbar } = harness;
  toolbar.init({ enableScreenshots: false });
  window.innerWidth = 390;
  const target = window.document.createElement("p");
  target.id = "edge-target";
  window.document.body.appendChild(target);
  target.getBoundingClientRect = () => ({ top: 2, left: 8, width: 374, height: 30 });
  const annotation = { id: 1, comment: "Spacing", status: "pending", element: {
    selector: "#edge-target", boundingBox: { top: 2, left: 8, width: 374, height: 30 }
  } };
  toolbar.annotations = [annotation];
  toolbar._renderPin(annotation);
  const pin = window.document.querySelector('[data-pin-id="1"]');
  assert.ok(parseFloat(pin.style.left) >= 0);
  assert.ok(parseFloat(pin.style.left) + 20 <= 390);
  assert.ok(parseFloat(pin.style.top) >= 0);

  window.innerWidth = 320;
  toolbar._repositionPins();
  assert.ok(parseFloat(pin.style.left) + 20 <= 320);
});

test("pin clamping accounts for a horizontally scrolled host", (t) => {
  const harness = createToolbarHarness();
  t.after(() => harness.reset());
  harness.window.innerWidth = 390;
  Object.defineProperty(harness.window, "scrollX", { value: 100, configurable: true });
  const pin = harness.window.document.createElement("div");
  harness.toolbar._positionPin(pin, { top: 80, left: 100, width: 600 });
  assert.ok(parseFloat(pin.style.left) >= 100);
  assert.ok(parseFloat(pin.style.left) + 20 <= 490);
});

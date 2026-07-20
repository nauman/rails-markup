import assert from "node:assert/strict";
import test from "node:test";

import { createFakeFetch } from "./support/fake_fetch.mjs";
import { createToolbarHarness } from "./support/toolbar_harness.mjs";

test("online state is mutable", (t) => {
  const harness = createToolbarHarness({ online: false });
  t.after(() => harness.reset());

  assert.equal(harness.window.navigator.onLine, false);
  harness.setOnline(true);
  assert.equal(harness.window.navigator.onLine, true);
});

test("timers advance manually without real waits", async (t) => {
  const harness = createToolbarHarness();
  t.after(() => harness.reset());
  const events = [];
  const intervalId = harness.window.setInterval(() => events.push("interval"), 5);
  harness.window.setTimeout(() => events.push("timeout"), 10);
  harness.window.setTimeout(() => events.push("same-time-first"), 15);
  harness.window.setTimeout(() => events.push("same-time-second"), 15);
  const timeoutSignal = harness.window.AbortSignal.timeout(15);
  timeoutSignal.addEventListener("abort", () => events.push("abort"));

  await harness.advanceTimersBy(4);
  assert.deepEqual(events, []);
  await harness.advanceTimersBy(1);
  assert.deepEqual(events, ["interval"]);
  await harness.advanceTimersBy(5);
  assert.deepEqual(events, ["interval", "timeout", "interval"]);
  await harness.advanceTimersBy(5);
  assert.deepEqual(events, ["interval", "timeout", "interval", "same-time-first", "same-time-second", "abort", "interval"]);
  harness.window.clearInterval(intervalId);
  assert.equal(harness.pendingTimerCount(), 0);
});

test("deferred fetches expose requests and settle explicitly", async () => {
  const fetch = createFakeFetch();
  const deferred = fetch.defer();
  const responsePromise = fetch("/annotations/client-id", { method: "PUT", body: "desired" });

  assert.deepEqual(fetch.lastCall(), {
    url: "/annotations/client-id",
    options: { method: "PUT", body: "desired" }
  });
  deferred.respondWith({ saved: true });
  assert.deepEqual(await (await responsePromise).json(), { saved: true });

  const rejected = fetch.defer();
  const rejectedPromise = fetch("/annotations/client-id", { method: "DELETE" });
  rejected.reject(new Error("offline"));
  await assert.rejects(rejectedPromise, /offline/);
});

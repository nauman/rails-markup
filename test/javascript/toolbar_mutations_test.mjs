import assert from "node:assert/strict";
import test from "node:test";

import { createFakeFetch } from "./support/fake_fetch.mjs";
import { createToolbarHarness } from "./support/toolbar_harness.mjs";

const clientId = "11111111-1111-4111-8111-111111111111";
const createDirtyFields = ["content", "intent", "severity", "selected_text", "target", "page_url", "metadata"];

function injectToolbar(harness) {
  harness.toolbar._injectStyles();
  harness.toolbar._injectDOM();
  harness.toolbar._bindEvents();
}

function serverBackedAnnotation(overrides = {}) {
  return {
    id: 7,
    clientId,
    serverId: 42,
    serverUpdatedAt: "2026-07-20T10:00:00Z",
    syncState: "synced",
    dirtyFields: [],
    revision: 3,
    comment: "Before",
    intent: "change",
    severity: "suggestion",
    element: { selector: "main", nearbyText: "Welcome" },
    selectedText: "Selected",
    screenshot: null,
    url: "https://example.test/products",
    pathname: "/products",
    pageUrl: "/products",
    timestamp: "2026-07-20T09:00:00Z",
    status: "acknowledged",
    thread: [{ role: "agent", message: "Server reply" }],
    metadata: { author: "Server Author", serverOnly: true, tool: "toolbar" },
    ...overrides
  };
}

test("create persists complete desired state and outbox before scheduled network work", async (t) => {
  const fetch = createFakeFetch();
  const deferred = fetch.defer();
  const harness = createToolbarHarness({ uuids: [clientId], url: "https://example.test/products?open=1", fetch });
  t.after(() => harness.reset());
  injectToolbar(harness);
  let documentAtFetch;
  harness.toolbar._flushOutbox = () => {
    documentAtFetch = harness.storageDocument();
    return fetch("/flush", { method: "PUT" });
  };
  harness.toolbar._currentElement = { selector: "main", nearbyText: "Products" };
  harness.window.document.getElementById("rm-popup-input").value = "Created locally";
  harness.window.document.getElementById("rm-intent-select").value = "fix";
  harness.window.document.getElementById("rm-severity-select").value = "important";

  harness.toolbar.submitAnnotation();

  assert.equal(fetch.calls.length, 0);
  const stored = harness.storageDocument();
  const annotation = stored.annotations[0];
  const entry = stored.outbox[clientId];
  assert.equal(annotation.syncState, "pending");
  assert.deepEqual(annotation.dirtyFields, createDirtyFields);
  assert.equal(entry.type, "upsert");
  assert.equal(entry.syncState, "pending");
  assert.equal(entry.clientId, clientId);
  assert.equal(entry.revision, annotation.revision);
  assert.deepEqual(entry.dirtyFields, createDirtyFields);
  assert.deepEqual(entry.annotation, {
    clientId,
    page_url: "/products?open=1",
    content: "Created locally",
    intent: "fix",
    severity: "important",
    selected_text: null,
    target: { selector: "main", nearbyText: "Products" },
    metadata: { tool: "rails-markup", url: "https://example.test/products?open=1", localId: 1 },
    status: "pending"
  });

  await harness.advanceTimersBy(0);
  assert.equal(fetch.calls.length, 1);
  assert.deepEqual(documentAtFetch, stored);
  deferred.respondWith({});
});

test("content edit persists before scheduled work and queues only canonical browser fields", async (t) => {
  const annotation = serverBackedAnnotation();
  const harness = createToolbarHarness({ storage: { "rm-annotations": { annotations: [annotation], nextId: 8, outbox: {} } } });
  t.after(() => harness.reset());
  injectToolbar(harness);
  harness.toolbar._loadFromStorage();
  const deferred = harness.fetch.defer();
  let documentAtFlush;
  harness.toolbar._flushOutbox = () => {
    documentAtFlush = harness.storageDocument();
    return harness.fetch("/flush", { method: "PUT" });
  };

  harness.toolbar._editAnnotation(7);
  harness.window.document.getElementById("rm-popup-input").value = "After";
  harness.toolbar.submitAnnotation();

  const stored = harness.storageDocument();
  const local = stored.annotations[0];
  const entry = stored.outbox[clientId];
  assert.equal(local.serverId, 42);
  assert.equal(local.serverUpdatedAt, "2026-07-20T10:00:00Z");
  assert.deepEqual(local.thread, [{ role: "agent", message: "Server reply" }]);
  assert.equal(local.metadata.author, "Server Author");
  assert.equal(local.syncState, "pending");
  assert.deepEqual(local.dirtyFields, ["content"]);
  assert.deepEqual(entry.dirtyFields, ["content"]);
  assert.equal(entry.annotation.content, "After");
  assert.equal(entry.annotation.selected_text, "Selected");
  assert.deepEqual(entry.annotation.target, { selector: "main", nearbyText: "Welcome" });
  assert.deepEqual(entry.annotation.metadata, { tool: "toolbar", url: "https://example.test/products", localId: 7 });
  for (const serverOwned of ["serverId", "serverUpdatedAt", "thread", "syncState", "dirtyFields", "revision", "id", "comment", "element"]) {
    assert.equal(Object.hasOwn(entry.annotation, serverOwned), false, `${serverOwned} must not enter desired payload`);
  }
  assert.equal(documentAtFlush, undefined);
  assert.equal(harness.fetch.calls.length, 0);
  await harness.advanceTimersBy(0);
  assert.deepEqual(documentAtFlush, stored);
  assert.equal(harness.fetch.calls.length, 1);
  deferred.respondWith({});
});

test("status persists before scheduled work and coalesces with the current upsert", async (t) => {
  const harness = createToolbarHarness({ storage: { "rm-annotations": { annotations: [serverBackedAnnotation()], nextId: 8, outbox: {} } } });
  t.after(() => harness.reset());
  injectToolbar(harness);
  harness.toolbar._loadFromStorage();
  const deferred = harness.fetch.defer();
  let documentAtFlush;
  harness.toolbar._flushOutbox = () => {
    documentAtFlush = harness.storageDocument();
    return harness.fetch("/flush", { method: "PUT" });
  };
  harness.toolbar._editAnnotation(7);
  harness.window.document.getElementById("rm-popup-input").value = "After";
  harness.toolbar.submitAnnotation();
  const editRevision = harness.toolbar.outbox[clientId].revision;

  harness.toolbar._changeStatus(7, "resolved");

  const stored = harness.storageDocument();
  assert.deepEqual(Object.keys(stored.outbox), [clientId]);
  assert.equal(stored.outbox[clientId].annotation.content, "After");
  assert.equal(stored.outbox[clientId].annotation.status, "resolved");
  assert.deepEqual(stored.outbox[clientId].dirtyFields, ["content", "status"]);
  assert.deepEqual(stored.annotations[0].dirtyFields, ["content", "status"]);
  assert.ok(stored.outbox[clientId].revision > editRevision);
  assert.equal(documentAtFlush, undefined);
  assert.equal(harness.fetch.calls.length, 0);
  await harness.advanceTimersBy(0);
  assert.deepEqual(documentAtFlush, stored);
  assert.equal(harness.fetch.calls.length, 1);
  deferred.respondWith({});
});

test("delete durably removes UI state and replaces the upsert before scheduled work", async (t) => {
  const annotation = serverBackedAnnotation({ syncState: "pending", dirtyFields: ["content"] });
  const upsert = {
    type: "upsert", clientId, revision: 4, syncState: "pending",
    annotation: { clientId, page_url: "/products", content: "Before" }, dirtyFields: ["content"]
  };
  const harness = createToolbarHarness({ storage: { "rm-annotations": { annotations: [annotation], nextId: 8, outbox: { [clientId]: upsert } } } });
  t.after(() => harness.reset());
  injectToolbar(harness);
  harness.toolbar._loadFromStorage();
  harness.toolbar._renderPins();
  const deferred = harness.fetch.defer();
  let documentAtFlush;
  harness.toolbar._flushOutbox = () => {
    documentAtFlush = harness.storageDocument();
    return harness.fetch("/flush", { method: "DELETE" });
  };

  harness.toolbar._deleteAnnotation(7);

  const stored = harness.storageDocument();
  assert.deepEqual(stored.annotations, []);
  assert.deepEqual(stored.outbox[clientId], {
    type: "delete", clientId, revision: 5, syncState: "pending"
  });
  assert.equal(harness.window.document.querySelector('[data-card-id="7"]'), null);
  assert.equal(harness.window.document.querySelector('[data-pin-id="7"]'), null);
  assert.equal(documentAtFlush, undefined);
  assert.equal(harness.fetch.calls.length, 0);
  await harness.advanceTimersBy(0);
  assert.deepEqual(documentAtFlush, stored);
  assert.equal(harness.fetch.calls.length, 1);
  deferred.respondWith({});
});

test("failed upsert exposes manual retry without losing desired state", async (t) => {
  const desired = { clientId, page_url: "/products", content: "Retry me", status: "pending" };
  const annotation = serverBackedAnnotation({ comment: "Retry me", syncState: "failed", dirtyFields: ["content"], revision: 4 });
  const harness = createToolbarHarness({ storage: { "rm-annotations": { annotations: [annotation], nextId: 8, outbox: {
    [clientId]: { type: "upsert", clientId, revision: 4, syncState: "failed", annotation: desired, dirtyFields: ["content"] }
  } } } });
  t.after(() => harness.reset());
  injectToolbar(harness);
  harness.toolbar._loadFromStorage();
  let flushes = 0;
  harness.toolbar._flushOutbox = () => { flushes += 1; };

  const retry = harness.window.document.querySelector(`[data-retry-client-id="${clientId}"]`);
  assert.ok(retry);
  harness.toolbar._retrySync(clientId);

  const stored = harness.storageDocument();
  assert.equal(stored.outbox[clientId].syncState, "pending");
  assert.deepEqual(stored.outbox[clientId].annotation, desired);
  assert.equal(stored.annotations[0].syncState, "pending");
  assert.equal(flushes, 0);
  await harness.advanceTimersBy(0);
  assert.equal(flushes, 1);
});

test("failed delete remains visible and retryable after its card is gone", async (t) => {
  const tombstone = { type: "delete", clientId, revision: 9, syncState: "failed" };
  const harness = createToolbarHarness({ storage: { "rm-annotations": { annotations: [], nextId: 8, outbox: { [clientId]: tombstone } } } });
  t.after(() => harness.reset());
  injectToolbar(harness);
  harness.toolbar._loadFromStorage();
  let flushes = 0;
  harness.toolbar._flushOutbox = () => { flushes += 1; };

  assert.ok(harness.window.document.querySelector(`[data-retry-client-id="${clientId}"]`));
  assert.match(harness.window.document.getElementById("rm-panel-list").textContent, /Delete failed/);
  harness.toolbar._retrySync(clientId);

  assert.deepEqual(harness.storageDocument().outbox[clientId], { ...tombstone, syncState: "pending" });
  await harness.advanceTimersBy(0);
  assert.equal(flushes, 1);
});

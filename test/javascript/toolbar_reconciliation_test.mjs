import assert from "node:assert/strict";
import test from "node:test";

import { createFakeFetch } from "./support/fake_fetch.mjs";
import { createToolbarHarness } from "./support/toolbar_harness.mjs";

const localId = "11111111-1111-4111-8111-111111111111";
const serverOnlyId = "22222222-2222-4222-8222-222222222222";
const tombstoneId = "33333333-3333-4333-8333-333333333333";
const absentId = "44444444-4444-4444-8444-444444444444";

function localAnnotation(clientId = localId, overrides = {}) {
  return {
    id: 1,
    clientId,
    serverId: "101",
    userId: 7,
    authorName: "Old owner",
    syncState: "synced",
    serverUpdatedAt: "2026-07-20T00:00:01Z",
    dirtyFields: [],
    revision: 1,
    comment: "Local content",
    intent: "change",
    severity: "suggestion",
    status: "pending",
    selectedText: null,
    element: { selector: "main" },
    metadata: { tool: "rails-markup", localId: 1, url: "https://example.test/products?open=1" },
    pathname: "/products?open=1",
    pageUrl: "/products?open=1",
    url: "https://example.test/products?open=1",
    thread: [],
    createdAt: "2026-07-20T00:00:00Z",
    ...overrides
  };
}

function serverRepresentation(clientId = localId, overrides = {}) {
  return {
    id: clientId === localId ? "101" : "202",
    clientId,
    userId: 77,
    authorName: "Server owner",
    content: "Server content",
    intent: "fix",
    severity: "important",
    status: "resolved",
    selectedText: "Server selection",
    pageUrl: "/products?open=1",
    target: { selector: "#server" },
    metadata: { tool: "rails-markup", localId: 99, url: "https://example.test/products?open=1" },
    thread: [{ role: "agent", message: "Server reply" }],
    createdAt: "2026-07-20T00:00:00Z",
    updatedAt: "2026-07-20T00:00:02Z",
    ...overrides
  };
}

function upsertEntry(annotation, dirtyFields = annotation.dirtyFields) {
  return {
    type: "upsert",
    clientId: annotation.clientId,
    revision: annotation.revision,
    syncState: "pending",
    annotation: {
      clientId: annotation.clientId,
      page_url: annotation.pageUrl,
      content: annotation.comment,
      intent: annotation.intent,
      severity: annotation.severity,
      selected_text: annotation.selectedText,
      target: annotation.element,
      metadata: annotation.metadata,
      status: annotation.status
    },
    dirtyFields: dirtyFields.slice()
  };
}

function reconciliationHarness({ annotations = [], outbox = {}, fetch = createFakeFetch(), url } = {}) {
  const harness = createToolbarHarness({
    url: url || "https://example.test/products?open=1",
    fetch,
    storage: { "rm-annotations": { annotations, nextId: 10, outbox } }
  });
  harness.toolbar._loadFromStorage();
  harness.toolbar.serverOnline = true;
  return harness;
}

test("a successful reconnect initializes the session, pulls the exact page, then flushes", async (t) => {
  const annotation = localAnnotation(localId, { dirtyFields: ["content"], syncState: "pending" });
  const fetch = createFakeFetch();
  fetch.respondWith({ ok: true });
  fetch.respondWith({ id: "rm-session" });
  fetch.respondWith([serverRepresentation(localId)]);
  fetch.respondWith(serverRepresentation(localId, { content: "Local content", updatedAt: "2026-07-20T00:00:03Z" }));
  const harness = reconciliationHarness({ annotations: [annotation], outbox: { [localId]: upsertEntry(annotation) }, fetch });
  t.after(() => harness.reset());
  harness.toolbar.serverOnline = false;

  await harness.toolbar._checkHealth();

  assert.deepEqual(fetch.calls.map(call => call.url), [
    "/feedback/api/health",
    "/feedback/api/sessions",
    "/feedback/api/annotations?page_url=%2Fproducts%3Fopen%3D1",
    `/feedback/api/annotations/${localId}`
  ]);
  assert.equal(fetch.calls[2].options.credentials, "same-origin");
  assert.equal(fetch.calls[3].options.method, "PUT");
  const desired = JSON.parse(fetch.calls[3].options.body);
  assert.equal(desired.page_url, "/products?open=1");
  assert.equal(desired.metadata.url, "https://example.test/products?open=1");
});

test("a failed pull still flushes durable state without applying absence deletion", async (t) => {
  const pending = localAnnotation(localId, { dirtyFields: ["content"], syncState: "pending" });
  const clean = localAnnotation(absentId, { id: 4, serverId: "404" });
  const fetch = createFakeFetch();
  fetch.respondWith({ ok: true });
  fetch.respondWith({ id: "rm-session" });
  fetch.respondWith({ error: "later" }, { status: 500 });
  fetch.respondWith(serverRepresentation(localId, { content: pending.comment }));
  const harness = reconciliationHarness({ annotations: [pending, clean], outbox: { [localId]: upsertEntry(pending) }, fetch });
  t.after(() => harness.reset());
  harness.toolbar.serverOnline = false;

  await harness.toolbar._checkHealth();

  assert.equal(fetch.calls.at(-1).options.method, "PUT");
  assert.ok(harness.toolbar.annotations.some(annotation => annotation.clientId === absentId));
  assert.equal(harness.toolbar._pullNeeded, true);
});

test("a failed pull is retried after a later healthy check", async (t) => {
  const fetch = createFakeFetch();
  fetch.respondWith({ ok: true });
  fetch.respondWith({ id: "rm-session" });
  fetch.respondWith("broken", { rawBody: true, headers: { "Content-Type": "application/json" } });
  fetch.respondWith({ ok: true });
  fetch.respondWith([]);
  const harness = reconciliationHarness({ fetch });
  t.after(() => harness.reset());
  harness.toolbar.serverOnline = false;

  await harness.toolbar._checkHealth();
  assert.equal(harness.toolbar._pullNeeded, true);
  await harness.toolbar._checkHealth();

  assert.equal(harness.toolbar._pullNeeded, false);
  assert.equal(fetch.calls.filter(call => call.url.includes("/annotations?page_url=")).length, 2);
  assert.equal(fetch.calls.filter(call => call.url.endsWith("/sessions")).length, 1);
});

test("pull reconciles server ownership while preserving dirty browser fields and status", async (t) => {
  const dirty = localAnnotation(localId, {
    comment: "Offline edit",
    status: "acknowledged",
    dirtyFields: ["content", "status"],
    syncState: "pending"
  });
  const fetch = createFakeFetch();
  fetch.respondWith([serverRepresentation(localId), serverRepresentation(serverOnlyId)]);
  const harness = reconciliationHarness({ annotations: [dirty], outbox: { [localId]: upsertEntry(dirty) }, fetch });
  t.after(() => harness.reset());

  const complete = await harness.toolbar._pullAnnotations();

  assert.equal(complete, true);
  const merged = harness.toolbar.annotations.find(annotation => annotation.clientId === localId);
  assert.equal(merged.comment, "Offline edit");
  assert.equal(merged.status, "acknowledged");
  assert.equal(merged.intent, "fix");
  assert.equal(merged.severity, "important");
  assert.deepEqual(JSON.parse(JSON.stringify(merged.thread)), [{ role: "agent", message: "Server reply" }]);
  assert.equal(merged.userId, 77);
  assert.equal(merged.authorName, "Server owner");
  assert.equal(merged.serverUpdatedAt, "2026-07-20T00:00:02Z");
  assert.equal(harness.toolbar.outbox[localId].annotation.content, "Offline edit");
  assert.equal(harness.toolbar.outbox[localId].annotation.status, "acknowledged");
  assert.equal(harness.toolbar.outbox[localId].annotation.intent, "fix");

  const added = harness.toolbar.annotations.find(annotation => annotation.clientId === serverOnlyId);
  assert.ok(added);
  assert.equal(added.syncState, "synced");
  assert.equal(added.comment, "Server content");
  assert.ok(Number.isInteger(added.id));
});

test("pull refreshes non-dirty desired state in migrated outbox entries keyed only by UUID", async (t) => {
  const pending = localAnnotation(localId, { comment: "Dirty content", dirtyFields: ["content"], syncState: "pending" });
  const migratedEntry = upsertEntry(pending);
  delete migratedEntry.clientId;
  const fetch = createFakeFetch();
  fetch.respondWith([serverRepresentation(localId, { intent: "approve" })]);
  const harness = reconciliationHarness({ annotations: [pending], outbox: { [localId]: migratedEntry }, fetch });
  t.after(() => harness.reset());

  await harness.toolbar._pullAnnotations();

  assert.equal(harness.toolbar.outbox[localId].annotation.content, "Dirty content");
  assert.equal(harness.toolbar.outbox[localId].annotation.intent, "approve");
});

test("flush calls made during a pull share one deferred single-flight promise", async (t) => {
  const annotation = localAnnotation(localId, { dirtyFields: ["content"], syncState: "pending" });
  const fetch = createFakeFetch();
  const pull = fetch.defer();
  fetch.respondWith(serverRepresentation(localId, { content: annotation.comment }));
  const harness = reconciliationHarness({ annotations: [annotation], outbox: { [localId]: upsertEntry(annotation) }, fetch });
  t.after(() => harness.reset());

  harness.toolbar._pullAnnotations();
  const first = harness.toolbar._flushOutbox();
  const second = harness.toolbar._flushOutbox();

  assert.strictEqual(first, second);
  pull.respondWith([serverRepresentation(localId)]);
  await first;
  assert.equal(fetch.calls.filter(call => call.options.method === "PUT").length, 1);
});

test("navigation during a pending pull queues the new exact page before synchronization completes", async (t) => {
  const fetch = createFakeFetch();
  const oldPage = fetch.defer();
  const newPage = fetch.defer();
  const harness = reconciliationHarness({ fetch });
  t.after(() => harness.reset());

  const first = harness.toolbar._pullAnnotations();
  harness.window.history.pushState({}, "", "/products?open=2");
  const second = harness.toolbar._pullAnnotations();
  oldPage.respondWith([]);
  await first;
  assert.equal(fetch.calls[1].url, "/feedback/api/annotations?page_url=%2Fproducts%3Fopen%3D2");

  newPage.respondWith([]);
  assert.equal(await second, true);
  assert.equal(harness.toolbar._pullNeeded, false);
});

test("tombstones prevent resurrection and complete exact pulls remove only absent clean records", async (t) => {
  const tombstone = { type: "delete", clientId: tombstoneId, revision: 3, syncState: "pending" };
  const absent = localAnnotation(absentId, { id: 4, serverId: "404" });
  const otherQuery = localAnnotation(serverOnlyId, {
    id: 2,
    serverId: "202",
    pathname: "/products?open=2",
    pageUrl: "/products?open=2",
    url: "https://example.test/products?open=2"
  });
  const fetch = createFakeFetch();
  fetch.respondWith([serverRepresentation(tombstoneId)]);
  const harness = reconciliationHarness({ annotations: [absent, otherQuery], outbox: { [tombstoneId]: tombstone }, fetch });
  t.after(() => harness.reset());

  await harness.toolbar._pullAnnotations();

  assert.equal(harness.toolbar.annotations.some(annotation => annotation.clientId === tombstoneId), false);
  assert.ok(harness.toolbar.outbox[tombstoneId]);
  assert.equal(harness.toolbar.annotations.some(annotation => annotation.clientId === absentId), false);
  assert.equal(harness.toolbar.annotations.some(annotation => annotation.clientId === serverOnlyId), true);
});

test("stale server records and stale PUT responses cannot overwrite newer reconciled state", async (t) => {
  const newer = localAnnotation(localId, {
    comment: "Newer server value",
    status: "resolved",
    thread: [{ role: "agent", message: "Newest" }],
    serverUpdatedAt: "2026-07-20T00:00:05Z"
  });
  const fetch = createFakeFetch();
  fetch.respondWith([serverRepresentation(localId, { content: "Stale pull", updatedAt: "2026-07-20T00:00:04Z" })]);
  const harness = reconciliationHarness({ annotations: [newer], fetch });
  t.after(() => harness.reset());

  await harness.toolbar._pullAnnotations();
  assert.equal(harness.toolbar.annotations[0].comment, "Newer server value");
  assert.deepEqual(JSON.parse(JSON.stringify(harness.toolbar.annotations[0].thread)), [{ role: "agent", message: "Newest" }]);

  harness.toolbar.annotations[0].dirtyFields = ["content"];
  harness.toolbar.annotations[0].syncState = "pending";
  harness.toolbar._queueLocalMutation("upsert", harness.toolbar.annotations[0], ["content"]);
  harness.toolbar.serverOnline = true;
  fetch.respondWith(serverRepresentation(localId, { content: "Stale PUT", updatedAt: "2026-07-20T00:00:03Z" }));
  await harness.toolbar._flushOutbox();
  assert.equal(harness.toolbar.annotations[0].comment, "Newer server value");
  assert.equal(harness.toolbar.annotations[0].serverUpdatedAt, "2026-07-20T00:00:05Z");
});

test("invalid or incomplete pull responses never mutate state or delete absent records", async () => {
  for (const response of [
    { error: "not an array" },
    [serverRepresentation(localId), { broken: true }],
    [serverRepresentation(localId, { pageUrl: "/products?open=2" })],
    [serverRepresentation(localId), serverRepresentation(localId)]
  ]) {
    const original = localAnnotation(absentId, { id: 4, serverId: "404" });
    const fetch = createFakeFetch();
    fetch.respondWith(response);
    const harness = reconciliationHarness({ annotations: [original], fetch });

    assert.equal(await harness.toolbar._pullAnnotations(), false);
    assert.equal(harness.toolbar.annotations.length, 1);
    assert.equal(harness.toolbar.annotations[0].clientId, absentId);
    harness.reset();
  }
});

test("empty-query and query variants use independent exact page identities", async (t) => {
  const fetch = createFakeFetch();
  fetch.respondWith([]);
  const harness = reconciliationHarness({ url: "https://example.test/products", fetch });
  t.after(() => harness.reset());

  await harness.toolbar._pullAnnotations();

  assert.equal(fetch.calls[0].url, "/feedback/api/annotations?page_url=%2Fproducts");
  assert.equal(harness.toolbar._pageUrl(), "/products");
});

import assert from "node:assert/strict";
import test from "node:test";

import { createFakeFetch } from "./support/fake_fetch.mjs";
import { createToolbarHarness } from "./support/toolbar_harness.mjs";

const firstId = "11111111-1111-4111-8111-111111111111";
const secondId = "22222222-2222-4222-8222-222222222222";

function localAnnotation(clientId = firstId, overrides = {}) {
  return {
    id: clientId === firstId ? 1 : 2,
    clientId,
    serverId: null,
    syncState: "pending",
    serverUpdatedAt: null,
    dirtyFields: ["content"],
    revision: 1,
    comment: `Local ${clientId.slice(0, 1)}`,
    intent: "change",
    severity: "suggestion",
    status: "pending",
    selectedText: null,
    element: { selector: "main" },
    pathname: "/products?open=1",
    pageUrl: "/products?open=1",
    url: "https://example.test/products?open=1",
    thread: [],
    ...overrides
  };
}

function upsertEntry(annotation, overrides = {}) {
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
      metadata: { tool: "rails-markup", localId: annotation.id, url: annotation.url },
      status: annotation.status
    },
    dirtyFields: annotation.dirtyFields.slice(),
    ...overrides
  };
}

function serverRepresentation(annotation, overrides = {}) {
  return {
    id: String(annotation.id + 100),
    clientId: annotation.clientId,
    userId: 77,
    authorName: "Server Owner",
    content: annotation.comment,
    intent: annotation.intent,
    severity: annotation.severity,
    status: annotation.status,
    selectedText: annotation.selectedText,
    pageUrl: annotation.pageUrl,
    target: annotation.element,
    metadata: { tool: "rails-markup", localId: annotation.id },
    thread: [],
    createdAt: "2026-07-20T00:00:00Z",
    updatedAt: "2026-07-20T00:00:01Z",
    ...overrides
  };
}

function flushHarness({ annotations, outbox, fetch = createFakeFetch(), online = true } = {}) {
  const harness = createToolbarHarness({
    url: "https://example.test/products?open=1",
    fetch,
    online,
    storage: { "rm-annotations": { annotations, nextId: 3, outbox } }
  });
  harness.toolbar._loadFromStorage();
  harness.toolbar.serverOnline = online;
  return harness;
}

function nextTurn() {
  return new Promise(resolve => setImmediate(resolve));
}

test("flush is single-flight and sends entries serially with UUID PUT", async (t) => {
  const one = localAnnotation(firstId);
  const two = localAnnotation(secondId);
  const fetch = createFakeFetch();
  const first = fetch.defer();
  const second = fetch.defer();
  const harness = flushHarness({ annotations: [one, two], outbox: { [firstId]: upsertEntry(one), [secondId]: upsertEntry(two) }, fetch });
  t.after(() => harness.reset());

  const left = harness.toolbar._flushOutbox();
  const right = harness.toolbar._flushOutbox();
  assert.strictEqual(left, right);
  assert.equal(fetch.calls.length, 1);
  assert.equal(fetch.calls[0].url, "/feedback/api/annotations/" + firstId);
  assert.equal(fetch.calls[0].options.method, "PUT");

  first.respondWith(serverRepresentation(one));
  await nextTurn();
  assert.equal(fetch.calls.length, 2);
  second.respondWith(serverRepresentation(two));
  await left;
  assert.deepEqual(JSON.parse(JSON.stringify(harness.toolbar.outbox)), {});
});

test("health, online, and visibility work coalesce behind one health request and one flush", async (t) => {
  const annotation = localAnnotation();
  const fetch = createFakeFetch();
  const health = fetch.defer();
  const harness = flushHarness({ annotations: [annotation], outbox: { [firstId]: upsertEntry(annotation) }, fetch, online: false });
  t.after(() => harness.reset());
  let flushes = 0;
  harness.toolbar._flushOutbox = async () => { flushes += 1; };
  harness.toolbar._initSession = async () => {};

  harness.setOnline(true);
  const one = harness.toolbar._checkHealth();
  const two = harness.toolbar._checkHealth();
  harness.toolbar._onOnline();
  Object.defineProperty(harness.window.document, "hidden", { configurable: true, value: false });
  harness.toolbar._onVisibilityChange();
  assert.equal(fetch.calls.length, 1);

  health.respondWith({ ok: true });
  await Promise.all([one, two]);
  await nextTurn();
  assert.equal(flushes, 1);
});

test("an edit replacing an in-flight upsert is neither cleared nor overwritten", async (t) => {
  const annotation = localAnnotation();
  const fetch = createFakeFetch();
  const pending = fetch.defer();
  const replacement = fetch.defer();
  const harness = flushHarness({ annotations: [annotation], outbox: { [firstId]: upsertEntry(annotation) }, fetch });
  t.after(() => harness.reset());

  const flush = harness.toolbar._flushOutbox();
  assert.equal(fetch.calls.length, 1);
  harness.toolbar._persistLocalMutation("upsert", ["content"], () => {
    harness.toolbar.annotations[0].comment = "Newer local edit";
    return harness.toolbar.annotations[0];
  });
  pending.respondWith(serverRepresentation(annotation, { content: "Older server value" }));
  await nextTurn();

  assert.equal(harness.toolbar.annotations[0].comment, "Newer local edit");
  assert.equal(harness.toolbar.outbox[firstId].annotation.content, "Newer local edit");
  assert.equal(harness.toolbar.outbox[firstId].revision, 2);
  assert.equal(fetch.calls.length, 2);
  assert.equal(JSON.parse(fetch.calls[1].options.body).content, "Newer local edit");
  replacement.respondWith(serverRepresentation(annotation, { content: "Newer local edit" }));
  await flush;
  assert.equal(harness.toolbar.outbox[firstId], undefined);
  assert.equal(harness.toolbar.annotations[0].comment, "Newer local edit");
});

test("a delete replacing an in-flight upsert is not resurrected by the older response", async (t) => {
  const annotation = localAnnotation();
  const fetch = createFakeFetch();
  const pending = fetch.defer();
  const replacement = fetch.defer();
  const harness = flushHarness({ annotations: [annotation], outbox: { [firstId]: upsertEntry(annotation) }, fetch });
  t.after(() => harness.reset());

  const flush = harness.toolbar._flushOutbox();
  assert.equal(fetch.calls.length, 1);
  harness.toolbar._deleteAnnotation(annotation.id);
  pending.respondWith(serverRepresentation(annotation));
  await nextTurn();

  assert.equal(harness.toolbar.annotations.length, 0);
  assert.equal(harness.toolbar.outbox[firstId].type, "delete");
  assert.equal(harness.toolbar.outbox[firstId].revision, 2);
  assert.equal(fetch.calls.length, 2);
  assert.equal(fetch.calls[1].options.method, "DELETE");
  replacement.respondWith({}, { status: 204 });
  await flush;
  assert.equal(harness.toolbar.outbox[firstId], undefined);
});

test("DELETE 204 clears only the exact current tombstone without parsing JSON", async (t) => {
  const fetch = createFakeFetch();
  fetch.respondWith({}, { status: 204 });
  const tombstone = { type: "delete", clientId: firstId, revision: 7, syncState: "pending" };
  const other = { type: "delete", clientId: secondId, revision: 2, syncState: "failed" };
  const harness = flushHarness({ annotations: [], outbox: { [firstId]: tombstone, [secondId]: other }, fetch });
  t.after(() => harness.reset());

  await harness.toolbar._flushOutbox();
  assert.equal(fetch.calls[0].options.method, "DELETE");
  assert.deepEqual(JSON.parse(JSON.stringify(harness.toolbar.outbox)), { [secondId]: other });
});

test("DELETE accepts any successful response without requiring a representation", async (t) => {
  const fetch = createFakeFetch();
  fetch.respondWith("deleted", { status: 200, rawBody: true, headers: { "Content-Type": "text/plain" } });
  const tombstone = { type: "delete", clientId: firstId, revision: 7, syncState: "pending" };
  const harness = flushHarness({ annotations: [], outbox: { [firstId]: tombstone }, fetch });
  t.after(() => harness.reset());

  await harness.toolbar._flushOutbox();
  assert.equal(harness.toolbar.outbox[firstId], undefined);
});

test("successful PUT stores the full response, server id, and clears only sent dirty fields", async (t) => {
  const annotation = localAnnotation(undefined, { dirtyFields: ["content", "status"] });
  const fetch = createFakeFetch();
  const entry = upsertEntry(annotation);
  fetch.respondWith(serverRepresentation(annotation, { id: "91", content: "Canonical", status: "resolved", thread: [{ role: "agent", message: "Done" }] }));
  const harness = flushHarness({ annotations: [annotation], outbox: { [firstId]: entry }, fetch });
  t.after(() => harness.reset());

  await harness.toolbar._flushOutbox();
  const saved = harness.toolbar.annotations[0];
  assert.equal(saved.serverId, "91");
  assert.equal(saved.userId, 77);
  assert.equal(saved.authorName, "Server Owner");
  assert.equal(saved.createdAt, "2026-07-20T00:00:00Z");
  assert.equal(saved.comment, "Canonical");
  assert.equal(saved.status, "resolved");
  assert.deepEqual(JSON.parse(JSON.stringify(saved.thread)), [{ role: "agent", message: "Done" }]);
  assert.deepEqual(JSON.parse(JSON.stringify(saved.dirtyFields)), []);
  assert.equal(saved.syncState, "synced");
  assert.equal(saved.serverUpdatedAt, "2026-07-20T00:00:01Z");
});

test("successful PUT validates the complete API representation before mutating durable state", async () => {
  const annotation = localAnnotation();
  const valid = serverRepresentation(annotation);
  const invalidRepresentations = [
    {},
    { error: "not actually an annotation" },
    { ...valid, id: 101, userId: "77", target: [], status: "invented" },
    { ...valid, clientId: secondId },
    Object.fromEntries(Object.entries(valid).filter(([key]) => key !== "metadata"))
  ];

  for (const body of invalidRepresentations) {
    const fetch = createFakeFetch();
    fetch.respondWith(body);
    const originalEntry = upsertEntry(annotation);
    const harness = flushHarness({ annotations: [annotation], outbox: { [firstId]: originalEntry }, fetch });

    await harness.toolbar._flushOutbox();

    const saved = harness.toolbar.annotations[0];
    assert.equal(saved.serverId, null);
    assert.equal(saved.comment, annotation.comment);
    assert.equal(saved.syncState, "pending");
    assert.equal(harness.toolbar.outbox[firstId].malformedAttempts, 1);
    assert.equal(harness.toolbar.outbox[firstId].clientId, firstId);
    harness.reset();
  }
});

test("cross-origin mutation endpoints fail closed before sending CSRF or credentials", async (t) => {
  const annotation = localAnnotation();
  const fetch = createFakeFetch();
  const harness = flushHarness({ annotations: [annotation], outbox: { [firstId]: upsertEntry(annotation) }, fetch });
  t.after(() => harness.reset());
  const csrf = harness.window.document.createElement("meta");
  csrf.name = "csrf-token";
  csrf.content = "secret-csrf-token";
  harness.window.document.head.appendChild(csrf);
  harness.toolbar.endpoint = "//attacker.example/feedback/api";

  await harness.toolbar._flushOutbox();
  harness.toolbar.serverOnline = true;
  await harness.toolbar._initSession();
  await harness.toolbar._pushToServer(annotation);

  assert.equal(fetch.calls.length, 0);
  assert.ok(harness.toolbar.outbox[firstId]);
  assert.match(harness.toolbar._syncUnavailable, /same.origin|unavailable/i);
});

test("absolute same-origin mutation endpoints retain CSRF and same-origin credentials", async (t) => {
  const annotation = localAnnotation();
  const fetch = createFakeFetch();
  fetch.respondWith(serverRepresentation(annotation));
  const harness = flushHarness({ annotations: [annotation], outbox: { [firstId]: upsertEntry(annotation) }, fetch });
  t.after(() => harness.reset());
  const csrf = harness.window.document.createElement("meta");
  csrf.name = "csrf-token";
  csrf.content = "same-origin-token";
  harness.window.document.head.appendChild(csrf);
  harness.toolbar.endpoint = "https://example.test/feedback/api";

  await harness.toolbar._flushOutbox();

  assert.equal(fetch.calls.length, 1);
  assert.equal(fetch.calls[0].url, `https://example.test/feedback/api/annotations/${firstId}`);
  assert.equal(fetch.calls[0].options.headers["X-CSRF-Token"], "same-origin-token");
  assert.equal(fetch.calls[0].options.credentials, "same-origin");
});

test("auth, redirects, and successful HTML stop flushing and expose unavailable state", async (t) => {
  for (const response of [
    { body: { error: "sign in" }, options: { status: 401 } },
    { body: "<html>login</html>", options: { status: 302, headers: { "Content-Type": "text/html" }, rawBody: true } },
    { body: "<html>login</html>", options: { status: 200, headers: { "Content-Type": "text/html" }, rawBody: true } }
  ]) {
    const annotation = localAnnotation();
    const fetch = createFakeFetch();
    fetch.respondWith(response.body, response.options);
    const harness = flushHarness({ annotations: [annotation], outbox: { [firstId]: upsertEntry(annotation) }, fetch });
    await harness.toolbar._flushOutbox();
    assert.ok(harness.toolbar.outbox[firstId]);
    assert.match(harness.toolbar._syncUnavailable, /auth|required|unavailable/i);
    harness.reset();
  }
});

test("terminal client errors mark upserts and tombstones failed for manual retry", async (t) => {
  for (const status of [400, 404, 405, 409, 410, 415, 422]) {
    const annotation = localAnnotation();
    const fetch = createFakeFetch();
    fetch.respondWith({ error: "terminal" }, { status });
    const harness = flushHarness({ annotations: [annotation], outbox: { [firstId]: upsertEntry(annotation) }, fetch });
    await harness.toolbar._flushOutbox();
    assert.equal(harness.toolbar.outbox[firstId].syncState, "failed", `status ${status}`);
    assert.equal(harness.toolbar.annotations[0].syncState, "failed", `status ${status}`);
    harness.reset();
  }
});

test("retryable responses and network errors retain pending entries and share one capped retry timer", async (t) => {
  for (const result of [408, 425, 429, 500, new Error("offline")]) {
    const annotation = localAnnotation();
    const fetch = createFakeFetch();
    if (result instanceof Error) fetch.rejectWith(result);
    else fetch.respondWith({ error: "later" }, { status: result, headers: result === 429 ? { "Content-Type": "application/json", "Retry-After": "9999" } : undefined });
    const harness = flushHarness({ annotations: [annotation], outbox: { [firstId]: upsertEntry(annotation) }, fetch });
    await harness.toolbar._flushOutbox();
    assert.equal(harness.toolbar.outbox[firstId].syncState, "pending");
    assert.equal(
      harness.toolbar._syncRetryDelay,
      result === 429 ? harness.toolbar._syncMaxRetryDelay : harness.toolbar._syncBaseRetryDelay,
      `result ${result}`
    );
    assert.equal(harness.toolbar._syncRetryTimer == null, false);
    const scheduledDelay = harness.toolbar._syncRetryDelay;
    harness.toolbar._scheduleSyncRetry(1);
    assert.equal(harness.toolbar._syncRetryDelay, scheduledDelay);
    harness.reset();
  }
});

test("exponential backoff is bounded and resets after a later success", async (t) => {
  const annotation = localAnnotation();
  const fetch = createFakeFetch();
  fetch.respondWith({ error: "later" }, { status: 500 });
  fetch.respondWith(serverRepresentation(annotation));
  const harness = flushHarness({ annotations: [annotation], outbox: { [firstId]: upsertEntry(annotation) }, fetch });
  t.after(() => harness.reset());

  await harness.toolbar._flushOutbox();
  assert.equal(harness.toolbar._syncRetryAttempt, 1);
  harness.toolbar.serverOnline = true;
  await harness.toolbar._flushOutbox();
  assert.equal(fetch.calls.length, 1, "backoff prevents an immediate retry");
  harness.window.clearTimeout(harness.toolbar._syncRetryTimer);
  harness.toolbar._syncRetryTimer = null;
  harness.toolbar.serverOnline = true;
  await harness.toolbar._flushOutbox();
  assert.equal(harness.toolbar._syncRetryAttempt, 0);
  assert.equal(harness.toolbar._syncRetryTimer, null);
});

test("malformed successful JSON retries a bounded number of times before failing", async (t) => {
  const annotation = localAnnotation();
  const fetch = createFakeFetch();
  for (let attempt = 0; attempt < 3; attempt += 1) {
    fetch.respondWith("not-json", { status: 200, rawBody: true, headers: { "Content-Type": "application/json" } });
  }
  const harness = flushHarness({ annotations: [annotation], outbox: { [firstId]: upsertEntry(annotation) }, fetch });
  t.after(() => harness.reset());

  await harness.toolbar._flushOutbox();
  assert.equal(harness.toolbar.outbox[firstId].syncState, "pending");
  harness.window.clearTimeout(harness.toolbar._syncRetryTimer);
  harness.toolbar._syncRetryTimer = null;
  harness.toolbar.serverOnline = true;
  await harness.toolbar._flushOutbox();
  assert.equal(harness.toolbar.outbox[firstId].syncState, "pending");
  harness.window.clearTimeout(harness.toolbar._syncRetryTimer);
  harness.toolbar._syncRetryTimer = null;
  harness.toolbar.serverOnline = true;
  await harness.toolbar._flushOutbox();
  assert.equal(harness.toolbar.outbox[firstId].syncState, "failed");
  assert.equal(harness.toolbar.annotations[0].syncState, "failed");
});

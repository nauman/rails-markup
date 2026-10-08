import assert from "node:assert/strict";
import test from "node:test";

import { createFakeFetch } from "./support/fake_fetch.mjs";
import { createToolbarHarness } from "./support/toolbar_harness.mjs";

const uuidA = "11111111-1111-4111-8111-111111111111";
const uuidB = "22222222-2222-4222-8222-222222222222";

test("client identities remain UUIDs without crypto.randomUUID", (t) => {
  const harness = createToolbarHarness({ randomUUID: false });
  t.after(() => harness.reset());

  assert.match(harness.toolbar._newClientId(), /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

test("page identity and server page_url include pathname and search", async (t) => {
  const fetch = createFakeFetch();
  fetch.respondWith({});
  const harness = createToolbarHarness({ url: "https://example.test/products?status=open", fetch });
  t.after(() => harness.reset());

  assert.equal(harness.toolbar._pageStorageKey(), "rm-annotations:%2Ffeedback%2Fapi:/products?status=open");
  harness.toolbar.serverOnline = true;
  await harness.toolbar._pushToServer({
    id: 1,
    clientId: uuidA,
    comment: "Fix this",
    intent: "fix",
    severity: "important",
    pathname: "/products?status=open",
    url: "https://example.test/products?status=open"
  });

  assert.equal(JSON.parse(fetch.calls[0].options.body).page_url, "/products?status=open");

  const other = createToolbarHarness({ url: "https://example.test/products?status=closed" });
  t.after(() => other.reset());
  assert.notEqual(harness.toolbar._pageStorageKey(), other.toolbar._pageStorageKey());
});

test("namespaced storage remains isolated by endpoint", (t) => {
  const alphaKey = "rm-annotations:%2Falpha%2Fapi";
  const betaKey = "rm-annotations:%2Fbeta%2Fapi";
  const storage = {
    [alphaKey]: { annotations: [{ id: 2, clientId: uuidA, serverId: 10, comment: "Alpha" }], nextId: 3, outbox: {} },
    [betaKey]: { annotations: [{ id: 3, clientId: uuidB, serverId: 11, comment: "Beta" }], nextId: 4, outbox: {} }
  };
  const alpha = createToolbarHarness({ endpoint: "/alpha/api", storage });
  const beta = createToolbarHarness({ endpoint: "/beta/api", storage });
  t.after(() => {
    alpha.reset();
    beta.reset();
  });

  assert.equal(alpha.toolbar._storageKey(), alphaKey);
  assert.equal(beta.toolbar._storageKey(), betaKey);
  assert.notEqual(alpha.toolbar._storageKey(), beta.toolbar._storageKey());

  alpha.toolbar._loadFromStorage();
  beta.toolbar._loadFromStorage();

  assert.deepEqual(Array.from(alpha.toolbar.annotations, annotation => annotation.comment), ["Alpha"]);
  assert.deepEqual(Array.from(beta.toolbar.annotations, annotation => annotation.comment), ["Beta"]);
});

test("stored toolbar settings override init-time defaults", (t) => {
  const settingsKey = "rm-toolbar-settings:%2Ffeedback%2Fapi";
  const harness = createToolbarHarness({
    storage: {
      [settingsKey]: {
        accent: "rose",
        position: "tr",
        size: "compact",
        fabVisible: false,
        enableScreenshots: false
      }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar.init({
    endpoint: "/feedback/api",
    accent: "indigo",
    position: "bl",
    size: "default",
    fabVisible: true,
    enableScreenshots: true
  });

  assert.equal(harness.toolbar.accent, "rose");
  assert.equal(harness.toolbar.position, "tr");
  assert.equal(harness.toolbar.size, "compact");
  assert.equal(harness.toolbar.fabVisible, false);
  assert.equal(harness.toolbar.enableScreenshots, false);
  assert.equal(harness.window.document.getElementById("rm-fab").style.display, "none");
  assert.equal(harness.window.document.getElementById("rm-dock").style.right, "24px");
  assert.equal(harness.window.document.getElementById("rm-dock").style.top, "24px");
});

test("toolbar starts compact with settings inside the collapsed dock", (t) => {
  const harness = createToolbarHarness();
  t.after(() => harness.reset());

  harness.toolbar.init({
    endpoint: "/feedback/api",
    accent: "indigo",
    position: "bl",
    size: "default",
    fabVisible: true,
    enableScreenshots: true
  });

  const settingsToggle = harness.window.document.getElementById("rm-settings-toggle");
  assert.ok(settingsToggle);
  assert.equal(settingsToggle.getAttribute("aria-controls"), "rm-settings-panel");
  assert.equal(harness.window.document.getElementById("rm-fab").style.width, "40px");
  assert.equal(harness.window.document.getElementById("rm-fab").style.height, "40px");
  assert.equal(harness.window.document.getElementById("rm-dock-controls").hidden, true);
  assert.equal(harness.window.document.getElementById("rm-dock").style.bottom, "24px");
});

test("toolbar setting changes persist and reinitialize the runtime config", (t) => {
  const settingsKey = "rm-toolbar-settings:%2Ffeedback%2Fapi";
  const harness = createToolbarHarness();
  t.after(() => harness.reset());

  harness.toolbar.init({
    endpoint: "/feedback/api",
    accent: "indigo",
    position: "bl",
    size: "default",
    fabVisible: true,
    enableScreenshots: true
  });

  harness.toolbar._setToolbarSetting("accent", "emerald");
  harness.toolbar._setToolbarSetting("fabVisible", false);

  const stored = JSON.parse(harness.window.localStorage.getItem(settingsKey));
  assert.equal(stored.accent, "emerald");
  assert.equal(stored.fabVisible, false);
  assert.equal(harness.toolbar.accent, "emerald");
  assert.equal(harness.toolbar.fabVisible, false);
  assert.equal(harness.window.document.getElementById("rm-fab").style.display, "none");
});

test("legacy records gain sync fields and only unmapped records enter the outbox", (t) => {
  const harness = createToolbarHarness({
    uuids: [uuidA, uuidB],
    storage: {
      "rm-annotations:%2Ffeedback%2Fapi": {
        annotations: [
          { id: 1, comment: "Local only", pathname: "/products", status: "pending" },
          { id: 2, serverId: 42, comment: "Already mapped", pathname: "/products", status: "resolved" }
        ],
        nextId: 3
      }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  const [unmapped, mapped] = harness.toolbar.annotations;
  assert.equal(unmapped.clientId, uuidA);
  assert.equal(unmapped.serverId, null);
  assert.equal(unmapped.syncState, "pending");
  assert.equal(unmapped.serverUpdatedAt, null);
  assert.ok(Array.isArray(unmapped.dirtyFields));
  assert.equal(mapped.clientId, uuidB);
  assert.equal(mapped.serverId, 42);
  assert.equal(mapped.syncState, "synced");
  assert.deepEqual(Object.keys(harness.toolbar.outbox), [uuidA]);
  assert.equal(harness.toolbar.outbox[uuidA].type, "upsert");
  assert.equal(harness.toolbar.outbox[uuidA].annotation.clientId, uuidA);
  assert.equal(harness.toolbar.outbox[uuidA].annotation.status, "pending");
  assert.equal(harness.toolbar.outbox[uuidA].annotation.content, "Local only");
});

test("an existing mapping or outbox is not requeued or overwritten", (t) => {
  const existingEntry = { type: "upsert", annotation: { clientId: uuidA, comment: "Newest intent" }, dirtyFields: ["content"] };
  const harness = createToolbarHarness({
    storage: {
      "rm-annotations:%2Ffeedback%2Fapi": {
        annotations: [
          { id: 1, clientId: uuidA, comment: "Older local", pathname: "/", syncState: "pending" },
          { id: 2, clientId: uuidB, serverId: 9, comment: "Mapped", pathname: "/" }
        ],
        nextId: 3,
        outbox: { [uuidA]: existingEntry }
      }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.deepEqual(JSON.parse(JSON.stringify(harness.toolbar.outbox)), {
    [uuidA]: {
      ...existingEntry,
      clientId: uuidA,
      revision: 0,
      baseRevision: 0,
      syncState: "pending"
    }
  });
});

test("invalid legacy client IDs are replaced and their outbox entries rekeyed", (t) => {
  const invalidClientId = "rm-legacy-client";
  const harness = createToolbarHarness({
    uuids: [uuidA],
    storage: {
      "rm-annotations:%2Ffeedback%2Fapi": {
        annotations: [{ id: 1, clientId: invalidClientId, comment: "Legacy", pathname: "/" }],
        nextId: 2,
        outbox: {
          [invalidClientId]: {
            type: "upsert",
            annotation: { clientId: invalidClientId, comment: "Legacy" },
            dirtyFields: ["content"]
          }
        }
      }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.equal(harness.toolbar.annotations[0].clientId, uuidA);
  assert.equal(harness.toolbar.outbox[invalidClientId], undefined);
  assert.equal(harness.toolbar.outbox[uuidA].annotation.clientId, uuidA);
});

test("distinct records sharing an invalid client ID remain distinct queued upserts", (t) => {
  const invalidClientId = "rm-shared-legacy-id";
  const harness = createToolbarHarness({
    uuids: [uuidA, uuidB],
    storage: {
      "rm-annotations:%2Ffeedback%2Fapi": {
        annotations: [
          { id: 1, clientId: invalidClientId, comment: "First record", pathname: "/" },
          { id: 2, clientId: invalidClientId, comment: "Second record", pathname: "/" }
        ],
        nextId: 3,
        outbox: {
          [invalidClientId]: {
            type: "upsert",
            annotation: { clientId: invalidClientId, comment: "Second record" },
            dirtyFields: ["content"]
          }
        }
      }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.deepEqual(Array.from(harness.toolbar.annotations, annotation => annotation.comment), ["First record", "Second record"]);
  assert.deepEqual(Array.from(harness.toolbar.annotations, annotation => annotation.clientId), [uuidA, uuidB]);
  assert.deepEqual(Object.keys(harness.toolbar.outbox).sort(), [uuidA, uuidB]);
  assert.equal(harness.toolbar.outbox[uuidA].type, "upsert");
  assert.equal(harness.toolbar.outbox[uuidB].type, "upsert");
  assert.equal(harness.toolbar.outbox[uuidA].annotation.content, "First record");
  assert.equal(harness.toolbar.outbox[uuidB].annotation.comment, "Second record");
  assert.deepEqual(
    Object.values(harness.toolbar.outbox).map(entry => entry.annotation.content ?? entry.annotation.comment).sort(),
    ["First record", "Second record"]
  );
});

test("legacy per-page migration preserves records with colliding local IDs", (t) => {
  const harness = createToolbarHarness({
    uuids: [uuidA, uuidB, "33333333-3333-4333-8333-333333333333"],
    storage: {
      "rm-annotations:%2Ffeedback%2Fapi": { annotations: [{ id: 1, comment: "Global", pathname: "/one" }], nextId: 1 },
      "rm-annotations:%2Ffeedback%2Fapi:/one": { annotations: [{ id: 1, comment: "Page one", pathname: "/one" }], nextId: 2 },
      "rm-annotations:%2Ffeedback%2Fapi:/two": { annotations: [{ id: 1, comment: "Page two", pathname: "/two" }], nextId: 2 }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.deepEqual(Array.from(harness.toolbar.annotations, (annotation) => annotation.comment).sort(), ["Global", "Page one", "Page two"]);
  assert.equal(new Set(harness.toolbar.annotations.map((annotation) => annotation.id)).size, 3);
  assert.equal(Object.keys(harness.toolbar.outbox).length, 3);
  assert.equal(harness.window.localStorage.getItem("rm-annotations:%2Ffeedback%2Fapi:/one"), null);
  assert.equal(harness.window.localStorage.getItem("rm-annotations:%2Ffeedback%2Fapi:/two"), null);
});

test("pre-1.3 bare annotations and outbox migrate into the current endpoint namespace once", (t) => {
  const legacyOutbox = {
    type: "upsert",
    annotation: {
      clientId: uuidA,
      page_url: "/legacy",
      content: "Pending offline edit",
      intent: "change",
      severity: "important",
      target: { selector: "main" }
    },
    dirtyFields: ["content", "severity"]
  };
  const harness = createToolbarHarness({
    url: "https://example.test/page",
    legacyStorageEndpoint: "/feedback/api",
    uuids: [uuidB],
    storage: {
      "rm-annotations": {
        annotations: [{
          id: 1,
          clientId: uuidA,
          comment: "Pending offline edit",
          pathname: "/legacy",
          intent: "change",
          severity: "important"
        }],
        nextId: 2,
        outbox: { [uuidA]: legacyOutbox }
      },
      "rm-annotations:/page": {
        annotations: [{ id: 1, comment: "Old page annotation", pathname: "/page" }],
        nextId: 2
      }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.deepEqual(
    Array.from(harness.toolbar.annotations, annotation => annotation.comment).sort(),
    ["Old page annotation", "Pending offline edit"]
  );
  assert.equal(harness.toolbar.outbox[uuidA].clientId, uuidA);
  assert.equal(harness.toolbar.outbox[uuidA].revision, 0);
  assert.equal(harness.toolbar.outbox[uuidA].syncState, "pending");
  assert.deepEqual(Array.from(harness.toolbar.outbox[uuidA].dirtyFields), ["content", "severity"]);
  assert.ok(harness.toolbar.outbox[uuidB]);
  assert.equal(harness.window.localStorage.getItem("rm-annotations"), null);
  assert.equal(harness.window.localStorage.getItem("rm-annotations:/page"), null);
  assert.equal(harness.storageDocument().annotations.length, 2);

  harness.toolbar._loadFromStorage();
  assert.equal(harness.toolbar.annotations.length, 2);
});

test("legacy migration leaves ambiguous bare data and other pages available to another endpoint", (t) => {
  const harness = createToolbarHarness({
    url: "https://example.test/alpha",
    endpoint: "/alpha/api",
    uuids: [uuidA],
    storage: {
      "rm-annotations": {
        annotations: [{ id: 1, comment: "Ambiguous", pathname: "/alpha" }],
        outbox: { legacy: { type: "upsert" } }
      },
      "rm-annotations:/alpha": {
        annotations: [{ id: 2, comment: "Alpha page", pathname: "/alpha" }]
      },
      "rm-annotations:/beta": {
        annotations: [{ id: 3, comment: "Beta page", pathname: "/beta" }]
      }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.deepEqual(Array.from(harness.toolbar.annotations, annotation => annotation.comment), ["Alpha page"]);
  assert.notEqual(harness.window.localStorage.getItem("rm-annotations"), null);
  assert.equal(harness.window.localStorage.getItem("rm-annotations:/alpha"), null);
  assert.notEqual(harness.window.localStorage.getItem("rm-annotations:/beta"), null);
});

test("legacy migration preserves malformed and unrecognized prefixed keys", (t) => {
  const harness = createToolbarHarness({
    uuids: [uuidA],
    storage: {
      "rm-annotations:%2Ffeedback%2Fapi:recognized": { annotations: [{ id: 1, comment: "Migrated", pathname: "/recognized" }] },
      "rm-annotations:%2Ffeedback%2Fapi:malformed": "{not-json",
      "rm-annotations:%2Ffeedback%2Fapi:unrecognized": { annotations: "not-an-array" }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.equal(harness.window.localStorage.getItem("rm-annotations:%2Ffeedback%2Fapi:recognized"), null);
  assert.equal(harness.window.localStorage.getItem("rm-annotations:%2Ffeedback%2Fapi:malformed"), "{not-json");
  assert.notEqual(harness.window.localStorage.getItem("rm-annotations:%2Ffeedback%2Fapi:unrecognized"), null);
});

test("legacy migration retains source keys when consolidated persistence fails", (t) => {
  const harness = createToolbarHarness({
    uuids: [uuidA],
    storage: {
      "rm-annotations:%2Ffeedback%2Fapi": { annotations: [], nextId: 1, outbox: {} },
      "rm-annotations:%2Ffeedback%2Fapi:/legacy": { annotations: [{ id: 1, comment: "Keep me", pathname: "/legacy" }] }
    }
  });
  t.after(() => harness.reset());
  harness.failNextStorageWrite(new Error("quota exceeded"));

  harness.toolbar._loadFromStorage();

  assert.notEqual(harness.window.localStorage.getItem("rm-annotations:%2Ffeedback%2Fapi:/legacy"), null);
  assert.equal(harness.storageDocument().annotations.length, 0);
});

test("legacy cleanup retries idempotently when one source key cannot be removed", (t) => {
  const harness = createToolbarHarness({
    uuids: [uuidA, uuidB],
    storage: {
      "rm-annotations:%2Ffeedback%2Fapi": { annotations: [], nextId: 1, outbox: {} },
      "rm-annotations:%2Ffeedback%2Fapi:/one": { annotations: [{ id: 1, comment: "One", pathname: "/one" }] },
      "rm-annotations:%2Ffeedback%2Fapi:/two": { annotations: [{ id: 1, comment: "Two", pathname: "/two" }] }
    }
  });
  t.after(() => harness.reset());
  harness.failNextStorageRemoval("rm-annotations:%2Ffeedback%2Fapi:/one", new Error("remove denied"));

  harness.toolbar._loadFromStorage();

  assert.notEqual(harness.window.localStorage.getItem("rm-annotations:%2Ffeedback%2Fapi:/one"), null);
  assert.equal(harness.window.localStorage.getItem("rm-annotations:%2Ffeedback%2Fapi:/two"), null);
  assert.equal(harness.toolbar.annotations.length, 2);

  harness.toolbar._loadFromStorage();
  harness.toolbar._loadFromStorage();

  assert.equal(harness.window.localStorage.getItem("rm-annotations:%2Ffeedback%2Fapi:/one"), null);
  assert.deepEqual(Array.from(harness.toolbar.annotations, annotation => annotation.comment).sort(), ["One", "Two"]);
  assert.deepEqual(Object.keys(harness.toolbar.outbox).sort(), [uuidA, uuidB]);
});

test("retained legacy source cannot overwrite consolidated edits on cleanup retry", (t) => {
  const harness = createToolbarHarness({
    uuids: [uuidA],
    storage: {
      "rm-annotations:%2Ffeedback%2Fapi": { annotations: [], nextId: 1, outbox: {} },
      "rm-annotations:%2Ffeedback%2Fapi:/legacy": { annotations: [{ id: 1, comment: "Stale source", pathname: "/legacy" }] }
    }
  });
  t.after(() => harness.reset());
  harness.failNextStorageRemoval("rm-annotations:%2Ffeedback%2Fapi:/legacy", new Error("remove denied"));
  harness.toolbar._loadFromStorage();

  harness.toolbar.annotations[0].comment = "Edited desired state";
  harness.toolbar.outbox[uuidA].annotation.content = "Edited desired state";
  harness.toolbar._saveToStorage();
  harness.toolbar._loadFromStorage();

  assert.equal(harness.window.localStorage.getItem("rm-annotations:%2Ffeedback%2Fapi:/legacy"), null);
  assert.equal(harness.toolbar.annotations.length, 1);
  assert.equal(harness.toolbar.annotations[0].comment, "Edited desired state");
  assert.equal(harness.toolbar.outbox[uuidA].annotation.content, "Edited desired state");
});

test("duplicate client IDs collapse to the deterministically newest local record", (t) => {
  const harness = createToolbarHarness({
    storage: {
      "rm-annotations:%2Ffeedback%2Fapi": {
        annotations: [
          { id: 7, clientId: uuidA, comment: "old", updatedAt: "2026-01-01T00:00:00Z" },
          { id: 8, clientId: uuidA, comment: "new-first", updatedAt: "2026-02-01T00:00:00Z", serverUpdatedAt: "2026-02-02T00:00:00Z" },
          { id: 9, clientId: uuidA, comment: "new-stable-winner", updatedAt: "2026-02-01T00:00:00Z", serverUpdatedAt: "2026-02-02T00:00:00Z" },
          { id: 9, clientId: uuidB, comment: "unrelated" }
        ],
        nextId: 2,
        outbox: {}
      }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.equal(harness.toolbar.annotations.length, 2);
  assert.equal(harness.toolbar.annotations.find((annotation) => annotation.clientId === uuidA).comment, "new-stable-winner");
  assert.equal(harness.toolbar.annotations.find((annotation) => annotation.clientId === uuidB).comment, "unrelated");
  assert.equal(new Set(harness.toolbar.annotations.map((annotation) => annotation.id)).size, 2);
});

test("equal local update times use later array order instead of server time", (t) => {
  const harness = createToolbarHarness({
    storage: {
      "rm-annotations:%2Ffeedback%2Fapi": {
        annotations: [
          { id: 1, clientId: uuidA, comment: "earlier array", updatedAt: "2026-03-01T00:00:00Z", serverUpdatedAt: "2026-04-01T00:00:00Z" },
          { id: 2, clientId: uuidA, comment: "later array", updatedAt: "2026-03-01T00:00:00Z", serverUpdatedAt: "2026-02-01T00:00:00Z" }
        ],
        nextId: 3,
        outbox: {}
      }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.equal(harness.toolbar.annotations.length, 1);
  assert.equal(harness.toolbar.annotations[0].comment, "later array");
});

test("malformed persisted annotation collections reset to safe empty state", () => {
  for (const malformedAnnotations of ["not-an-array", { unexpected: true }]) {
    const harness = createToolbarHarness({
      storage: {
        "rm-annotations:%2Ffeedback%2Fapi": { annotations: malformedAnnotations, nextId: 99, outbox: ["unsafe"] }
      }
    });

    harness.toolbar._injectDOM();
    harness.toolbar._loadFromStorage();

    assert.deepEqual(Array.from(harness.toolbar.annotations), []);
    assert.equal(Array.isArray(harness.toolbar.outbox), false);
    assert.deepEqual(Object.keys(harness.toolbar.outbox), []);
    assert.doesNotThrow(() => harness.toolbar._renderPins());
    harness.reset();
  }
});

test("server-only records receive stable collision-free display IDs across reload", (t) => {
  const first = createToolbarHarness({
    storage: {
      "rm-annotations:%2Ffeedback%2Fapi": {
        annotations: [
          { id: 5, clientId: uuidA, serverId: 10, comment: "Existing" },
          { clientId: uuidB, serverId: 11, comment: "Imported" }
        ],
        nextId: 2,
        outbox: {}
      }
    }
  });
  t.after(() => first.reset());
  first.toolbar._loadFromStorage();

  const firstIds = Array.from(first.toolbar.annotations, (annotation) => annotation.id);
  const persisted = first.storageDocument();
  assert.deepEqual(firstIds, [5, 6]);
  assert.equal(first.toolbar.nextId, 7);

  const reloaded = createToolbarHarness({ storage: { "rm-annotations:%2Ffeedback%2Fapi": persisted } });
  t.after(() => reloaded.reset());
  reloaded.toolbar._loadFromStorage();
  assert.deepEqual(Array.from(reloaded.toolbar.annotations, (annotation) => annotation.id), firstIds);
  assert.equal(reloaded.toolbar.nextId, 7);
});

test("new UI annotations have the complete sync schema before storage", (t) => {
  const harness = createToolbarHarness({ uuids: [uuidA] });
  t.after(() => harness.reset());
  harness.toolbar._injectStyles();
  harness.toolbar._injectDOM();
  harness.window.document.getElementById("rm-popup-input").value = "Created locally";
  harness.toolbar._currentElement = { selector: "main" };

  harness.toolbar.submitAnnotation();

  const annotation = harness.toolbar.annotations[0];
  assert.equal(annotation.clientId, uuidA);
  assert.equal(annotation.serverId, null);
  assert.equal(annotation.syncState, "pending");
  assert.equal(annotation.serverUpdatedAt, null);
  assert.deepEqual(Array.from(annotation.dirtyFields), ["content", "intent", "severity", "selected_text", "target", "page_url", "metadata"]);
  assert.equal(harness.storageDocument().annotations[0].syncState, "pending");
  assert.equal(harness.storageDocument().outbox[uuidA].type, "upsert");
});

test("harness reset destroys toolbar intervals and global state", (t) => {
  const fetch = createFakeFetch();
  fetch.rejectWith(new Error("offline"));
  const harness = createToolbarHarness({ fetch });
  t.after(() => harness.reset());

  harness.toolbar.init();
  assert.equal(harness.pendingIntervalCount(), 1);
  harness.reset();
  assert.equal(harness.pendingIntervalCount(), 0);
  assert.equal(harness.window.RailsMarkupToolbar, undefined);
});

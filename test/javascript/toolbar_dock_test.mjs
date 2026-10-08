import assert from "node:assert/strict";
import test from "node:test";
import { createToolbarHarness } from "./support/toolbar_harness.mjs";

function setup(t, options = {}) {
  const harness = createToolbarHarness();
  t.after(() => harness.reset());
  harness.toolbar.init({ enableScreenshots: false, ...options });
  return { ...harness, el: id => harness.window.document.getElementById(id) };
}

test("first click expands without intercepting the host; second click annotates; exit steps back", t => {
  const { toolbar, el, window } = setup(t);
  const fab = el("rm-fab");
  assert.equal(el("rm-dock-controls").hidden, true);
  fab.click();
  assert.equal(toolbar.active, false);
  assert.equal(toolbar.dockState, "expanded");
  assert.equal(el("rm-dock-controls").hidden, false);
  assert.equal(window.document.body.style.cursor, "");
  const host = window.document.createElement("button");
  window.document.body.append(host);
  let clicks = 0;
  host.addEventListener("click", () => clicks++);
  host.click();
  assert.equal(clicks, 1);
  fab.click();
  assert.equal(toolbar.active, true);
  assert.equal(fab.getAttribute("aria-pressed"), "true");
  host.click();
  assert.equal(clicks, 1);
  el("rm-dock-close").click();
  assert.equal(toolbar.active, false);
  assert.equal(toolbar.dockState, "expanded");
  host.click();
  assert.equal(clicks, 2);
  el("rm-dock-close").click();
  assert.equal(toolbar.dockState, "collapsed");
  assert.equal(window.document.activeElement, fab);
});

test("Escape exits selection then collapses the dock", t => {
  const { toolbar, el, window } = setup(t);
  el("rm-fab").click();
  el("rm-fab").click();
  window.document.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
  assert.equal(toolbar.dockState, "expanded");
  assert.equal(toolbar.active, false);
  window.document.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
  assert.equal(toolbar.dockState, "collapsed");
});

test("settings opens its containing panel, and collapse closes all dock surfaces", t => {
  const { toolbar, el } = setup(t);
  el("rm-fab").click();
  el("rm-settings-toggle").click();
  assert.equal(el("rm-panel").style.display, "flex");
  assert.equal(el("rm-settings-panel").hidden, false);
  assert.equal(el("rm-panel-toggle").getAttribute("aria-expanded"), "false");
  assert.equal(el("rm-panel").dataset.view, "settings");
  el("rm-panel-toggle").click();
  assert.equal(el("rm-settings-panel").hidden, true);
  assert.equal(el("rm-panel").dataset.view, "feedback");
  el("rm-dock-close").click();
  assert.equal(el("rm-panel").style.display, "none");
  assert.equal(el("rm-settings-panel").hidden, true);
  assert.equal(el("rm-panel-toggle").getAttribute("aria-expanded"), "false");
  toolbar.annotations = [{ id: 1 }];
  toolbar._updateCount();
  assert.equal(el("rm-dock-controls").hidden, true);
  assert.equal(el("rm-panel-toggle-badge").textContent, "1");
});

test("hidden FAB hides the entire floating dock", t => {
  const { el } = setup(t, { fabVisible: false });
  assert.equal(el("rm-fab").style.display, "none");
  assert.equal(el("rm-dock").style.display, "none");
});

test("navigation exits selection and reinitialization restores a compact launcher", t => {
  const { toolbar, el, window } = setup(t);
  el("rm-fab").click();
  el("rm-fab").click();
  window.history.pushState({}, "", "/next");
  toolbar._onTurboNavigate();
  assert.equal(toolbar.active, false);
  assert.equal(toolbar.dockState, "expanded");
  toolbar.destroy();
  toolbar.init();
  assert.equal(toolbar.dockState, "collapsed");
  el("rm-fab").click();
  assert.equal(toolbar.active, false);
});

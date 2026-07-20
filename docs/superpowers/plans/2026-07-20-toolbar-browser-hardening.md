# Rails Markup Toolbar Browser Hardening Follow-up Plan

> **For agentic workers:** This plan is intentionally separate from the 1.2 security/sync contract and must receive its own design review after Claude's browser-harness baseline is committed.

**Goal:** Verify and fix Turbo cache restoration, host style isolation, and mobile interaction gaps in the real dummy-app browser harness.

**Scope:** `turbo:before-cache` teardown/reinitialization, listener/timer uniqueness, Shadow DOM or root-scoped CSS isolation, safe-area-aware FAB bounds/touch targets, mobile popup scrolling, and pointer-event screenshot drawing. Preserve the public FAB visibility/size/position configuration contract.

**Ownership gate:** Do not edit `toolbar.js` or Claude's harness for this follow-up until the security/sync toolbar commit is complete and the harness baseline is committed and reviewed.

# Kuickr demonstration

The original sample app is `test/dummy`, a Rails test host inside this repository. Neither that app nor these examples are included in the published gem.

Run `bundle exec ruby script/demo`, sign in at <http://127.0.0.1:4317/rails_markup_test_session/new>, then open <http://127.0.0.1:4317/demo>.

`control-surface.html` is a local copy of [EXP·002 — Control Surface](https://kuickr.co/nauman/experiments/exp-002-control-surface.html), by Nauman / Kuickr / Pavelabs. The demo controller adds CSRF metadata and the real Rails Markup toolbar. The hosted Kuickr page is untouched. Test routes `/host` and `/other` remain available. Demo feedback persists separately under `tmp/demo`.

## Video preview

```sh
cd examples/demo-video
npm ci
npm run dev -- --no-open
```

Choose `RailsMarkupDemo` in Remotion Studio. It is a 38-second, 1920×1080 captioned walkthrough made from actual browser screenshots: the page, element feedback, optional image upload, shared-modal review, acknowledgement, and the compact board with optional help. Individual scenes are editable compositions. It has no recorded voice or continuous screen recording. The image step demonstrates upload, not the native screen-sharing permission picker.

The captures contain only local demo content. Re-capture them after changing the UI before reusing the walkthrough. No video has been published.

# Rails Markup walkthrough

See [the demo guide](../README.md) for the source page, local Rails host, and capture provenance.

Run `npm ci` and `npm run dev -- --no-open`, then select `RailsMarkupDemo`. The seven scenes are also available separately under Scenes.

Validation: `npm run lint` checks ESLint and TypeScript.

## Screenshot drawing clip

`RailsMarkupDrawing` is an 18-second, 900 × 900 captioned sequence of real app screenshots, rather than a continuous screen recording. The images in `public/drawing/` show a screenshot uploaded to the live toolbar, marked with Rect, Arrow and Highlight, then saved and opened in the dashboard. The demo comment asks to increase the contrast of the boxed label. `markup.png` is the actual persisted attachment at its original 720 × 340 resolution.

Render with `npx remotion render RailsMarkupDrawing out/rails-markup-image-markup.mp4 --codec=h264`. Create the poster with `npx remotion still RailsMarkupDrawing public/drawing/poster.png --frame=330`. The homepage uses copies in `docs/assets/` and features the original attachment in `docs/assets/screenshots/image-markup.png`.

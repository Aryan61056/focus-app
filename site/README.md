# Focus website

Static page, no build step: `index.html`, `styles.css`, `main.js`, `halftone.js`.

```bash
cd site && python3 -m http.server 4173   # then open http://127.0.0.1:4173
```
Serve it over HTTP: the halftone art reads image pixels from a canvas, which browsers block for `file://` pages.

## Images
The repo ignores image files (privacy rule in `.gitignore`) except under `site/assets/`. To recreate them:

- `assets/app/icon.png`: `sips -s format png -Z 512 mac/.build/Focus.app/Contents/Resources/AppIcon.icns --out site/assets/app/icon.png` after `./tools/build_app.sh`.
- `assets/app/today.jpg`, `assets/app/projects.jpg`: the demo window (`FOCUS_DEMO=1`, optionally `FOCUS_DEMO_ACTIONS=section:projects`), captured with `screencapture -o -l <window id>`. Demo data only, never a real screen.
- `assets/art/*.jpg`, about 1100 px tall, from Wikimedia Commons:
  - `thinker.jpg`: File:The Thinker, Rodin.jpg (public domain)
  - `jerome.jpg`: File:Albrecht Dürer, Saint Jerome in His Study, 1514, NGA 6642.jpg (CC0)
  - `wanderer.jpg`: File:Caspar David Friedrich - Wanderer above the sea of fog.jpg (public domain)

Credits for the art are in the page footer.

## Open items (owner)
- The download buttons point at `#download`. Distribution is not decided yet.
- The iPhone companion is described as "in testing".

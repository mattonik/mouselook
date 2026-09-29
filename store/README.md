# App Store screenshots and previews

`shots.json` lists the screenshots in listing order, each with its caption and
the raw screen it frames. Raw screens and renders stay out of git: they can
show accounts and files, and the public repository shouldn't carry them.

1. **Raw screens** go in `store/raw/`, landscape:
   - From the 13-inch iPad simulator, at exactly 2752 x 2064:
     `tools/app-store/capture.sh` (welcome, get-ready, settings, menu). The
     simulator must be in Full Screen Apps mode (Settings ▸ Multitasking &
     Gestures), or a resize handle shows in the corner.
   - From an iPad Pro 12.9-inch, 2732 x 2048 screenshots work as they are
     (a game, Figma mid-drag).
2. **Screenshots:** `node tools/app-store/render.mjs` puts each raw screen under
   its caption and writes `store/out/<id>.png` (2752 x 2064, no alpha).
3. **Previews:** record on the iPad (Control Center ▸ Screen Recording), then
   `tools/app-store/preview.sh <recording> <start> <end> <name>` writes
   `store/out/preview-<name>.mp4` (1600 x 1200, 30 fps, H.264, stereo AAC,
   15 to 30 s).

Before uploading, check each image for personal data: names, team names, file
names, email addresses.

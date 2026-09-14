# Interactive picker demo

`interactive-picker.svg` is a short, static walkthrough of the shared inline picker. It uses a
throwaway `demo` catalog and a fixture-local `democtl`; no service, hostname, credential, or local
machine path appears in the frame.

The flow shows the review panel, keyboard navigation, native `e` editing, a placeholder prompt, and
native output. It is intentionally an SVG rather than an autoplay recording so it remains legible in
GitHub's README, works without a large download, and has an equivalent text description in the image
alt text.

Verify it before changing picker behavior or the frame:

```bash
bash docs/demo/capture-interactive-picker.sh
```

The verifier builds the real helper, drives it through a controlling PTY, moves to the second row,
enters the normal command editor, fills a placeholder, and confirms the fake child stdout and stderr.
It never contacts an infrastructure service.

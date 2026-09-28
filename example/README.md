# node_flow example

A runnable demo of the [node_flow](https://pub.dev/packages/node_flow) canvas
with four pages:

- **01 · Static camera** — a read-only graph with pan / zoom / fit.
- **02 · Editing** — node dragging, selection, marquee, snap guides.
- **03 · Edges** — animated bezier, branches, dangling badges.
- **04 · Connect** — ports, drag-to-connect, validation, dedupe.

Run it with:

```sh
flutter run
```

## Browser integration tests

The web suites use Flutter's SDK `integration_test` runner and a local
ChromeDriver on port 4444. Install a matching Chrome and ChromeDriver pair,
then start ChromeDriver in another terminal:

```sh
chromedriver --port=4444
```

From `example/`, run the smoke and functional suites:

```sh
flutter pub get
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_smoke_test.dart -d web-server --headless --browser-dimension=1600x1024@1
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/workflow_test.dart -d web-server --headless --browser-dimension=1600x1024@1
```

The lifecycle suite compares cropped Chrome screenshots and is pinned to
Flutter 3.41.2, Chrome/ChromeDriver 154.0.8037.57, and device pixel ratio 1.
Run it with:

```sh
flutter drive --driver=test_driver/lifecycle_driver.dart --target=integration_test/lifecycle_test.dart -d web-server --headless --browser-dimension=1600x1024@1
```

The visual driver saves PNGs in `build/integration_artifacts/`. It checks that
graph changes alter minimap or edge pixels while a static canvas region stays
unchanged; changing the browser size or pixel ratio invalidates its crop
mapping. The CI browser jobs save command logs and upload these artifacts on
failure. The suites exercise desktop Chrome mouse and keyboard input; they do
not establish native touch, trackpad, or IME behavior.

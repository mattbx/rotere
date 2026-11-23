# test

off-device checks for rotere. plain lua 5.3, no norns needed.

```
lua5.3 test/test_rotere.lua     # behaviour tests (keys, physics, midi in/out, octaves, probability, screen)
lua5.3 test/bench.lua           # physics speed + note counts (norns is roughly 10x slower than a laptop)
```

## screen previews

`screens.lua` lists the screen states worth seeing (normal view, K1 held, the
triangle opening, spinning backwards). it drives the real script with keys and
encoders, so every run draws the same pixels on the same platform (lua 5.3's
`math.random` follows the C library, so a native Mac run can put the balls
somewhere other than the Linux docker run does). add a shot there for whatever
you're working on.

**exact**, with Weft's preview tool. this runs from a checkout of **Weft**
(github.com/mattbx/weft, private) rather than this repo, and replays every
`redraw()` through Cairo with the norns font, so shapes and text match the device.
best in Weft's bullseye image, which has the device's Cairo 1.16:

```
docker run --rm -v "$PWD":/weft -v ~/Github/audio-apps/rotere:/scripts/rotere -w /weft \
  weft-bullseye-cairo python3 tools/norns-harness/screens.py /scripts/rotere
```

or straight on the Mac, with lua 5.3 and pycairo installed:

```
python3 tools/norns-harness/screens.py ~/Github/audio-apps/rotere
```

both write `screens/` here (gitignored): a PNG per state and `sheet.png` with all of them.

**quick**, without Weft (needs python + Pillow). same states, close but not exact:
rects are exact, lines are a few pixels off in places and text uses a hand-made
copy of the norns font.

```
mkdir -p screens
lua5.3 test/render_screens.lua > /tmp/frames.txt
python3 test/screen_png.py /tmp/frames.txt screens/quick.png
```

## the bits

- `norns_offline.lua` - stubs the norns globals (screen, params, metro, midi, engine, musicutil, util) so a script runs in plain lua. load it, press keys, turn encoders, `run()` time forward, then look at what the engine was told, what midi went out and what got drawn. not rotere-specific - copy it into any norns script.
- `test_rotere.lua` - the checks. each one was first done by hand while building rotere.
- `screens.lua` - the screen states, for both preview tools.
- `render_screens.lua` + `screen_png.py` - the quick preview: run the scenes, record each `redraw()`, turn them into a png sheet.
- `bench.lua` - physics timing and note-flood numbers.

install lua 5.3: `brew install lua@5.3` (mac) or `apt install lua5.3`.

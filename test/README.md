# test

off-device checks for rotere. plain lua 5.3, no norns needed.

```
lua5.3 test/test_rotere.lua     # behaviour tests (keys, physics, midi in/out, octaves, probability, screen)
lua5.3 test/bench.lua           # physics speed + note counts (norns is roughly 10x slower than a laptop)
```

previews of the screen, drawn from the real code (needs python + Pillow):

```
lua5.3 test/render_screens.lua > /tmp/frames.txt
python3 test/screen_png.py /tmp/frames.txt screens.png
```

## the bits

- `norns_offline.lua` - stubs the norns globals (screen, params, metro, midi, engine, musicutil, util) so a script runs in plain lua. load it, press keys, turn encoders, `run()` time forward, then look at what the engine was told, what midi went out and what got drawn. not rotere-specific - copy it into any norns script.
- `test_rotere.lua` - the checks. each one was first done by hand while building rotere.
- `render_screens.lua` + `screen_png.py` - record a few `redraw()`s and turn them into a png sheet. rects and lines are pixel-exact, text is a close-but-not-identical copy of the norns font.
- `bench.lua` - physics timing and note-flood numbers.

install lua 5.3: `brew install lua@5.3` (mac) or `apt install lua5.3`.

# autowarmthasym.koplugin

Companion plugin for KOReader's built-in **Auto warmth** plugin. It lets you set a
different warmth (and night mode) value for every sun event, for example cold at
sunrise and warm at sunset.

The stock plugin already stores one value per sun event and its scheduler
interpolates between them. Only its settings menu forces the evening value to
mirror the morning one ("Sunset and sunrise", "Darkest time of civil twilight",
...). This plugin replaces that one menu function on the running Auto warmth
instance; nothing in `koreader/plugins/autowarmth.koplugin` is modified, so the
change survives KOReader updates.

## Install

1. Download `autowarmthasym.koplugin.zip` from the latest
   [release](https://github.com/glaucon1984/autowarmthasym.koplugin/releases)
   and unzip it into `koreader/plugins/` on the device, so the
   `autowarmthasym.koplugin` folder sits next to `autowarmth.koplugin`.
2. Restart KOReader.
3. Open the Auto warmth menu. The "Set warmth and night mode for:" section now
   lists Civil dawn, Sunrise, Solar noon, Sunset and Civil dusk separately
   (plus the nautical, astronomical and solar midnight entries in expert mode).

Existing Auto warmth settings are kept; the stored format is unchanged.

## Requirements

- Auto warmth plugin enabled (the companion does nothing otherwise).
- Tested against the KOReader `master` plugin source of 2026-09; the replaced
  function is `AutoWarmth:getWarmthMenu()`. If a future KOReader changes that
  function, disable this plugin in Plugin management and the stock menu is back.

## Development

`tests/test_asym.lua` is a LuaJIT harness that loads the stock plugin and this
one with stubbed KOReader modules and checks the menu behaviour (46 checks):

```
luajit tests/test_asym.lua autowarmthasym.koplugin path/to/autowarmth.koplugin
```

CI downloads the stock plugin from KOReader `master` and runs the same harness
on every push, so a breaking upstream change shows up as a failed run.

## Uninstall

Delete the folder, or disable it in Plugin management. The stock menu returns,
but it will again mirror values once you change one.

## License

AGPL-3.0-or-later, the same as KOReader. The replaced menu function is derived
from KOReader's `plugins/autowarmth.koplugin/main.lua`.

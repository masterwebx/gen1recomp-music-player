# Music Player

A [gen1recomp](https://github.com/bryanthaboi/gen1recomp) mod that opens an in-game music browser on the overworld, with favorites and a now-playing HUD.

**Requires** gen1recomp `>=0.1.37 <2.0.0`. Declares the `engine_internals` permission.

## Controls

| Input | Action |
| --- | --- |
| **SELECT + A** (overworld) | Open the music list |
| **A** (in list) | Play the selected track (loops) |
| **START** (in list) | Mark / unmark favorite (`F` on the right) |
| **SELECT** (in list) | Restore map music |
| **B** (in list) | Close |
| **SELECT + START** (overworld) | Play favorites playlist (one-shot each track, then next; loops the queue) |

While a custom track is locked, a now-playing chip (name + bar visualizer) sits in the bottom-left. Long titles scroll like a billboard.

Favorites are stored in your save (`mod.save`).

## Install

1. Download `MUSIC_PLAYER-1.2.2.zip` from [Releases](https://github.com/masterwebx/gen1recomp-music-player/releases).
2. In gen1recomp, open the **MODS** panel and **Import mod.zip**.
3. Enable **Music Player** (allow `engine_internals` if prompted).
4. Restart if the manager asks you to.

Or unzip so you have `mods/MUSIC_PLAYER/manifest.json` next to the game (portable installs).

## Notes

- Map music cues stay on your chosen track until you restore map music with **SELECT** in the list.
- Favorites playlist uses the engine one-shot path so tracks can advance; if a track misbehaves, restore map music and try again.

## Support

If you like this mod, you can tip on [Ko-fi](https://ko-fi.com/justwex).

## License

MIT — see [LICENSE](LICENSE).

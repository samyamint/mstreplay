# Changelog

## 1.1.0

- **macOS:** updated to STREPLAY 1.1.0, retaining AVFoundation export, the universal encoder, and Finder support.

- **Player outlines:** turn outlines around players on or off in replays and renders (Settings tab and the render panel). They use your outline colours and width from the game's settings: the team colour for you, the enemy colour for everyone else.
- **Viewmodel: Default or Kestrel.** Kestrel shows your first-person arms and weapon the way Kestrel's Minimal Viewmodels Reborn is set up (offset, FOV, mirrored, hidden arms or weapon), in My view and in renders. Changes made in game with Mod Menu show up right away. Without that mod installed, replays keep the default viewmodel.
- **My view closer to the game:**
  - Your first-person hands show. They were switched off along with the rest of what other players don't see.
  - The weapon in your hands is drawn by the viewmodel camera, like in game: at the viewmodel FOV, and it no longer clips into walls.
- **Voice chat kept out of replays:** the "who's talking" tags and your own "transmitting voice" note are no longer recorded. Recordings made with 1.0.0, where they showed up as a white box, skip them too.
- **Kill feed:** replays show the same kill feed whether you just launched the game or just finished a match. Kill feed lines left over from the live game no longer fade along with the replay. The text in each line's box keeps the gap below it, like in game.

## 1.0.0 for macOS

- Replace external FFmpeg encoding with a bundled AVFoundation helper for H.264/H.265 MP4 and ProRes 4444 MOV, including sound.
- Support Apple Silicon and Intel on macOS 12 or later, with PNG/WAV fallback when native encoding cannot start.
- Use Finder for opening folders, accept Command key bindings, and discover the macOS Steam game assemblies.
- Build and package the native encoder locally; remove the Windows FFmpeg companion package.

## 1.0.0

First public release.

- **Recording:** automatic recording of every round, with markers (F8) and automatic kill and death markers.
- **Browser:** replay browser grouped by match, plus a Highlights list ranking your kills across all recordings.
- **Playback:**
  - My view (camera, arms, HUD, post-processing, sounds).
  - Free camera, player POV, and chase, orbit and victim angles.
  - Timeline with clip range, slow motion and frame stepping.
- **Render:** any resolution and frame rate, sub-frame motion blur, H.264/H.265/ProRes through ffmpeg or a PNG sequence, with sound.
- **Folder size limit:** the oldest unmarked rounds are deleted when the replay folder passes the limit.
- **Disk safety:** always leaves 2 GB free on the drive (old unmarked rounds go early, recording pauses if nothing can), with a low-space warning.
- **Settings tab:** storage limit with an hours estimate, replay folder, recording on/off (F9 in game), update rate, REC indicator, automatic markers, key bindings and free camera settings.

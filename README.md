# Dartify

An iPhone app that scores steel-tip darts automatically. Mount the phone so it looks at the board, and it detects each dart as it lands, works out the score, calls it out loud and keeps the match going. It can also show a live scoreboard on a TV over AirPlay.

## Features

- **Camera scoring**: finds the board, calibrates itself and scores every dart without any taps.
- **Tap scoring**: score on a board drawn on screen when there's no camera setup.
- **Game modes**: X01 (301 / 501 / 701, double in/out, best-of legs) and Killer, for 1–4 players.
- **Corrections and undo**: fix any dart in the current visit and the whole visit is scored again.
- **Spoken scores**: scores are called out like a darts caller ("Treble 20", "Bust").
- **TV scoreboard**: a dedicated scoreboard on an external display via AirPlay, not just mirroring.
- **Stats**: average, form chart, records, checkout/doubles rate, a heat map of where your darts land and a visit-by-visit breakdown of every match.

## How the camera scoring works

The scoring uses classic computer vision written in plain Swift, with no machine-learning model and no OpenCV. It runs in real time on the phone's camera frames, in three stages.

### 1. Finding the board (`Detection/BoardDetector.swift`)

1. Each frame is downsampled and every pixel is classified as **red**, **green** or neither.
2. The coloured pixels are grouped into connected blobs. The double ring (the outer band of alternating red and green segments) is the largest thin blob that contains both colours.
3. The detector counts colour changes around the ring. A real double ring has exactly **20** of them (10 red and 10 green segments), which rules out other red and green objects.
4. An **ellipse** is fitted to the ring's edges with RANSAC (`EllipseFit.swift`), then refined at full resolution.

### 2. Calibration (`Detection/BoardGeometry.swift`)

The detector finds the 20 segment wires along the ring, works out which segment is the 20, and locates the bull. Those points are matched to a standard board's real dimensions in millimetres to fit a **homography**: a transform between the camera image and a top-down view of the board. The camera can then be at an angle and every pixel still maps to a board position in millimetres. Once the calibration has been stable for about two seconds, the board **locks**. At that point exposure, focus and white balance are frozen so that only real changes show up.

### 3. Detecting darts (`Detection/DartDetector.swift`)

1. Every frame is warped into a top-down view of the board (1 mm per pixel) and compared with a reference view taken before the throw.
2. Motion is tracked in 5×5 mm blocks. The detector waits until the scene is still again, so a hand or a dart in flight isn't scored.
3. A dart-sized area of change is a new dart. A much larger change means the darts were pulled out (the visit is over) or someone is standing in front of the board.
4. **Finding the tip:** a dart sticks out of the board, so in the top-down view it smears away from the camera. The tip is the narrow end of the changed area, or the end nearest the camera's position over the board when both ends look alike.
5. The tip's position in millimetres gives the score directly: distance from the bull gives the ring, and the angle gives the segment.

If the whole board suddenly changes, the app assumes the camera moved or the lighting changed. It re-detects the board and recalibrates if needed.

Some lessons from building it:

- The phone needs a **fixed mount**. Held in a hand, it constantly reports movement.
- Detection runs with compiler optimisation even in Debug builds (`-O`), because unoptimised it was about 40× slower.

## Project structure

```
Dartify/
├── Camera/       Capture session, camera preview and overlays
├── Detection/    Board detection, calibration, dart detection (the CV part)
├── Game/         X01 and Killer rules, match controller, tap board, announcer
├── Home/         Home screen and match setup
├── Profile/      Players and recent matches
├── Stats/        SwiftData match stats, stats page, heat map, match details
├── Scoreboard/   AirPlay TV scoreboard
└── Theme/        Shared "soft" UI styling
```

## Requirements

- Xcode 26 and iOS 26
- An iPhone (the camera scoring doesn't work in the simulator), on a fixed mount facing the board
- Optional: an Apple TV or AirPlay display for the scoreboard

## Running it

1. Open `Dartify.xcodeproj` in Xcode.
2. Choose your iPhone as the run destination and set your own team under *Signing & Capabilities*. A free Apple developer account works.
3. Build and run, mount the phone facing the board, and start an X01 match with camera scoring.

`Dartify-Info.plist` in the project root declares the external-display scene. Keep it: without it, AirPlay only mirrors the phone screen instead of showing the scoreboard.

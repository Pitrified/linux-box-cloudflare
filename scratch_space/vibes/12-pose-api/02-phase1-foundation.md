# Phase 1 - Foundation

Set up the `pose-tools` repo and extract the core shared types that are identical or near-identical across climbing-wire, holo-table, and abyss.

Parent: [00-pose-overview.md](./00-pose-overview.md)

## 1.1 - Repo scaffolding

**Status:** not started

Create the `pose-tools` repo from `python-project-template`. Package name: `pose_tools`. Python 3.13, uv-managed.

Tasks:
- [ ] Run `uv run rename-project pose_tools` from the template
- [ ] Set up `pyproject.toml` with core deps: `mediapipe`, `opencv-contrib-python`, `numpy`, `matplotlib`, `loguru`
- [ ] Verify `uv run pytest && uv run ruff check . && uv run pyright` passes on the empty scaffold
- [ ] Initialize git repo and push to GitHub

## 1.2 - Frame dataclass

**Status:** not started

Unify the `Frame` dataclass. Target: the holo-table/abyss version (mp.Image-based) as the canonical implementation, since it is more capable than climbing-wire's bare numpy version.

Source files:
- `climbing-wire/src/climbing_wire/video/frame.py` - `Frame(frame: np.ndarray, usec: int, idx: int)`
- `holo-table/src/holo_table/video/frame.py` - `Frame(image: mp.Image, msec: float, idx: int)` with `from_np_array()`, `from_opencv()`, `from_file()`
- `abyss/src/abyss/video/frame.py` - identical to holo-table

Target: `pose_tools/video/frame.py`

Tasks:
- [ ] Copy the holo-table/abyss `Frame` as the base
- [ ] Add `usec` property (derived from `msec`) for backward compat with climbing-wire
- [ ] Add `to_numpy()` method returning a plain numpy BGR array (for climbing-wire's pipeline)
- [ ] Ensure `from_np_array()`, `from_opencv()`, `from_file()` factory methods are present
- [ ] Write unit tests for all factory methods and conversions

## 1.3 - Video loading utilities

**Status:** not started

Unify video loading. Target: abyss's `VideoFrameIterator` (context-managed class, most mature) plus the generator functions from holo-table/climbing-wire.

Source files:
- `climbing-wire/src/climbing_wire/video/load.py` - `iterate_video_frames()`, `pairwise_video_frames()`, `first_video_frame()`
- `holo-table/src/holo_table/video/load.py` - `iterate_video_frames()`, `list_video_frames()`
- `abyss/src/abyss/video/load.py` - `VideoFrameIterator` class, `list_video_frames()`

Target: `pose_tools/video/load.py`

Tasks:
- [ ] Port `VideoFrameIterator` from abyss as the primary class
- [ ] Add `list_video_frames()` convenience function (wraps iterator into a list)
- [ ] Add `iterate_video_frames()` thin wrapper (generator, for backward compat)
- [ ] Consider adding `pairwise_video_frames()` if it generalizes beyond climbing (otherwise stays in climbing-wire)
- [ ] Write tests using a short sample video fixture

## 1.4 - OpenCV display utilities

**Status:** not started

Extract shared OpenCV helpers.

Source files:
- `climbing-wire/src/climbing_wire/utils/cv.py` - `cv_imshow()`, `perspective_transform()`
- `holo-table/src/holo_table/utils/cv.py` - `cv_imshow()`, `resize()`, `cv_imshow_rgb()`
- `abyss/src/abyss/utils/cv.py` - `resize()`, `cv_imshow_rgb()`

Target: `pose_tools/utils/cv.py`

Tasks:
- [ ] Extract `resize(image, desired_width, desired_height)` - present in holo-table and abyss
- [ ] Extract `cv_imshow(img, ax)` - present in climbing-wire and holo-table
- [ ] Extract `cv_imshow_rgb(winname, image_rgb)` - present in holo-table and abyss
- [ ] `perspective_transform` stays in climbing-wire for now (geometry, Phase 3 candidate)
- [ ] Write tests for resize (input/output shape validation)

## 1.5 - Matplotlib plotting utilities

**Status:** not started

Extract shared plotting helpers.

Source files:
- `holo-table/src/holo_table/utils/plt.py` - `show_frame(frame, ax, title_suffix, do_show, do_resize)`
- `abyss/src/abyss/utils/plt.py` - identical to holo-table

Target: `pose_tools/utils/plt.py`

Tasks:
- [ ] Port `show_frame()` from holo-table/abyss (they are identical)
- [ ] Verify it works with the new unified `Frame` dataclass
- [ ] Write basic smoke test (non-display, just check no exceptions)

## 1.6 - MediaPipe shared utilities

**Status:** not started

Extract common MediaPipe helpers used by both pose and hand detection.

Source files:
- `climbing-wire/src/climbing_wire/utils/mediapipe.py` - `POSE_LANDMARKS_NAMES`, `POSE_LANDMARKS_MAP`, `normalized_to_pixel_coordinates()`, `are_valid_normalized_points()`
- `holo-table/src/holo_table/utils/mediapipe.py` - `HAND_LANDMARK_NAMES`, `HAND_LANDMARK_MAP`, `get_default_hand_connections()`, `get_spec_from_map()`, `get_landmarks_from_result()`, `list_land_to_landlist()`
- `abyss/src/abyss/utils/mediapipe.py` - `POSE_LANDMARK_NAMES`, `POSE_LANDMARK_MAP`, `get_default_pose_connections()`, `get_landmarks_from_result()`, `list_land_to_landlist()`

Target: `pose_tools/utils/mediapipe.py`

Tasks:
- [ ] Extract `get_spec_from_map()` - generic drawing spec helper (from holo-table)
- [ ] Extract `list_land_to_landlist()` - protobuf conversion, works for both hand and pose landmarks
- [ ] Extract `get_landmarks_from_result()` - generalize to accept both `HandLandmarkerResult` and `PoseLandmarkerResult`
- [ ] Extract `normalized_to_pixel_coordinates()` from climbing-wire (numpy-based coordinate conversion)
- [ ] Extract `are_valid_normalized_points()` from climbing-wire
- [ ] Provide landmark name/map constants for both pose and hand (keep separate: `POSE_LANDMARK_NAMES`, `HAND_LANDMARK_NAMES`)
- [ ] Provide `get_default_pose_connections()` and `get_default_hand_connections()`
- [ ] Write tests for coordinate conversion and protobuf utilities

## 1.7 - Numpy signal utilities

**Status:** not started

Extract general-purpose numpy helpers used by holo-table's signal processing.

Source files:
- `holo-table/src/holo_table/utils/np.py` - `diff_pad()`, `create_left_triangle_filter()`, `roll_append()`, `roll_append_smooth()`

Target: `pose_tools/utils/np_signal.py`

Tasks:
- [ ] Port all four functions from holo-table
- [ ] These are general signal processing functions, not pose-specific, but useful for gesture tracking pipelines
- [ ] Write unit tests with known input/output pairs

## Dependencies between sub-tasks

```
1.1 (scaffolding)
 ├── 1.2 (Frame)
 │    ├── 1.3 (video loading) - uses Frame
 │    ├── 1.5 (plt utils) - uses Frame
 │    └── 1.6 (mediapipe utils) - partially depends on Frame
 ├── 1.4 (cv utils) - independent of Frame
 └── 1.7 (np signal utils) - independent
```

## Done criteria

- `pose_tools` package installable with `uv pip install -e .`
- All extracted utilities have unit tests
- `uv run pytest && uv run ruff check . && uv run pyright` passes
- No consumer repos modified yet (that is Phase 4)

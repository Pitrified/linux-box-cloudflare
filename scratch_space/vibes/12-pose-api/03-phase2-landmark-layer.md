# Phase 2 - Landmark layer

Build the landmarker abstraction layer on top of MediaPipe's Tasks API. This phase creates unified wrappers for pose and hand detection, drawing, and numpy-based landmark arrays.

Parent: [00-pose-overview.md](./00-pose-overview.md)  
Depends on: [Phase 1](./02-phase1-foundation.md) (Frame, mediapipe utils)

## 2.1 - Base landmarker pattern

**Status:** not started

Define the shared interface and dispatch logic that both pose and hand landmarkers use.

Source files:
- `holo-table/src/holo_table/landmark/compute.py` - `HandLandmarkerFrame` with `detect(frame)` dispatching on running mode
- `abyss/src/abyss/landmarker/pose.py` - `PoseLandmarkerFrame` with `detect(frame)` dispatching on running mode

Target: `pose_tools/landmark/base.py`

Tasks:
- [ ] Define a `Protocol` or ABC `BaseLandmarkerFrame` with `detect(frame: Frame) -> ResultT` signature
- [ ] Extract the common mode-dispatch logic (IMAGE vs VIDEO mode detection) into a shared mixin or base
- [ ] Both `HandLandmarkerFrame` and `PoseLandmarkerFrame` use the same pattern: store the landmarker, check the running mode, call `detect()` or `detect_for_video()` accordingly
- [ ] Write a minimal test verifying the protocol

## 2.2 - Pose landmarker wrapper

**Status:** not started

Port the pose landmarker wrapper from abyss into pose-tools.

Source files:
- `abyss/src/abyss/landmarker/pose.py` - `create_pose_landmarker()`, `PoseLandmarkerFrame`

Target: `pose_tools/landmark/pose.py`

Tasks:
- [ ] Port `create_pose_landmarker(model_path, **kwargs)` factory function
- [ ] Port `PoseLandmarkerFrame` class, updated to use the base pattern from 2.1
- [ ] Ensure it uses the unified `Frame` from Phase 1
- [ ] Write integration test with a sample image (needs a pose_landmarker.task model file fixture)

## 2.3 - Hand landmarker wrapper

**Status:** not started

Port the hand landmarker wrapper from holo-table into pose-tools.

Source files:
- `holo-table/src/holo_table/landmark/compute.py` - `create_hand_landmarker()`, `HandLandmarkerFrame`

Target: `pose_tools/landmark/hand.py`

Tasks:
- [ ] Port `create_hand_landmarker(model_path, **kwargs)` factory function
- [ ] Port `HandLandmarkerFrame` class, updated to use the base pattern from 2.1
- [ ] Ensure it uses the unified `Frame` from Phase 1
- [ ] Write integration test with a sample image (needs a hand_landmarker.task model file fixture)

## 2.4 - Landmark drawing

**Status:** not started

Provide a single `draw_landmarks()` that works for both pose and hand results.

Source files:
- `climbing-wire/src/climbing_wire/landmark/drawing.py` - custom implementation with `LandmarkListImg`
- `holo-table/src/holo_table/landmark/drawing.py` - `draw_landmarks(frame, HandLandmarkerResult, ...)`
- `abyss/src/abyss/landmarker/drawing.py` - `draw_landmarks(frame, PoseLandmarkerResult)`

Target: `pose_tools/landmark/drawing.py`

Tasks:
- [ ] Create `draw_pose_landmarks(frame, PoseLandmarkerResult, ...)` based on abyss version
- [ ] Create `draw_hand_landmarks(frame, HandLandmarkerResult, ...)` based on holo-table version
- [ ] Both use `get_spec_from_map()` and `list_land_to_landlist()` from Phase 1 mediapipe utils
- [ ] Consider a unified `draw_landmarks()` with type dispatch, or keep separate for clarity
- [ ] Write visual smoke tests (non-display, verify output is a valid numpy array with correct shape)

## 2.5 - Landmark array (numpy-based)

**Status:** not started

Modernize climbing-wire's `LandmarkListNp` / `LandmarkListImg` to work with the Tasks API instead of the legacy Solutions API. This is climbing-wire's most unique contribution - a rich numpy-based landmark representation.

Source files:
- `climbing-wire/src/climbing_wire/landmark/landmark_list.py` - `LandmarkListNp`, `LandmarkListImg`

Target: `pose_tools/landmark/landmark_array.py`

Tasks:
- [ ] Audit `LandmarkListNp` - currently wraps `landmark_pb2.NormalizedLandmarkList` from legacy API
- [ ] Refactor to accept Tasks API `PoseLandmarkerResult` landmarks (list of `NormalizedLandmark`)
- [ ] Preserve the numpy-based visibility masking, drawable flags, and pixel coordinate conversion
- [ ] Preserve `get_landmark_for_joint()` for extracting specific joints by name
- [ ] Rename to `LandmarkArray` / `LandmarkArrayImg` for clarity
- [ ] Write tests: construct from a mock list of landmarks, verify coordinate conversion, visibility masking

## 2.6 - Landmark distance computation

**Status:** not started

Extract landmark distance utilities that are useful across multiple use cases (not just pinch detection).

Source files:
- `holo-table/src/holo_table/landmark/dist.py` - `compute_landmark_dist()`, `compute_pinch_level()`

Target: `pose_tools/landmark/distance.py`

Tasks:
- [ ] Port `compute_landmark_dist(landmarks, name1, name2)` - generic distance between any two landmarks
- [ ] `compute_pinch_level()` is hand-specific but still useful as a library function - port it too
- [ ] Generalize to work with either world or normalized landmarks
- [ ] Write tests with known landmark positions and expected distances

## 2.7 - Model manager

**Status:** not started

Unified resource/model path management replacing the per-repo `get_resource()` functions.

Source files:
- `holo-table/src/holo_table/utils/data.py` - `get_resource()` with hand_landmarker.task paths
- `abyss/src/abyss/utils/data.py` - `get_resource()` with pose_landmarker.task paths
- `climbing-wire/src/climbing_wire/utils/data.py` - `get_package_fol()` for data folder paths

Target: `pose_tools/landmark/model_manager.py`

Tasks:
- [ ] Define a config-based model resolver supporting all model types (pose, hand, face in future)
- [ ] Default model location: `~/.mediapipe/models/<model_name>.task`
- [ ] Support custom paths via constructor or env var
- [ ] Add `download_model()` or at least a clear error message if the model file is missing
- [ ] Write tests with tmp_path fixtures for path resolution

## Dependencies between sub-tasks

```
2.1 (base pattern)
 ├── 2.2 (pose landmarker) - implements base
 ├── 2.3 (hand landmarker) - implements base
 └── 2.4 (drawing) - uses detection results from 2.2/2.3

2.5 (landmark array) - independent of 2.1-2.4, depends on Phase 1 mediapipe utils
2.6 (distance) - independent, depends on Phase 1
2.7 (model manager) - independent, used by 2.2 and 2.3
```

## Done criteria

- All landmarker wrappers work with the unified `Frame` from Phase 1
- Tests pass for both pose and hand detection with sample images
- climbing-wire's `LandmarkListImg` functionality is preserved in modernized form
- `uv run pytest && uv run ruff check . && uv run pyright` passes

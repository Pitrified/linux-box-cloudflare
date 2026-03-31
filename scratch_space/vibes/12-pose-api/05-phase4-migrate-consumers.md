# Phase 4 - Migrate consumers

Update the three consumer repos to depend on `pose-tools` and remove duplicated code. Each repo keeps only its domain-specific logic.

Parent: [00-pose-overview.md](./00-pose-overview.md)  
Depends on: [Phase 1](./02-phase1-foundation.md), [Phase 2](./03-phase2-landmark-layer.md), [Phase 3](./04-phase3-geometry.md)

## 4.1 - Migrate abyss

**Status:** not started

Abyss is the simplest consumer (fewest files, closest to the target API). Start here.

Current source files to replace:
- `abyss/src/abyss/video/frame.py` -> use `pose_tools.video.frame.Frame`
- `abyss/src/abyss/video/load.py` -> use `pose_tools.video.load.VideoFrameIterator`
- `abyss/src/abyss/utils/cv.py` -> use `pose_tools.utils.cv`
- `abyss/src/abyss/utils/plt.py` -> use `pose_tools.utils.plt`
- `abyss/src/abyss/utils/mediapipe.py` -> use `pose_tools.utils.mediapipe`
- `abyss/src/abyss/utils/data.py` -> use `pose_tools.landmark.model_manager`
- `abyss/src/abyss/landmarker/pose.py` -> use `pose_tools.landmark.pose`
- `abyss/src/abyss/landmarker/drawing.py` -> use `pose_tools.landmark.drawing`

What stays in abyss:
- 3D projection/rendering logic (the core domain)
- Notebooks (update imports only)

Tasks:
- [ ] Add `pose-tools` as a dependency in `pyproject.toml`
- [ ] Replace all imports in `src/abyss/` to use `pose_tools.*`
- [ ] Delete the replaced source files (entire `utils/`, `video/`, `landmarker/` folders)
- [ ] Update `sample01.ipynb` imports
- [ ] Run tests, fix any breakage
- [ ] Verify `uv run pytest && uv run ruff check . && uv run pyright` passes

## 4.2 - Migrate holo-table

**Status:** not started

Holo-table has more domain-specific code (pinch tracking, socket transport, Streamlit/GUI apps) so the migration is selective.

Current source files to replace:
- `holo_table/video/frame.py` -> use `pose_tools.video.frame.Frame`
- `holo_table/video/load.py` -> use `pose_tools.video.load`
- `holo_table/utils/cv.py` -> use `pose_tools.utils.cv`
- `holo_table/utils/plt.py` -> use `pose_tools.utils.plt`
- `holo_table/utils/mediapipe.py` -> use `pose_tools.utils.mediapipe`
- `holo_table/utils/data.py` -> use `pose_tools.landmark.model_manager`
- `holo_table/utils/np.py` -> use `pose_tools.utils.np_signal`
- `holo_table/landmark/compute.py` -> use `pose_tools.landmark.hand`
- `holo_table/landmark/drawing.py` -> use `pose_tools.landmark.drawing`
- `holo_table/landmark/dist.py` -> use `pose_tools.landmark.distance`

What stays in holo-table:
- `holo_table/pinch/tracker.py` - domain-specific pinch gesture logic
- `holo_table/socket/socket.py` - UDP transport (not pose-related)
- `holo_table/app/` - all application entry points (GUI sender/receiver, Streamlit apps)
- `holo_table/utils/utils.py` - `get_current_msec()` (trivial, not worth extracting)

Tasks:
- [ ] Add `pose-tools` as a dependency in `pyproject.toml`
- [ ] Replace all imports in `src/holo_table/` to use `pose_tools.*`
- [ ] Delete replaced source files
- [ ] Update `PinchTracker` to import signal processing from `pose_tools.utils.np_signal`
- [ ] Update notebooks (`landmarker_01.ipynb`, `pinch_01.ipynb`) imports
- [ ] Update CLI entry points (`gui_sender`, `gui_receiver`) imports
- [ ] Update Streamlit apps imports
- [ ] Run tests, fix any breakage
- [ ] Verify `uv run pytest && uv run ruff check . && uv run pyright` passes

## 4.3 - Migrate climbing-wire

**Status:** not started

The most complex migration. Climbing-wire uses the legacy MediaPipe Solutions API and has custom numpy-based landmark wrappers. This migration also involves upgrading to the Tasks API.

Current source files to replace:
- `climbing_wire/video/frame.py` -> use `pose_tools.video.frame.Frame` (API change: np.ndarray -> mp.Image)
- `climbing_wire/video/load.py` -> use `pose_tools.video.load`
- `climbing_wire/utils/cv.py` -> use `pose_tools.utils.cv` (keep `perspective_transform` if not extracted)
- `climbing_wire/utils/data.py` -> use `pose_tools.landmark.model_manager`
- `climbing_wire/utils/mediapipe.py` -> use `pose_tools.utils.mediapipe`
- `climbing_wire/landmark/compute.py` -> use `pose_tools.landmark.pose` (major change: legacy -> Tasks API)
- `climbing_wire/landmark/landmark_list.py` -> use `pose_tools.landmark.landmark_array`
- `climbing_wire/landmark/drawing.py` -> use `pose_tools.landmark.drawing`

What stays in climbing-wire:
- `climbing_wire/homography/homography.py` - if not extracted to pose-tools in Phase 3
- `climbing_wire/joint_tracker/` - `JointTracker`, `JointHist` (domain-specific)
- `climbing_wire/fastdtw/` - vendored DTW (domain-specific)

Breaking changes to handle:
- [ ] `Frame.frame` (np.ndarray) -> `Frame.image` (mp.Image) - all code accessing raw pixels needs updating
- [ ] `PoseImg` (legacy Solutions API) -> `PoseLandmarkerFrame` (Tasks API) - different result format
- [ ] `LandmarkListNp`/`LandmarkListImg` constructed from NormalizedLandmarkList -> from Tasks API results
- [ ] `JointTracker` and `JointHist` depend on the old landmark format - need updating
- [ ] Homography code uses raw numpy frames - need `Frame.to_numpy()` calls

Tasks:
- [ ] Add `pose-tools` as a dependency in `pyproject.toml`
- [ ] Update `Frame` usage throughout: `frame.frame` -> `frame.to_numpy()` or `frame.image`
- [ ] Rewrite `JointTracker` to use `PoseLandmarkerFrame` + `LandmarkArray` from pose-tools
- [ ] Update homography pipeline to work with the new Frame type
- [ ] Update all 7 notebooks imports and Frame access patterns
- [ ] Run each notebook end-to-end to verify no regression
- [ ] Verify `uv run pytest && uv run ruff check . && uv run pyright` passes

## Migration order rationale

```
4.1 abyss (simplest, ~9 files, already on Tasks API)
 -> validates pose-tools API works for a real consumer
4.2 holo-table (medium, ~19 files, already on Tasks API)
 -> validates hand landmarker path + signal processing
4.3 climbing-wire (hardest, legacy API migration + custom wrappers)
 -> benefits from lessons learned in 4.1 and 4.2
```

## Done criteria

- All three repos depend on `pose-tools` for shared code
- No duplicated Frame/video/mediapipe-utils code remains
- climbing-wire upgraded from legacy Solutions API to Tasks API
- All tests pass in all four repos
- Each repo only contains its domain-specific logic

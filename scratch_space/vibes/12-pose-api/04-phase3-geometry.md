# Phase 3 - Geometry utilities

Extract geometry and signal processing utilities that support higher-level features like joint tracking and gesture detection.

Parent: [00-pose-overview.md](./00-pose-overview.md)  
Depends on: [Phase 1](./02-phase1-foundation.md) (Frame, cv utils), [Phase 2](./03-phase2-landmark-layer.md) (landmark array)

## 3.1 - Homography computation

**Status:** not started

Extract SIFT-based homography computation from climbing-wire. This is used for camera motion compensation (stabilizing landmark positions across frames when the camera moves).

Source files:
- `climbing-wire/src/climbing_wire/homography/homography.py` - `compute_homography(img1, img2)`
- `climbing-wire/src/climbing_wire/utils/cv.py` - `perspective_transform(points, M)`

Target: `pose_tools/geometry/homography.py`

Tasks:
- [ ] Port `compute_homography(img1, img2) -> np.ndarray` - SIFT feature detection + FLANN matching + RANSAC homography
- [ ] Port `perspective_transform(points, M) -> np.ndarray` - apply a homography matrix to a set of 2D points
- [ ] Document the expected input format (BGR numpy arrays) and output (3x3 homography matrix)
- [ ] Handle edge cases: insufficient keypoints, no matches, degenerate homography
- [ ] Write tests with synthetic image pairs (shifted/rotated versions of the same image)

Decision point: this is only used by climbing-wire today. If the scope feels too narrow, it can remain in climbing-wire and be extracted later when a second consumer appears. Include if the extraction is straightforward.

## 3.2 - Landmark distance and geometry

**Status:** not started

General geometric operations on landmark positions beyond the per-landmark distances in Phase 2.

Source files:
- `climbing-wire/src/climbing_wire/utils/mediapipe.py` - `normalized_to_pixel_coordinates()`, `are_valid_normalized_points()`
- `holo-table/src/holo_table/landmark/dist.py` - `compute_landmark_dist()` (already extracted in 2.6)

Target: `pose_tools/geometry/landmark_geometry.py`

Tasks:
- [ ] Port `normalized_to_pixel_coordinates(normalized_points, image_size, clip_to_image)` - batch conversion from normalized [0,1] to pixel coordinates
- [ ] Port `are_valid_normalized_points(points)` - validate that points are in [0,1] range
- [ ] Consider a `LandmarkGeometry` helper class or keep as standalone functions
- [ ] These are prerequisites for Phase 2's `LandmarkArray` pixel coordinate conversion
- [ ] Write tests with known coordinate conversions

Note: some of this may merge with Phase 1.6 (mediapipe utils) if the boundary feels artificial. The distinction is: Phase 1.6 handles MediaPipe data structure conversions, while this handles geometric coordinate math.

## 3.3 - Signal processing for gesture detection

**Status:** not started

The numpy signal processing utilities from Phase 1.7 are the foundation; this task layers gesture-level signal classification on top. Specifically, the smoothing + derivative + threshold logic used by holo-table's `PinchTracker`.

Source files:
- `holo-table/src/holo_table/pinch/tracker.py` - `PinchTracker` class

Target: Decision needed - either `pose_tools/gesture/signal_tracker.py` or stays in holo-table.

Tasks:
- [ ] Analyze `PinchTracker` to identify what is generic vs pinch-specific
- [ ] The rolling-window smoothing + first/second derivative computation + threshold-based classification pattern is reusable for any gesture detection based on a 1D signal
- [ ] If generalizable: extract a `SignalTracker` base that `PinchTracker` extends
- [ ] If too pinch-specific: leave in holo-table, just depend on `pose_tools.utils.np_signal` for the primitives
- [ ] Write tests for the signal processing pipeline with synthetic data

Decision point: this sub-task requires reading the `PinchTracker` implementation to decide the right boundary. Mark as "needs analysis" until then.

## Dependencies between sub-tasks

```
3.1 (homography) - depends on Phase 1 cv utils only
3.2 (landmark geometry) - depends on Phase 1 mediapipe utils, feeds into Phase 2 landmark array
3.3 (signal processing) - depends on Phase 1 np_signal utils, analysis needed
```

## Done criteria

- Homography and coordinate conversion functions have unit tests
- Signal processing boundary decision is made and documented
- `uv run pytest && uv run ruff check . && uv run pyright` passes

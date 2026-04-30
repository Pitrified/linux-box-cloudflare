# Assess `pose-tools` project

## Overview

plan made in this folder
`scratch_space/vibes/12-pose-api/*`
were implemented in repo
`pose-tools`

please analyze that repo and
- cross check that all the planned features were implemented, and if not, write a clear list of missing features and where they were planned to be implemented
- assess the overall code quality and propose meaningful improvements
- propose reasonable next steps for the project

## Implementation status

### Phase 1 - Foundation (complete)

All 7 sub-tasks landed and match the plan:

| Sub-task | Planned target | Actual file | Status |
|---|---|---|---|
| 1.1 Scaffolding | template + deps | `pyproject.toml` (mediapipe, opencv-contrib, matplotlib, numpy, loguru) | done |
| 1.2 `Frame` | `video/frame.py` | [frame.py](../../../../pose-tools/src/pose_tools/video/frame.py) - `Frame` (mp.Image + msec + idx), `usec` property, `from_np_array/from_opencv/from_file`, `to_numpy/to_opencv` | done |
| 1.3 Video loading | `video/load.py` | [load.py](../../../../pose-tools/src/pose_tools/video/load.py) - `VideoFrameIterator`, `list_video_frames`, `iterate_video_frames` | done |
| 1.4 OpenCV utils | `utils/cv.py` | [cv.py](../../../../pose-tools/src/pose_tools/utils/cv.py) - `resize`, `cv_imshow`, `cv_imshow_rgb` | done |
| 1.5 Matplotlib utils | `utils/plt.py` | [plt.py](../../../../pose-tools/src/pose_tools/utils/plt.py) - `show_frame` | done |
| 1.6 MediaPipe utils | `utils/mediapipe.py` | [mediapipe.py](../../../../pose-tools/src/pose_tools/utils/mediapipe.py) - constants, connections, `get_spec_from_map`, `get_landmarks_from_result` (overloaded), `normalized_to_pixel_coordinates`, `are_valid_normalized_points` | done |
| 1.7 Numpy signal utils | `utils/np_signal.py` | [np_signal.py](../../../../pose-tools/src/pose_tools/utils/np_signal.py) - `diff_pad`, `create_left_triangle_filter`, `roll_append`, `roll_append_smooth` | done |

Gap vs plan:
- `list_land_to_landlist()` (protobuf conversion, planned in 1.6) is **not present**. The new `draw_*_landmarks` functions in `landmark/drawing.py` use the Tasks API directly and no longer need it, so the omission is justified. Should be documented as an intentional drop.
- `pairwise_video_frames()` was listed as optional in 1.3 and was correctly left in `climbing-wire`.

### Phase 2 - Landmark layer (complete with caveats)

| Sub-task | Actual file | Status |
|---|---|---|
| 2.1 Base pattern | [base.py](../../../../pose-tools/src/pose_tools/landmark/base.py) - PEP-695 generic `BaseLandmarkerFrame[ResultT]` | done |
| 2.2 Pose landmarker | [pose.py](../../../../pose-tools/src/pose_tools/landmark/pose.py) - `create_pose_landmarker`, `PoseLandmarkerFrame` | done |
| 2.3 Hand landmarker | [hand.py](../../../../pose-tools/src/pose_tools/landmark/hand.py) - mirror of pose.py | done |
| 2.4 Drawing | [drawing.py](../../../../pose-tools/src/pose_tools/landmark/drawing.py) - `draw_pose_landmarks`, `draw_hand_landmarks` | done |
| 2.5 Landmark array | [landmark_array.py](../../../../pose-tools/src/pose_tools/landmark/landmark_array.py) - `LandmarkArray`, `LandmarkArrayImg` (Tasks API) | done |
| 2.6 Distance | [distance.py](../../../../pose-tools/src/pose_tools/landmark/distance.py) - `compute_landmark_dist`, `compute_pinch_level` | done |
| 2.7 Model manager | [model_manager.py](../../../../pose-tools/src/pose_tools/landmark/model_manager.py) - `ModelManager`, `ModelNotFoundError` | done |

Gaps vs plan:
- 2.2 / 2.3 do not include integration tests against real `.task` model fixtures (plan asked for them). Only construction-level tests would be possible without fixtures, and even those are missing.
- 2.4 does not provide a unified `draw_landmarks()` with type dispatch (plan flagged as optional - "consider").
- 2.5 keeps the legacy joint-name set (`left_hand`/`right_hand`/`left_foot`/`right_foot` only). No extension was made for additional joint groupings; acceptable since the plan asked only to preserve.
- 2.7 has no `download_model()` helper. Only a clear error message, which the plan accepted as a minimum bar.

### Phase 3 - Geometry (complete)

| Sub-task | Actual file | Status |
|---|---|---|
| 3.1 Homography | [homography.py](../../../../pose-tools/src/pose_tools/geometry/homography.py) - `compute_homography` (SIFT + FLANN + RANSAC), `perspective_transform`, `InsufficientMatchesError` | done |
| 3.2 Landmark geometry | [landmark_geometry.py](../../../../pose-tools/src/pose_tools/geometry/landmark_geometry.py) - re-exports from `utils.mediapipe` | done (thin) |
| 3.3 Signal processing | [signal_tracker.py](../../../../pose-tools/src/pose_tools/geometry/signal_tracker.py) - generic `SignalTracker` extracted from `PinchTracker` | done |

Gaps / observations:
- 3.2 is a pure re-export shim. The plan accepted this (Phase 1.6 vs Phase 3.2 boundary noted as artificial). Worth either consolidating or adding higher-level helpers.
- 3.3 lives under `geometry/` rather than the suggested `gesture/` namespace. Minor naming concern: signal tracking is not strictly geometry.

### Phase 4 - Migrate consumers (not started)

None of `abyss`, `holo-table`, or `climbing-wire` have been updated to depend on `pose-tools`. The duplicated code is still in place in all three repos. This is the only fully-missing planned phase.

### Other observations vs plan

- Repo follows the `python-project-template` scaffold strictly (`config/`, `params/`, `data_models/`, `metaclasses/`) even though `pose-tools` is a pure library with no env-driven runtime. The boilerplate is dead weight (no `params` or `config` is consumed by any feature module).
- `pydantic` and `python-dotenv` are listed as runtime deps but only the template scaffold uses them; the library code itself does not.
- Tests folder mirrors `src/` and unit tests cover all extracted utilities except the landmarker wrappers (no model fixtures available) and `Frame`/`VideoFrameIterator` (no sample-video fixture).
- Docs folder has only the template-provided `getting-started.md`, `contributing.md`, and three generic guides. No `library/` content describing the new modules.

## Code quality assessment

Strengths
- Clear module boundaries follow the plan: `video/`, `utils/`, `landmark/`, `geometry/`. One concept per file.
- Modern typing throughout: PEP-695 generics (`BaseLandmarkerFrame[ResultT]`), `Self`, `Literal`, `@overload` for `get_landmarks_from_result`.
- Custom exceptions (`InsufficientMatchesError`, `ModelNotFoundError`) instead of bare `ValueError` - matches house style.
- `loguru` used consistently for logging.
- Google-style docstrings present on most public symbols.
- Tests are small, focused, and use `tmp_path` fixtures correctly.

Concrete issues / improvement opportunities

1. `BaseLandmarkerFrame` typing is loose. `_landmarker: object` plus `# type: ignore[union-attr]` on every call defeats the generic. Either use a `Protocol` describing `detect`/`detect_for_video`, or parametrize a second type var (`BaseLandmarkerFrame[LandmarkerT, ResultT]`). The subclass `detect()` overrides only re-call `super().detect(frame)` and add nothing - they exist solely to narrow the return type and could be removed if the base is properly typed.

2. `landmark_array.py` accepts `landmarks: list` (untyped). This loses static checking entirely. It should accept `Sequence[NormalizedLandmark]`. The two `from_normalized_landmarks` classmethods duplicate the comprehension building `norm_ls`/`vis_ls`; factor a `_to_arrays(landmarks)` helper. The hard-coded `image_size=(480, 640)` default in `LandmarkArrayImg.from_normalized_landmarks` is a footgun - should be required.

3. `LandmarkArrayImg.get_landmark_for_joint` hard-codes a 4-entry joint map specific to climbing-wire. This is appropriate domain knowledge to keep, but it should live next to a `JOINT_NAMES_TYPE` constant (as climbing-wire had) and ideally be opt-in via a separate subclass or a free function rather than baked into the base image array, so non-climbing consumers do not inherit climbing semantics.

4. `utils/mediapipe.py` reaches into private API: `PoseLandmark._member_names_` / `._member_map_`. These work today but are brittle. Use `list(PoseLandmark.__members__)` and `dict(PoseLandmark.__members__)` instead. Also, `from mediapipe.tasks.python.vision import PoseLandmark` is unusual - verify the path is stable across mediapipe versions; the more common location is `mediapipe.tasks.python.vision.pose_landmarker`.

5. `get_landmarks_from_result` mixes responsibilities (pose vs hand vs handedness) and the implementation has an `if/elif` chain that pyright cannot prove exhaustive (`ll` may be unbound on an unknown `which_info`). Add a final `else: raise ValueError(...)` and assert via the overload set.

6. `compute_landmark_dist` / `compute_pinch_level` always read `.x/.y/.z`, but `NormalizedLandmark.z` is sometimes meaningless or missing for hand normalized landmarks. Consider a `dims: Literal[2, 3] = 3` parameter or document the assumption explicitly.

7. `VideoFrameIterator.__exit__` is untyped (`# noqa: ANN001`). Add the standard type hints (`type[BaseException] | None`, etc.) and drop the noqa.

8. `cv_imshow` mixes display side-effect (`plt.show()` + `plt.close()`) with axes drawing, depending on `ax`. This is hard to test and surprising. Split into `draw_bgr_on_ax(img, ax)` and `show_bgr(img)`.

9. `homography.compute_homography` does not validate `des1`/`des2` for `None` (SIFT can return `None` on featureless images). The current code would crash inside `flann.knnMatch`. Add a guard with a clear error.

10. Scaffolded but unused subsystems should be removed: `src/pose_tools/{config,params,data_models,metaclasses}/` and the `pydantic` / `python-dotenv` deps. They add cognitive load and lock the package to behaviours unneeded by a pure library.

11. `requires-python = "==3.14.*"` is too narrow for a shared library. The consumers (`climbing-wire`, `holo-table`, `abyss`) are on 3.11 / 3.13. Loosen to `>=3.13` or even `>=3.12` once 3.14-only syntax is verified - PEP-695 generics need 3.12+, so `>=3.12` is the practical floor.

12. `pyproject.toml` `description = "Add your description here"` is the template default and was never updated.

13. Test coverage gaps: no tests for `Frame` factory methods or round-trip conversions, no tests for `VideoFrameIterator` (would need a tiny sample-video fixture), no tests for `draw_pose_landmarks` / `draw_hand_landmarks`, no integration tests for the landmarkers (need bundled `.task` files or a pytest marker that skips when absent).

14. `geometry/landmark_geometry.py` is a 13-line re-export. Either remove (consumers can import from `utils/mediapipe.py`) or move the canonical definitions here and re-export from `utils/mediapipe.py`. The current arrangement violates "one obvious place".

15. `SignalTracker` retains every value forever in `all_*` lists. For long-running gesture pipelines this leaks memory. Make history retention opt-in (`record_history: bool = False`) or use a bounded deque.

16. Docs (`docs/library/`, `docs/reference/`) are empty. mkdocs is configured but produces a near-empty site. The repo `AGENTS.md` and copilot instructions both ask to keep `docs/` updated at end of task.

17. `README.md` references `~/cred/pose-tools/.env`, lints, and tests, but documents nothing about the actual library API. Add a "Quick start" with one pose-detect snippet and one hand-detect snippet.

## Next steps proposal

In priority order:

1. **Phase 4 migration (the missing phase).** Start with `abyss` (smallest surface, already on Tasks API). Concrete checklist:
    - Add `pose-tools` to abyss's `pyproject.toml` (path or git dep).
    - Replace imports per the plan in [05-phase4-migrate-consumers.md](./05-phase4-migrate-consumers.md) section 4.1.
    - Delete the now-redundant `abyss/src/abyss/{video,utils,landmarker}/` files.
    - Run `uv run pytest && uv run ruff check . && uv run pyright` in abyss.
    - The migration will likely flush out missing helpers (e.g., a `draw_landmarks` returning a `Frame` rather than `np.ndarray`); fix in `pose-tools` and re-test.
   Then `holo-table`, then `climbing-wire` (largest delta - legacy Solutions API to Tasks API, plus `JointTracker` rewrite to the new `LandmarkArrayImg`).

2. **Strip the unused scaffolding** (`config/`, `params/`, `data_models/`, `metaclasses/`, `pydantic`, `python-dotenv`) and **broaden Python support** (`>=3.12` or `>=3.13`). One-PR cleanup that materially improves usability for consumers.

3. **Tighten typing** in `BaseLandmarkerFrame` and `LandmarkArray.from_normalized_landmarks` (issues 1 and 2 above). Removes most `# type: ignore` comments.

4. **Add integration tests with bundled (or auto-downloaded) `.task` models** behind a `pytest.mark.requires_model` that skips by default. Use a CI job that downloads them once. Without this, the landmarker wrappers are effectively untested.

5. **Write the docs.** A `docs/library/` page per module (frame, video loading, landmarkers, landmark arrays, drawing, distance, homography, signal tracker) with one runnable snippet each. Update the README quick start. This is also the natural moment to nail down the public API by adding `__all__` to each module.

6. **Tidy small issues**: drop `landmark_geometry.py` re-export shim, replace `_member_names_`/`_member_map_` private access, add `else` branches in `get_landmarks_from_result`, fix `pyproject.toml` description, add `record_history` flag to `SignalTracker`, document the `list_land_to_landlist` removal in a CHANGELOG.

7. **Decide the gesture namespace.** Either move `SignalTracker` to `pose_tools/gesture/signal_tracker.py` (matching the original plan) or keep it under `geometry/` and document the renaming. Pick one and write it down.

8. **Optional: model auto-download.** Once consumers depend on `ModelManager`, ship a `download_model()` helper that fetches from the official MediaPipe URLs into `~/.mediapipe/models/`. Removes the manual setup step from every consumer's onboarding.

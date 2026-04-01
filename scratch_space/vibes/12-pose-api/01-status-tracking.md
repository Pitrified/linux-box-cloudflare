# Pose core tracking

High-level tracking of pose-related projects in the linux-box ecosystem.
Create dedicated tracking documents for sub-tasks with the format `NN-feature-name.md` as needed, increasing prefix.

Core analysis: [00-pose-overview.md](./00-pose-overview.md)

## Phase overview

| Phase | Plan | Status | Summary |
|-------|------|--------|---------|
| 1 - Foundation | [02-phase1-foundation.md](./02-phase1-foundation.md) | done | Repo scaffolding, Frame, video loading, CV/plt/mediapipe/numpy utils |
| 2 - Landmark layer | [03-phase2-landmark-layer.md](./03-phase2-landmark-layer.md) | done | Landmarker wrappers (pose + hand), drawing, landmark array, distance, model manager |
| 3 - Geometry | [04-phase3-geometry.md](./04-phase3-geometry.md) | done | Homography, coordinate geometry, signal processing boundary decision |
| 4 - Migrate consumers | [05-phase4-migrate-consumers.md](./05-phase4-migrate-consumers.md) | not started | Migrate abyss -> holo-table -> climbing-wire to depend on pose-tools |

## Phase 1 - Foundation (7 sub-tasks)

| # | Sub-task | Status | Notes |
|---|----------|--------|-------|
| 1.1 | Repo scaffolding | done | Created from python-project-template, added mediapipe/opencv/matplotlib deps |
| 1.2 | Frame dataclass | done | `video/frame.py` - mp.Image wrapper with factory methods + conversions |
| 1.3 | Video loading | done | `video/load.py` - VideoFrameIterator context manager + list/iterate helpers |
| 1.4 | OpenCV display utils | done | `utils/cv.py` - resize, cv_imshow, cv_imshow_rgb |
| 1.5 | Matplotlib plot utils | done | `utils/plt.py` - show_frame |
| 1.6 | MediaPipe shared utils | done | `utils/mediapipe.py` - Tasks API constants, connections, coordinate conversion |
| 1.7 | Numpy signal utils | done | `utils/np_signal.py` - diff_pad, triangle filter, roll_append |

## Phase 2 - Landmark layer (7 sub-tasks)

| # | Sub-task | Status | Notes |
|---|----------|--------|-------|
| 2.1 | Base landmarker pattern | done | `landmark/base.py` - PEP 695 generic BaseLandmarkerFrame[ResultT] |
| 2.2 | Pose landmarker wrapper | done | `landmark/pose.py` - PoseLandmarkerFrame |
| 2.3 | Hand landmarker wrapper | done | `landmark/hand.py` - HandLandmarkerFrame |
| 2.4 | Landmark drawing | done | `landmark/drawing.py` - Tasks API draw_landmarks, no protobuf conversion |
| 2.5 | Landmark array (numpy) | done | `landmark/landmark_array.py` - LandmarkArray + LandmarkArrayImg |
| 2.6 | Landmark distance | done | `landmark/distance.py` - compute_landmark_dist + compute_pinch_level |
| 2.7 | Model manager | done | `landmark/model_manager.py` - ModelManager with path resolution |

## Phase 3 - Geometry (3 sub-tasks)

| # | Sub-task | Status | Notes |
|---|----------|--------|-------|
| 3.1 | Homography computation | done | `geometry/homography.py` - SIFT + FLANN + RANSAC |
| 3.2 | Landmark geometry | done | `geometry/landmark_geometry.py` - re-exports from utils.mediapipe |
| 3.3 | Signal processing | done | `geometry/signal_tracker.py` - generic SignalTracker with derivative tracking |

## Phase 4 - Migrate consumers (3 sub-tasks)

| # | Sub-task | Status | Notes |
|---|----------|--------|-------|
| 4.1 | Migrate abyss | not started | Simplest: ~9 files, already on Tasks API |
| 4.2 | Migrate holo-table | not started | Medium: ~19 files, selective replacement |
| 4.3 | Migrate climbing-wire | not started | Hardest: legacy API upgrade + custom wrappers |

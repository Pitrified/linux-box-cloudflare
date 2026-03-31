# Pose core tracking

High-level tracking of pose-related projects in the linux-box ecosystem.
Create dedicated tracking documents for sub-tasks with the format `NN-feature-name.md` as needed, increasing prefix.

Core analysis: [00-pose-overview.md](./00-pose-overview.md)

## Phase overview

| Phase | Plan | Status | Summary |
|-------|------|--------|---------|
| 1 - Foundation | [02-phase1-foundation.md](./02-phase1-foundation.md) | not started | Repo scaffolding, Frame, video loading, CV/plt/mediapipe/numpy utils |
| 2 - Landmark layer | [03-phase2-landmark-layer.md](./03-phase2-landmark-layer.md) | not started | Landmarker wrappers (pose + hand), drawing, landmark array, distance, model manager |
| 3 - Geometry | [04-phase3-geometry.md](./04-phase3-geometry.md) | not started | Homography, coordinate geometry, signal processing boundary decision |
| 4 - Migrate consumers | [05-phase4-migrate-consumers.md](./05-phase4-migrate-consumers.md) | not started | Migrate abyss -> holo-table -> climbing-wire to depend on pose-tools |

## Phase 1 - Foundation (7 sub-tasks)

| # | Sub-task | Status | Notes |
|---|----------|--------|-------|
| 1.1 | Repo scaffolding | not started | Create pose-tools from python-project-template |
| 1.2 | Frame dataclass | not started | Unify on mp.Image-based Frame from holo-table/abyss |
| 1.3 | Video loading | not started | VideoFrameIterator + convenience generators |
| 1.4 | OpenCV display utils | not started | resize, cv_imshow, cv_imshow_rgb |
| 1.5 | Matplotlib plot utils | not started | show_frame |
| 1.6 | MediaPipe shared utils | not started | Protobuf converters, landmark constants, connections |
| 1.7 | Numpy signal utils | not started | Rolling window filters, derivatives |

## Phase 2 - Landmark layer (7 sub-tasks)

| # | Sub-task | Status | Notes |
|---|----------|--------|-------|
| 2.1 | Base landmarker pattern | not started | Protocol/ABC with detect(frame) dispatch |
| 2.2 | Pose landmarker wrapper | not started | Port from abyss, Tasks API |
| 2.3 | Hand landmarker wrapper | not started | Port from holo-table, Tasks API |
| 2.4 | Landmark drawing | not started | Unified draw for pose + hand |
| 2.5 | Landmark array (numpy) | not started | Modernize climbing-wire's LandmarkListNp/Img |
| 2.6 | Landmark distance | not started | Generic distance + pinch level computation |
| 2.7 | Model manager | not started | Config-based model path resolver |

## Phase 3 - Geometry (3 sub-tasks)

| # | Sub-task | Status | Notes |
|---|----------|--------|-------|
| 3.1 | Homography computation | not started | SIFT + RANSAC, decision: extract or leave in climbing-wire |
| 3.2 | Landmark geometry | not started | Normalized-to-pixel coordinate math |
| 3.3 | Signal processing | not started | Needs analysis: generic SignalTracker vs pinch-specific |

## Phase 4 - Migrate consumers (3 sub-tasks)

| # | Sub-task | Status | Notes |
|---|----------|--------|-------|
| 4.1 | Migrate abyss | not started | Simplest: ~9 files, already on Tasks API |
| 4.2 | Migrate holo-table | not started | Medium: ~19 files, selective replacement |
| 4.3 | Migrate climbing-wire | not started | Hardest: legacy API upgrade + custom wrappers |

# Overview of the pose/vision projects

## Current repos

**`climbing-wire`** - Pose tracking on climbing videos. MediaPipe landmarks +
OpenCV homographies to warp and overlay joint traces across frames. DTW for
video alignment.

**`holo-table`** - Air pinch-to-zoom gesture via MediaPipe hand tracking.
Client sends gesture data to a server which drives a remote display. Designed
for touchless fractal zoom demos.

**`abyss`** - 3D viewer geometry: given a viewer position and a screen position,
compute and render what the viewer sees on the screen. Uses MediaPipe pose
detection to locate the viewer.

**`pose-tools`** _(planned)_ - Installable library for pose tracking and analysis. Provides
common utilities for working with pose data, including MediaPipe integration, homography utilities.

## Overview

we want to analyze the repos in terms of:

- Functionality: what does the app do, what features does it have, what user needs does it address?
- Internal data models for pose-related concepts: what are the main data structures and models used in the app, how do they relate to the functionality? eg poses, joints, gestures, etc. Data models for users and authentication are out of scope for this analysis, we want to focus on the pose-related data models.

## Functional analysis

### climbing-wire

#### What it does

Analyzes climbing videos to visualize the climber's movement over time. Given a video of someone climbing, it draws persistent joint traces (hands, feet) on each frame so you can see the path each limb followed. It also supports aligning two climbing videos temporally so you can compare two climbers side by side.

#### Features and pipeline

1. **Landmark detection** - Runs MediaPipe Pose on each video frame to extract 33 body landmarks (normalized coordinates + visibility scores). The `PoseImg` wrapper converts raw MediaPipe results into `LandmarkListImg` objects with pixel coordinates and drawable flags.

2. **Homography-based stabilization** - Computes SIFT-based homographies between consecutive frames using OpenCV's feature matching + RANSAC. This warps previous landmark positions into the current frame's coordinate system, compensating for camera movement.

3. **Joint tracking** - `JointTracker` maintains a per-joint history (`JointHist`) of positions across frames. On each new frame, it transforms all previous joint positions using the new homography, then appends the current position. The result is a trace of each joint in the latest frame's coordinate space.

4. **DTW video alignment** - A custom FastDTW implementation (forked from `slaypni/fastdtw`) aligns two videos temporally. Homography distances between frames are used as the cost metric. This allows matching a shorter video against a longer one by repeating frames as needed.

5. **Wireframe playback** - After alignment, wireframes from both videos can be plotted in a shared reference frame for comparison.

6. **Phantom trace** _(planned)_ - Blend segmentation masks across frames to leave a ghost trail of the climber. Background stitching from segments where the person is absent.

#### Key data models

- `LandmarkListNp` - 33 pose landmarks as numpy arrays (normalized xy + visibility). Wraps MediaPipe's `NormalizedLandmarkList`.
- `LandmarkListImg(LandmarkListNp)` - Extends the above with pixel-space coordinates, image shape, visibility thresholding, and a `drawable` boolean mask. Provides `get_landmark_for_joint()` to extract specific joints (left/right hand/foot).
- `Frame` - Dataclass: `frame: np.ndarray`, `usec: int`, `idx: int`. Raw OpenCV image with timestamp.
- `JointHist` - Per-joint position history: `track: np.ndarray (Nx2)`, `visibility: np.ndarray`. Updated via homography transform + append.
- `JointTracker` - Holds a dict of `JointHist` per joint name, a `PoseImg` detector, and the current homography matrix.
- `JOINT_NAMES_TYPE` - Literal type for the four tracked joints: `left_hand`, `right_hand`, `left_foot`, `right_foot`.

#### Dependencies

Python 3.11, MediaPipe (legacy solutions API: `mp.solutions.pose`), OpenCV (SIFT, FLANN, homography, perspective transform), numpy, scipy, fastdtw (vendored), matplotlib, loguru, tqdm, pandas.

#### Entry points

Notebook-driven. Seven Jupyter notebooks under `notebooks/` covering video loading, joint tracking, homography, limb tracking, wireframe detection, and DTW matching. No CLI or app entry point.

---

### holo-table

#### What it does

Real-time pinch-to-zoom gesture control over a network. A client captures webcam video, detects hand landmarks with MediaPipe, computes a pinch distance (thumb tip to index finger tip), and sends the gesture data via UDP to a remote server. The server receives the stream and either plots it live (matplotlib animation or Streamlit+Plotly) or could drive a zoom level on a display (e.g. a fractal viewer).

#### Features and pipeline

1. **Hand landmark detection** - Uses MediaPipe's Tasks API (`HandLandmarker`) in VIDEO mode. The `HandLandmarkerFrame` wrapper accepts `Frame` objects and returns `HandLandmarkerResult` with per-hand world and normalized landmarks.

2. **Pinch level computation** - `compute_pinch_level()` measures the distance between `THUMB_TIP` and `INDEX_FINGER_TIP` in world coordinates, normalized by the wrist-to-index-MCP distance. This gives a scale-invariant pinch metric.

3. **Signal processing / pinch tracker** - `PinchTracker` applies a rolling triangle-weighted smoothing filter to the pinch distance time series. It computes first and second derivatives (also smoothed), and classifies a frame as "pinching" when the first derivative is within a controlled range and the second derivative is small (smooth, intentional movement, not noise or jerks).

4. **Network transport** - `UdpSocketSender` / `UdpSocketReceiver` provide a simple UDP socket layer. Payloads are JSON-encoded dicts with `pinch_level`, `pos_msec`, and optionally `dist_thumb_index`.

5. **Two frontend options**:
   - **GUI (OpenCV)**: `gui_sender` captures webcam, detects landmarks, draws annotations, sends data. `gui_receiver` receives data and plots it with matplotlib's `FuncAnimation`.
   - **Streamlit (WebRTC)**: `streamlit_sender` uses `streamlit-webrtc` for browser-based webcam capture. `streamlit_receiver` receives data and renders live Plotly charts with distance, first/second derivatives, and pinch detection state.

#### Key data models

- `Frame` - Dataclass: `image: mp.Image`, `msec: float`, `idx: int`. Wraps a MediaPipe Image (RGB). Factory methods: `from_np_array()`, `from_opencv()`, `from_file()`. Converts to/from OpenCV BGR.
- `PinchTracker` - Stateful tracker holding rolling numpy arrays for: raw distance, smoothed distance, first derivative (+ smoothed), second derivative (+ smoothed). Thresholds `sd_max`, `sd_min`, `sdsd_max` control pinch detection. Also stores full history lists for plotting.
- `UdpSocketSender` / `UdpSocketReceiver` - Socket wrappers with context manager support.
- `Sender` / `Receiver` - Application-level classes that compose landmark detection, pinch computation, socket transport, and visualization.
- MediaPipe's `Landmark`, `NormalizedLandmark`, `HandLandmarkerResult` are used directly (no custom landmark wrapper).

#### Dependencies

Python 3.11, MediaPipe (Tasks API: `HandLandmarker`), OpenCV, numpy, matplotlib, click, streamlit, streamlit-webrtc, plotly, loguru, pandas.

#### Entry points

- CLI: `gui_sender` and `gui_receiver` (click commands, registered as poetry scripts).
- Streamlit: `streamlit_sender` and `streamlit_receiver` (run with `streamlit run`).
- Notebooks: `landmarker_01.ipynb` (hand detection exploration), `pinch_01.ipynb` (pinch tracking exploration).

---

### abyss

#### What it does

Determines the viewer's real-world position using MediaPipe pose detection (from a webcam or video), with the eventual goal of rendering a perspective-correct scene on a screen based on where the viewer is standing. Currently implements the pose detection and visualization layer; the 3D geometry/rendering step is planned.

#### Features and pipeline

1. **Pose landmark detection** - Uses MediaPipe's Tasks API (`PoseLandmarker`) in either IMAGE or VIDEO mode. The `PoseLandmarkerFrame` wrapper dispatches to `detect()` or `detect_for_video()` based on the configured running mode.

2. **Landmark drawing** - `draw_landmarks()` extracts normalized landmarks from a `PoseLandmarkerResult`, converts them to a protobuf `NormalizedLandmarkList`, and draws using MediaPipe's built-in drawing utilities with default pose styles.

3. **Video frame iteration** - `VideoFrameIterator` is a context-managed iterator that reads frames from a file or camera, supports frame skipping (`keep_every_nth_frame`), frame count limits, and yields `Frame` objects.

4. **Resource/model management** - `get_resource()` resolves paths to MediaPipe model files (`~/.mediapipe/models/pose_landmarker.task`) and data folders.

#### Key data models

- `Frame` - Dataclass: `image: mp.Image`, `msec: float`, `idx: int`. Same structure as holo-table's Frame (essentially identical code). Factory methods: `from_np_array()`, `from_opencv()`, `from_file()`.
- `PoseLandmarkerFrame` - Wrapper around MediaPipe's `PoseLandmarker` that accepts `Frame` objects and auto-dispatches based on running mode.
- `VideoFrameIterator` - Context-managed video reader class with `__iter__` yielding `Frame` objects. Tracks `feed_count` and `yield_count`.
- MediaPipe's `Landmark`, `NormalizedLandmark`, `PoseLandmarkerResult` are used directly.

#### Dependencies

Python 3.11, MediaPipe (Tasks API: `PoseLandmarker`), numpy, loguru.

#### Entry points

Notebook-driven. One notebook `sample01.ipynb`. No CLI entry point.

---

## Common components

### Duplicated code across repos

The three repos share a significant amount of copy-pasted code with minor variations:

| Component | climbing-wire | holo-table | abyss |
|---|---|---|---|
| **Frame dataclass** | `video/frame.py` - bare numpy + usec | `video/frame.py` - mp.Image + msec + factories | `video/frame.py` - mp.Image + msec + factories (identical to holo-table) |
| **Video loading** | `video/load.py` - generator functions | `video/load.py` - generator + list functions | `video/load.py` - `VideoFrameIterator` class + list function |
| **MediaPipe utils** | `utils/mediapipe.py` - pose landmarks, `get_spec_from_map`, connections | `utils/mediapipe.py` - hand landmarks, `get_spec_from_map`, connections, result extraction, protobuf conversion | `utils/mediapipe.py` - pose landmarks, `get_spec_from_map`, connections, result extraction, protobuf conversion |
| **CV display utils** | `utils/cv.py` - `cv_imshow`, `resize`, `show_frame`, `show_warp` | `utils/cv.py` - `cv_imshow`, `resize`, `cv_imshow_rgb` | `utils/cv.py` - `resize`, `cv_imshow_rgb` |
| **Plotting utils** | integrated in cv.py | `utils/plt.py` - `show_frame` | `utils/plt.py` - `show_frame` (identical to holo-table) |
| **Data/resource paths** | `utils/data.py` - `get_package_fol` | `utils/data.py` - `get_resource` | `utils/data.py` - `get_resource` |
| **Landmark drawing** | `landmark/drawing.py` - custom implementation | `landmark/drawing.py` - uses mp drawing utils | `landmarker/drawing.py` - uses mp drawing utils |
| **Landmark compute** | `landmark/compute.py` - legacy `mp.solutions.pose` | `landmark/compute.py` - Tasks API `HandLandmarker` | `landmarker/pose.py` - Tasks API `PoseLandmarker` |

### Key differences and inconsistencies

1. **MediaPipe API generation** - climbing-wire uses the legacy Solutions API (`mp.solutions.pose.Pose`), while holo-table and abyss use the newer Tasks API (`HandLandmarker`, `PoseLandmarker`).

2. **Frame representation** - climbing-wire stores raw numpy arrays + microsecond timestamps. holo-table and abyss wrap a `MediaPipe Image` + millisecond timestamps. The holo-table/abyss Frame classes are essentially identical but independently maintained.

3. **Landmark abstraction level** - climbing-wire has a rich custom `LandmarkListNp` / `LandmarkListImg` hierarchy with numpy-based visibility masking, drawable flags, and pixel coordinate conversion. holo-table and abyss use MediaPipe's result objects directly without a custom wrapper.

4. **Result extraction** - holo-table and abyss both have `get_landmarks_from_result()` and `list_land_to_landlist()` functions, but specialize for hand vs pose respectively. Same pattern, different landmark types.

5. **Naming** - climbing-wire uses `landmark/`, holo-table uses `landmark/`, abyss uses `landmarker/`. The compute wrapper is `PoseImg` in climbing-wire, `HandLandmarkerFrame` in holo-table, `PoseLandmarkerFrame` in abyss.

### What belongs in pose-tools

The following components are candidates for extraction into the shared `pose-tools` library:

**Tier 1 - Direct extraction (identical or near-identical across repos)**

- `Frame` dataclass with mp.Image wrapping, factory methods, and timestamp. Unify on the holo-table/abyss version (mp.Image-based), with both msec and usec support.
- `VideoFrameIterator` / video loading utilities. Unify on abyss's context-managed class, which is the most mature version.
- `cv_imshow`, `resize`, `cv_imshow_rgb` display utilities.
- `show_frame` plotting helper.
- `get_spec_from_map` MediaPipe drawing spec helper.
- `get_default_pose_connections` / `get_default_hand_connections`.
- `list_land_to_landlist` protobuf conversion (generalized for both hand and pose).
- `get_landmarks_from_result` (generalized for both `HandLandmarkerResult` and `PoseLandmarkerResult`).

**Tier 2 - Refactor and extract (needs generalization)**

- Landmarker wrappers: unify `HandLandmarkerFrame` and `PoseLandmarkerFrame` into a common pattern, possibly a generic `LandmarkerFrame[ResultT]` or just a shared base with `detect(frame)` dispatching on running mode.
- `LandmarkListImg` from climbing-wire: the numpy-based landmark wrapper with visibility masking and pixel coordinate conversion. Useful beyond climbing, but needs updating to work with the Tasks API instead of the legacy Solutions API.
- Landmark drawing: provide a single `draw_landmarks()` that works for both pose and hand results.
- Resource/model path management: unify `get_resource()` into a config-based approach that knows about all model types.

**Tier 3 - Domain-specific (stay in their repo, but depend on pose-tools)**

- `JointTracker` / `JointHist` - climbing-specific joint history tracking with homography warping.
- `PinchTracker` - holo-table-specific gesture classification with signal processing.
- Homography computation and perspective transforms - could go in pose-tools as a general utility, or stay in climbing-wire.
- FastDTW - general purpose, but only used by climbing-wire for video alignment.
- UDP socket transport - not pose-related at all, stays in holo-table.

### Roadmap to unification

**Phase 1 - Foundation**

Create `pose-tools` with the core shared types:

- `pose_tools.video.frame.Frame` - unified frame dataclass
- `pose_tools.video.load` - `VideoFrameIterator`, `list_video_frames`, `iterate_video_frames`
- `pose_tools.utils.cv` - OpenCV display helpers
- `pose_tools.utils.plt` - matplotlib plotting helpers
- `pose_tools.utils.mediapipe` - shared MediaPipe utilities (connections, spec helpers, protobuf converters, result extractors)

**Phase 2 - Landmark layer**

- `pose_tools.landmark.base` - abstract landmarker wrapper with `detect(frame)` pattern
- `pose_tools.landmark.pose` - `PoseLandmarkerFrame` using Tasks API
- `pose_tools.landmark.hand` - `HandLandmarkerFrame` using Tasks API
- `pose_tools.landmark.drawing` - unified drawing that works with both pose and hand results
- `pose_tools.landmark.landmark_array` - modernized version of `LandmarkListImg` working with Tasks API results. Numpy-based landmark arrays with visibility masking, pixel coordinate conversion, and drawable flags.
- `pose_tools.landmark.model_manager` - resolve and download MediaPipe model files

**Phase 3 - Geometry utilities**

- `pose_tools.geometry.homography` - SIFT-based homography, perspective transforms
- `pose_tools.geometry.distance` - landmark distance computation (used by both pinch detection and potential climbing analysis)

**Phase 4 - Migrate consumers**

- Update climbing-wire to depend on `pose-tools`, remove duplicated code, migrate from legacy Solutions API to Tasks API
- Update holo-table to depend on `pose-tools`, remove duplicated code
- Update abyss to depend on `pose-tools`, remove duplicated code
- Each repo keeps only its domain-specific logic (joint tracking, pinch tracking, 3D projection)

"""
Physics Proxies Extraction for Ragi Moisture & Quality Assessment
===================================================================

Extracts single-image optical proxies for moisture detection and quality grading:
  - Texture Entropy: Shannon entropy of surface micro-roughness
  - LAB Color Shifts: Moisture absorption via CIE-LAB darkening
  - Capillary Clumping: Connected-component analysis for wet grain clustering
  
No multi-image fusion. All features derived from single, diffused-light image.

Author: Copilot
Date: 2026-04-29
"""

import cv2
import numpy as np
from pathlib import Path
from scipy import ndimage
from scipy.stats import entropy
from scipy.signal import find_peaks
from typing import Dict, Tuple, List, Any, Optional, Union
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


ImageInput = Union[str, Path, np.ndarray]


def _get_aruco_detector(aruco_module: Any, dictionary: Any) -> Tuple[Any, Any]:
    """
    Build an ArUco detector across OpenCV API variants.

    OpenCV 4.7+ exposes cv2.aruco.ArucoDetector, while older contrib builds use
    the module-level detectMarkers function. Returning both the detector object
    and parameters keeps flatten_perspective compatible with either wheel.
    """
    try:
        parameters = (
            aruco_module.DetectorParameters_create()
            if hasattr(aruco_module, "DetectorParameters_create")
            else aruco_module.DetectorParameters()
        )
    except Exception:
        parameters = None

    if hasattr(aruco_module, "ArucoDetector") and parameters is not None:
        return aruco_module.ArucoDetector(dictionary, parameters), parameters
    return None, parameters


def _detect_required_aruco_markers(
    gray: np.ndarray,
    required_ids: Tuple[int, int, int, int],
) -> Dict[int, np.ndarray]:
    """
    Detect the requested ArUco IDs and return their 4-corner quadrilaterals.

    The v3.2 sheet is expected to use IDs 0, 1, 2, 3. The detector tries common
    small marker dictionaries because older calibration sheet revisions in this
    project have used different ArUco families. A dictionary only wins when it
    can see all required IDs.
    """
    aruco = getattr(cv2, "aruco", None)
    if aruco is None:
        logger.warning("Perspective flatten skipped: cv2.aruco is unavailable in this OpenCV build.")
        return {}

    dictionary_names = ("DICT_4X4_50", "DICT_5X5_50", "DICT_6X6_50")
    required_set = set(required_ids)

    for dictionary_name in dictionary_names:
        if not hasattr(aruco, dictionary_name):
            continue

        try:
            dictionary_id = getattr(aruco, dictionary_name)
            dictionary = (
                aruco.getPredefinedDictionary(dictionary_id)
                if hasattr(aruco, "getPredefinedDictionary")
                else aruco.Dictionary_get(dictionary_id)
            )
            detector, parameters = _get_aruco_detector(aruco, dictionary)
            if detector is not None:
                corners, ids, _rejected = detector.detectMarkers(gray)
            else:
                corners, ids, _rejected = aruco.detectMarkers(gray, dictionary, parameters=parameters)
        except Exception as exc:
            logger.debug("ArUco detection failed for %s: %s", dictionary_name, exc)
            continue

        if ids is None or len(corners) == 0:
            continue

        flat_ids = ids.reshape(-1).astype(int)
        marker_corners: Dict[int, np.ndarray] = {}
        marker_areas: Dict[int, float] = {}
        for marker_id, marker_corner in zip(flat_ids, corners):
            if int(marker_id) not in required_set:
                continue
            quad = np.asarray(marker_corner, dtype=np.float32).reshape(4, 2)
            area = abs(float(cv2.contourArea(quad)))
            if int(marker_id) not in marker_areas or area > marker_areas[int(marker_id)]:
                marker_corners[int(marker_id)] = quad
                marker_areas[int(marker_id)] = area

        if required_set.issubset(marker_corners.keys()):
            logger.debug("Detected v3.2 calibration markers with %s.", dictionary_name)
            return marker_corners

    return {}


def flatten_perspective(image_path_or_array: ImageInput) -> np.ndarray:
    """
    Rectify an A4 v3.2 calibration-sheet photo to a top-down view.

    Expected sheet layout:
      - ID 0: top-left corner
      - ID 1: top-right corner
      - ID 2: bottom-right corner
      - ID 3: bottom-left corner

    The output canvas is mathematically constrained to the A4 portrait ratio:
    width:height = 1:sqrt(2), approximately 1:1.414. If any required marker is
    missing, the function logs a warning and returns the original image array so
    the app can continue with non-rectified analysis.

    Args:
        image_path_or_array: Path readable by cv2.imread, or an already-loaded
            OpenCV/NumPy image array. Path input returns a BGR image because
            cv2.imread returns BGR; array input keeps the caller's channel order.

    Returns:
        A warped np.ndarray when all four markers are detected, otherwise the
        original image array.
    """
    if isinstance(image_path_or_array, (str, Path)):
        image = cv2.imread(str(image_path_or_array), cv2.IMREAD_COLOR)
        if image is None:
            raise ValueError(f"Failed to read image for perspective flattening: {image_path_or_array}")
    elif isinstance(image_path_or_array, np.ndarray):
        image = image_path_or_array
    else:
        raise TypeError("flatten_perspective expects a filesystem path or a NumPy image array.")

    if image.ndim not in (2, 3) or image.size == 0:
        logger.warning("Perspective flatten skipped: input image is empty or has unsupported shape.")
        return image

    gray = image if image.ndim == 2 else cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    required_ids = (0, 1, 2, 3)
    marker_corners = _detect_required_aruco_markers(gray, required_ids)
    if len(marker_corners) < 4:
        detected = sorted(marker_corners.keys())
        logger.warning(
            "Perspective flatten skipped: detected %d/4 required ArUco markers. "
            "Need IDs [0, 1, 2, 3], detected %s.",
            len(marker_corners),
            detected,
        )
        return image

    # Use the marker corner farthest from the sheet center as the physical page
    # corner. This is more rotation-tolerant than assuming marker corner order,
    # and it works when users rotate the A4 sheet in the camera frame.
    marker_centers = np.stack([marker_corners[marker_id].mean(axis=0) for marker_id in required_ids])
    sheet_center = marker_centers.mean(axis=0)
    source_points = []
    for marker_id in required_ids:
        quad = marker_corners[marker_id]
        outward_corner = quad[np.argmax(np.linalg.norm(quad - sheet_center, axis=1))]
        source_points.append(outward_corner)
    src = np.asarray(source_points, dtype=np.float32)

    if abs(float(cv2.contourArea(src))) < 100.0:
        logger.warning("Perspective flatten skipped: detected marker geometry is degenerate.")
        return image

    top_width = float(np.linalg.norm(src[1] - src[0]))
    bottom_width = float(np.linalg.norm(src[2] - src[3]))
    left_height = float(np.linalg.norm(src[3] - src[0]))
    right_height = float(np.linalg.norm(src[2] - src[1]))

    a4_height_to_width = np.sqrt(2.0)
    observed_width = max(top_width, bottom_width, 1.0)
    observed_height = max(left_height, right_height, 1.0)
    target_width = int(round(max(observed_width, observed_height / a4_height_to_width)))
    target_height = int(round(target_width * a4_height_to_width))

    if target_width < 2 or target_height < 2:
        logger.warning("Perspective flatten skipped: destination canvas would be too small.")
        return image

    dst = np.array(
        [
            [0.0, 0.0],
            [float(target_width - 1), 0.0],
            [float(target_width - 1), float(target_height - 1)],
            [0.0, float(target_height - 1)],
        ],
        dtype=np.float32,
    )

    matrix = cv2.getPerspectiveTransform(src, dst)
    return cv2.warpPerspective(
        image,
        matrix,
        (target_width, target_height),
        flags=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_REPLICATE,
    )


class PhysicsProxiesExtractor:
    """
    Lightweight OpenCV-based feature extraction for ragi grain analysis.
    Designed for edge inference on low-end devices.
    """

    def __init__(self, grain_mask_threshold: int = 50, morph_kernel_size: int = 5):
        """
        Args:
            grain_mask_threshold: Binary threshold for grain region detection
            morph_kernel_size: Morphological kernel size for cleaning
        """
        self.grain_mask_threshold = grain_mask_threshold
        self.morph_kernel = cv2.getStructuringElement(
            cv2.MORPH_ELLIPSE, (morph_kernel_size, morph_kernel_size)
        )

    def extract_all_proxies(self, image_path: str) -> Dict[str, Any]:
        """
        End-to-end extraction pipeline.
        
        Args:
            image_path: Path to grain image (diffused lighting)
            
        Returns:
            Dictionary with all physics proxies and metadata
        """
        try:
            img = cv2.imread(image_path)
            if img is None:
                raise ValueError(f"Failed to read image: {image_path}")

            img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            h, w = img_rgb.shape[:2]

            logger.info(f"Processing image: {image_path} ({w}x{h})")

            # 1. Create grain mask (conservative segmentation)
            grain_mask = self._segment_grain_region(img_rgb)

            # 2. Extract texture entropy
            texture_entropy = self._compute_texture_entropy(img_rgb, grain_mask)

            # 3. Extract LAB color features (moisture proxy)
            lab_features = self._extract_lab_features(img_rgb, grain_mask)

            # 4. Detect capillary clumping (wet grain clustering)
            clumping_density = self._compute_clumping_density(img_rgb, grain_mask)

            # 5. Surface roughness (Laplacian variance)
            roughness_score = self._compute_surface_roughness(img_rgb, grain_mask)

            # 6. Specular highlights ratio (flash/moisture indicator)
            specular_ratio = self._compute_specular_highlights(img_rgb, grain_mask)

            # 7. Grain uniformity (color distribution)
            uniformity_score = self._compute_uniformity(img_rgb, grain_mask)

            capture_distance_cm, capture_distance_source = self._estimate_capture_distance_cm(img_rgb)
            calibration = self._estimate_calibration(img_rgb)
            sample_field = self._detect_sample_field(img_rgb)
            if sample_field is None:
                sample_field = self._infer_sample_field_from_grain_mask(grain_mask, img_rgb)
            calibrated_geometry = self._compute_calibrated_grain_geometry(
                grain_mask,
                calibration,
                sample_field,
            )
            physical_properties = self._compute_physical_properties(
                img_rgb,
                grain_mask,
                calibration,
                sample_field,
            )
            grid_box_analysis = self._analyze_grid_boxes(
                img_rgb,
                grain_mask,
                calibration,
                sample_field,
            )

            result = {
                "image_path": image_path,
                "image_size": {"width": w, "height": h},
                "capture_distance_estimate_cm": capture_distance_cm,
                "capture_distance_source": capture_distance_source,
                "calibration": calibration,
                "sample_field": sample_field,
                "grain_mask_coverage": float(np.sum(grain_mask) / grain_mask.size),
                "texture_entropy": float(texture_entropy),
                "lab_features": {
                    "l_mean": float(lab_features["l_mean"]),
                    "l_std": float(lab_features["l_std"]),
                    "a_mean": float(lab_features["a_mean"]),
                    "b_mean": float(lab_features["b_mean"]),
                    "color_darkness_index": float(
                        lab_features["color_darkness_index"]
                    ),  # Higher = darker (moisture indicator)
                },
                "clumping": {
                    "density": float(clumping_density["density"]),
                    "cluster_count": int(clumping_density["cluster_count"]),
                    "avg_cluster_size": float(clumping_density["avg_cluster_size"]),
                },
                "roughness_score": float(roughness_score),
                "specular_highlights_ratio": float(specular_ratio),
                "uniformity_score": float(uniformity_score),
                "calibrated_geometry": calibrated_geometry,
                "physical_properties": physical_properties,
                "grid_box_analysis": grid_box_analysis,
            }

            logger.info(f"✓ Extraction complete. Entropy: {texture_entropy:.3f}")
            return result

        except Exception as e:
            logger.error(f"Error in proxy extraction: {e}")
            raise

    def _estimate_capture_distance_cm(self, img_rgb: np.ndarray) -> Tuple[Optional[float], str]:
        """
        Estimate capture distance from an ArUco marker when present.

        Falls back to a square calibration marker contour when the OpenCV ArUco
        module is unavailable or the marker cannot be decoded. This is an
        approximate optical estimate intended for UI metadata, not metrology.
        """
        aruco = getattr(cv2, "aruco", None)
        if aruco is not None:
            distance = self._estimate_capture_distance_with_aruco(img_rgb, aruco)
            if distance is not None:
                return distance, "aruco"

        try:
            distance = self._estimate_capture_distance_from_square_marker(img_rgb)
            if distance is not None:
                return distance, "marker"
        except Exception as e:
            logger.debug(f"ArUco distance estimate failed: {e}")

        return None, "auto"

    def _estimate_capture_distance_with_aruco(
        self, img_rgb: np.ndarray, aruco_module: Any
    ) -> Optional[float]:
        gray = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2GRAY)
        dictionary = None
        dict_names = ["DICT_4X4_50", "DICT_5X5_50", "DICT_6X6_50"]
        for dict_name in dict_names:
            if hasattr(aruco_module, dict_name):
                try:
                    marker_dict = getattr(aruco_module, dict_name)
                    if hasattr(aruco_module, "getPredefinedDictionary"):
                        dictionary = aruco_module.getPredefinedDictionary(marker_dict)
                    elif hasattr(aruco_module, "Dictionary_get"):
                        dictionary = aruco_module.Dictionary_get(marker_dict)
                    break
                except Exception:
                    dictionary = None
        if dictionary is None:
            return None

        try:
            if hasattr(aruco_module, "DetectorParameters_create"):
                parameters = aruco_module.DetectorParameters_create()
            else:
                parameters = aruco_module.DetectorParameters()
        except Exception:
            parameters = None

        try:
            if hasattr(aruco_module, "ArucoDetector") and parameters is not None:
                detector = aruco_module.ArucoDetector(dictionary, parameters)
                corners, ids, _ = detector.detectMarkers(gray)
            else:
                corners, ids, _ = aruco_module.detectMarkers(gray, dictionary, parameters=parameters)
        except Exception:
            return None

        if ids is None or len(corners) == 0:
            return None

        marker_px = float(cv2.arcLength(corners[0][0], True) / 4.0)
        if marker_px <= 0:
            return None

        marker_size_cm = 5.0
        nominal_focal_px = max(img_rgb.shape[1], img_rgb.shape[0]) * 1.35
        distance_cm = (marker_size_cm * nominal_focal_px) / marker_px
        return round(float(distance_cm), 1)

    def _estimate_capture_distance_from_square_marker(self, img_rgb: np.ndarray) -> Optional[float]:
        gray = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edges = cv2.Canny(blurred, 50, 150)
        contours_info = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
        contours = contours_info[0] if len(contours_info) == 2 else contours_info[1]

        if not contours:
            return None

        img_area = float(img_rgb.shape[0] * img_rgb.shape[1])
        best_side_px = None
        best_score = 0.0

        for contour in contours:
            area = cv2.contourArea(contour)
            if area < img_area * 0.01 or area > img_area * 0.45:
                continue

            peri = cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, 0.04 * peri, True)
            if len(approx) != 4 or not cv2.isContourConvex(approx):
                continue

            xs = approx[:, 0, 0].astype(float)
            ys = approx[:, 0, 1].astype(float)
            width = float(np.max(xs) - np.min(xs))
            height = float(np.max(ys) - np.min(ys))
            if width <= 0 or height <= 0:
                continue

            aspect = max(width, height) / (min(width, height) + 1e-6)
            if aspect > 1.2:
                continue

            solidity = area / (width * height + 1e-6)
            score = area * solidity
            if score > best_score:
                best_score = score
                best_side_px = (width + height) / 2.0

        if best_side_px is None:
            return None

        marker_size_cm = 5.0
        nominal_focal_px = max(img_rgb.shape[1], img_rgb.shape[0]) * 1.35
        distance_cm = (marker_size_cm * nominal_focal_px) / best_side_px
        return round(float(distance_cm), 1)

    def _estimate_calibration(self, img_rgb: np.ndarray) -> Dict[str, Any]:
        """
        Estimate a scale calibration from the printed grid sheet.

        The extractor supports both current calibration sheets:
          - Sheet 1: white precision sheet with a 100 mm active grain zone.
          - Sheet 2: blue grading sheet with 4x4 ArUco corner markers.
        """
        page = self._detect_paper_region(img_rgb)
        calibration = {
            "available": False,
            "sheet_detected": False,
            "reference_patch_detected": False,
            "marker_count": 0,
            "source": "none",
            "pixels_per_mm": None,
            "mm_per_pixel": None,
            "grid_spacing_mm": None,
            "grid_spacing_px": None,
            "grid_spacing_vertical_px": None,
            "grid_spacing_horizontal_px": None,
            "grid_confidence": 0.0,
            "sheet_style": "unknown",
            "calibration_reference": "none",
        }

        if page is None:
            return calibration

        warped = page["warped"]
        calibration["sheet_detected"] = True
        calibration["marker_count"] = int(page.get("marker_count", 0))
        calibration["source"] = page.get("source", "sheet")
        calibration["sheet_style"] = page.get("sheet_style", "unknown")
        calibration["reference_patch_detected"] = bool(
            self._detect_reference_patch(warped)
        )

        active_scale = self._estimate_active_zone_scale(img_rgb)
        if active_scale is not None:
            pixels_per_mm = active_scale["pixels_per_mm"]
            calibration["available"] = True
            calibration["pixels_per_mm"] = round(float(pixels_per_mm), 3)
            calibration["mm_per_pixel"] = round(1.0 / float(pixels_per_mm), 5)
            calibration["grid_spacing_mm"] = 10.0
            calibration["grid_spacing_px"] = round(float(pixels_per_mm) * 10.0, 2)
            calibration["grid_spacing_vertical_px"] = round(
                float(active_scale["height_px"]) / 10.0, 2
            )
            calibration["grid_spacing_horizontal_px"] = round(
                float(active_scale["width_px"]) / 10.0, 2
            )
            calibration["grid_confidence"] = round(
                float(np.clip(0.78 + min(0.2, calibration["marker_count"] * 0.04), 0.0, 1.0)),
                3,
            )
            calibration["source"] = (
                "aruco-active-zone"
                if calibration["marker_count"] >= 4
                else "active-zone"
            )
            calibration["sheet_style"] = "precision-white"
            calibration["calibration_reference"] = "100mm-active-grain-zone"
            return calibration

        if page.get("sheet_style") == "blue-grading":
            blue_grid = self._measure_blue_grid_calibration(warped)
            if blue_grid is not None:
                marker_bonus = min(0.25, calibration["marker_count"] * 0.05)
                calibration["available"] = True
                calibration["pixels_per_mm"] = round(float(blue_grid["pixels_per_mm"]), 3)
                calibration["mm_per_pixel"] = round(
                    1.0 / float(blue_grid["pixels_per_mm"]), 5
                )
                calibration["grid_spacing_mm"] = float(blue_grid["grid_spacing_mm"])
                calibration["grid_spacing_px"] = round(float(blue_grid["grid_spacing_px"]), 2)
                calibration["grid_spacing_vertical_px"] = round(
                    float(blue_grid["grid_spacing_vertical_px"]), 2
                )
                calibration["grid_spacing_horizontal_px"] = round(
                    float(blue_grid["grid_spacing_horizontal_px"]), 2
                )
                calibration["grid_confidence"] = round(
                    float(np.clip(blue_grid["confidence"] + marker_bonus, 0.0, 1.0)),
                    3,
                )
                calibration["source"] = (
                    "aruco-blue-grid"
                    if calibration["marker_count"] >= 4
                    else "blue-grid"
                )
                calibration["calibration_reference"] = "blue-sheet-3mm-grid"
                return calibration

        spacing_v, spacing_h, spacing_conf = self._measure_grid_spacing(warped)
        spacing_values = [value for value in [spacing_v, spacing_h] if value is not None]
        if spacing_values:
            grid_spacing_px = float(np.median(spacing_values))
            grid_spacing_mm = 10.0 if grid_spacing_px >= 8.0 else 1.0
            pixels_per_mm = grid_spacing_px / grid_spacing_mm
            calibration["available"] = True
            calibration["pixels_per_mm"] = round(pixels_per_mm, 3)
            calibration["mm_per_pixel"] = round(grid_spacing_mm / grid_spacing_px, 5)
            calibration["grid_spacing_mm"] = grid_spacing_mm
            calibration["grid_spacing_px"] = round(grid_spacing_px, 2)
            calibration["grid_spacing_vertical_px"] = (
                round(float(spacing_v), 2) if spacing_v is not None else None
            )
            calibration["grid_spacing_horizontal_px"] = (
                round(float(spacing_h), 2) if spacing_h is not None else None
            )
            marker_bonus = min(0.25, calibration["marker_count"] * 0.05)
            patch_bonus = 0.15 if calibration["reference_patch_detected"] else 0.0
            calibration["grid_confidence"] = round(
                float(np.clip(spacing_conf + marker_bonus + patch_bonus, 0.0, 1.0)),
                3,
            )
            if calibration["marker_count"] >= 4:
                calibration["source"] = "aruco-grid"
            elif calibration["marker_count"] > 0:
                calibration["source"] = "marker-grid"
            else:
                calibration["source"] = "grid-only"
            calibration["calibration_reference"] = "detected-grid-lines"

        return calibration

    def _estimate_active_zone_scale(self, img_rgb: np.ndarray) -> Optional[Dict[str, float]]:
        """
        Sheet 1 prints a 100 mm x 100 mm blue active grain zone.
        When visible, this is a stronger local scale reference than measuring
        grid lines through perspective and grain occlusion.
        """
        sample_box = self._detect_blue_sample_box(img_rgb)
        if sample_box is None or sample_box.get("source") != "active-zone-box":
            return None

        x, y, w, h = sample_box["bbox"]
        img_area = float(img_rgb.shape[0] * img_rgb.shape[1])
        box_area = float(w * h)
        aspect = w / float(h + 1e-6)
        if not (0.75 <= aspect <= 1.35):
            return None
        if box_area < img_area * 0.04 or box_area > img_area * 0.45:
            return None

        pixels_per_mm = ((float(w) + float(h)) / 2.0) / 100.0
        if pixels_per_mm <= 0:
            return None
        return {
            "pixels_per_mm": float(pixels_per_mm),
            "width_px": float(w),
            "height_px": float(h),
            "x": float(x),
            "y": float(y),
        }

    def _detect_blue_sample_box(self, img_rgb: np.ndarray) -> Optional[Dict[str, Any]]:
        """
        Detect the printed blue active-zone rectangle on Sheet 1, or the large
        blue grid field on Sheet 2.
        """
        hsv = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2HSV)
        mask = cv2.inRange(
            hsv,
            np.array([92, 35, 35], dtype=np.uint8),
            np.array([140, 255, 255], dtype=np.uint8),
        )
        mask = cv2.morphologyEx(
            mask,
            cv2.MORPH_CLOSE,
            cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9)),
        )

        contours_info = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contours = contours_info[0] if len(contours_info) == 2 else contours_info[1]
        if not contours:
            return None

        img_h, img_w = mask.shape[:2]
        img_area = float(img_h * img_w)
        candidates = []
        for contour in contours:
            area = cv2.contourArea(contour)
            if area < img_area * 0.02:
                continue
            peri = cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, 0.035 * peri, True)
            x, y, w, h = cv2.boundingRect(contour)
            aspect = w / float(h + 1e-6)
            fill = area / float(w * h + 1e-6)
            score = area
            if 0.75 <= aspect <= 1.35:
                score *= 1.3
            if len(approx) == 4:
                score *= 1.2
            if fill > 0.35:
                score *= 1.05
            candidates.append((score, area, x, y, w, h, aspect))

        if not candidates:
            return None

        _, area, x, y, w, h, aspect = max(candidates, key=lambda item: item[0])
        source = "active-zone-box"
        if area > img_area * 0.55 or aspect < 0.6 or aspect > 1.6:
            source = "blue-grid-field"
            grid_bbox = self._detect_blue_grid_bbox(img_rgb)
            if grid_bbox is not None:
                x, y, w, h = grid_bbox

        return {
            "bbox": (int(x), int(y), int(w), int(h)),
            "area_px": float(max(1, w * h)),
            "source": source,
        }

    def _detect_blue_grid_bbox(self, img_rgb: np.ndarray) -> Optional[Tuple[int, int, int, int]]:
        """
        Locate Sheet 2's white grid inside the blue field.
        """
        hsv = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2HSV)
        white_mask = ((hsv[:, :, 1] < 90) & (hsv[:, :, 2] > 125)).astype(np.uint8)
        h, w = white_mask.shape[:2]
        x0, x1 = int(w * 0.04), int(w * 0.96)
        y0, y1 = int(h * 0.08), int(h * 0.96)
        roi = white_mask[y0:y1, x0:x1]
        if roi.size == 0:
            return None

        col_density = np.mean(roi > 0, axis=0)
        row_density = np.mean(roi > 0, axis=1)
        x_span = self._regular_peak_span(col_density, min_spacing=5)
        y_span = self._regular_peak_span(row_density, min_spacing=5)
        if x_span is None or y_span is None:
            return None

        x_a, x_b = x_span
        y_a, y_b = y_span
        bw = int(max(1, x_b - x_a))
        bh = int(max(1, y_b - y_a))
        if bw * bh < float(h * w) * 0.20:
            return None
        return (int(x0 + x_a), int(y0 + y_a), bw, bh)

    def _regular_peak_span(
        self,
        density: np.ndarray,
        min_spacing: int = 4,
    ) -> Optional[Tuple[int, int]]:
        if density.size < 20:
            return None

        prominence = max(0.01, float(np.std(density) * 0.30))
        peaks, _ = find_peaks(density, prominence=prominence, distance=min_spacing)
        if len(peaks) < 6:
            return None

        # Keep the longest run of mostly regular grid peaks, ignoring text,
        # labels, and ruler graphics near the sheet edges.
        best_run: List[int] = []
        current: List[int] = [int(peaks[0])]
        for prev, nxt in zip(peaks[:-1], peaks[1:]):
            gap = int(nxt - prev)
            if min_spacing <= gap <= max(28, int(density.size * 0.035)):
                current.append(int(nxt))
            else:
                if len(current) > len(best_run):
                    best_run = current
                current = [int(nxt)]
        if len(current) > len(best_run):
            best_run = current

        if len(best_run) < 6:
            return None

        return (int(best_run[0]), int(best_run[-1]))

    def _measure_blue_grid_calibration(self, warped_rgb: np.ndarray) -> Optional[Dict[str, float]]:
        """
        Sheet 2 uses a blue grid with roughly 3 mm minor spacing. Measure the
        regular white grid lines in the rectified sheet.
        """
        hsv = cv2.cvtColor(warped_rgb, cv2.COLOR_RGB2HSV)
        white_mask = ((hsv[:, :, 1] < 90) & (hsv[:, :, 2] > 120)).astype(np.uint8)
        h, w = white_mask.shape[:2]
        roi = white_mask[int(h * 0.08): int(h * 0.96), int(w * 0.04): int(w * 0.96)]
        if roi.size == 0:
            return None

        col_density = np.mean(roi > 0, axis=0)
        row_density = np.mean(roi > 0, axis=1)
        spacing_v = self._estimate_grid_density_spacing(col_density)
        spacing_h = self._estimate_grid_density_spacing(row_density)
        spacing_values = [value for value in [spacing_v, spacing_h] if value is not None]
        if not spacing_values:
            return None

        grid_spacing_px = float(np.median(spacing_values))
        grid_spacing_mm = 3.0
        pixels_per_mm = grid_spacing_px / grid_spacing_mm
        confidence = 0.72
        if spacing_v is not None and spacing_h is not None:
            confidence += 0.10

        return {
            "pixels_per_mm": float(pixels_per_mm),
            "grid_spacing_mm": float(grid_spacing_mm),
            "grid_spacing_px": float(grid_spacing_px),
            "grid_spacing_vertical_px": float(spacing_v or grid_spacing_px),
            "grid_spacing_horizontal_px": float(spacing_h or grid_spacing_px),
            "confidence": float(np.clip(confidence, 0.0, 1.0)),
        }

    def _estimate_grid_density_spacing(self, density: np.ndarray) -> Optional[float]:
        if density.size < 20:
            return None
        prominence = max(0.01, float(np.std(density) * 0.25))
        peaks, _ = find_peaks(
            density,
            prominence=prominence,
            distance=max(4, int(density.size / 220)),
        )
        if len(peaks) < 6:
            return None
        spacings = np.diff(np.sort(peaks))
        spacings = spacings[
            (spacings >= 4)
            & (spacings <= max(32, int(density.size * 0.05)))
        ]
        if len(spacings) < 4:
            return None
        return float(np.median(spacings))

    def _detect_paper_region(self, img_rgb: np.ndarray) -> Optional[Dict[str, Any]]:
        """
        Detect the calibration sheet as the largest bright quadrilateral and warp it
        to a top-down view for grid analysis.
        """
        gray = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2GRAY)
        blur = cv2.GaussianBlur(gray, (7, 7), 0)
        _, thresh = cv2.threshold(blur, 160, 255, cv2.THRESH_BINARY)
        thresh = cv2.morphologyEx(
            thresh,
            cv2.MORPH_CLOSE,
            cv2.getStructuringElement(cv2.MORPH_RECT, (17, 17)),
        )

        contours_info = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contours = contours_info[0] if len(contours_info) == 2 else contours_info[1]
        if not contours:
            return None

        img_area = float(img_rgb.shape[0] * img_rgb.shape[1])
        best = None
        best_area = 0.0
        marker_count = 0
        for contour in contours:
            area = cv2.contourArea(contour)
            if area < img_area * 0.20:
                continue
            peri = cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, 0.02 * peri, True)
            score = area
            if len(approx) >= 4:
                score *= 1.1
            if score > best_area:
                best_area = score
                best = contour

        if best is None:
            return self._detect_colored_calibration_region(img_rgb)

        page = self._warp_calibration_contour(img_rgb, best)
        if page is None:
            return self._detect_colored_calibration_region(img_rgb)

        direct_markers = self._detect_marker_count(img_rgb)
        page["marker_count"] = max(int(page.get("marker_count", 0)), int(direct_markers))
        if page["marker_count"] >= 4:
            page["source"] = "aruco"
        return page

    def _detect_colored_calibration_region(self, img_rgb: np.ndarray) -> Optional[Dict[str, Any]]:
        """
        Detect Sheet 2, where the calibration field is blue instead of white.
        """
        hsv = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2HSV)
        blue_mask = cv2.inRange(
            hsv,
            np.array([80, 25, 35], dtype=np.uint8),
            np.array([145, 255, 255], dtype=np.uint8),
        )
        blue_mask = cv2.morphologyEx(
            blue_mask,
            cv2.MORPH_CLOSE,
            cv2.getStructuringElement(cv2.MORPH_RECT, (21, 21)),
        )
        blue_mask = cv2.morphologyEx(
            blue_mask,
            cv2.MORPH_OPEN,
            cv2.getStructuringElement(cv2.MORPH_RECT, (7, 7)),
        )

        contours_info = cv2.findContours(blue_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contours = contours_info[0] if len(contours_info) == 2 else contours_info[1]
        if not contours:
            return None

        img_area = float(img_rgb.shape[0] * img_rgb.shape[1])
        best = None
        best_area = 0.0
        for contour in contours:
            area = cv2.contourArea(contour)
            if area < img_area * 0.20:
                continue
            if area > best_area:
                best_area = area
                best = contour

        if best is None:
            return None

        page = self._warp_calibration_contour(img_rgb, best)
        if page is None:
            return None
        page["source"] = "blue-sheet"
        page["sheet_style"] = "blue-grading"
        page["marker_count"] = max(
            int(page.get("marker_count", 0)),
            int(self._detect_marker_count(img_rgb)),
        )
        return page

    def _warp_calibration_contour(
        self,
        img_rgb: np.ndarray,
        contour: np.ndarray,
    ) -> Optional[Dict[str, Any]]:
        rect = cv2.minAreaRect(contour)
        box = cv2.boxPoints(rect)
        box = np.array(sorted(box, key=lambda p: (p[1], p[0])), dtype=np.float32)
        box = self._order_points(box)

        width_a = np.linalg.norm(box[2] - box[3])
        width_b = np.linalg.norm(box[1] - box[0])
        height_a = np.linalg.norm(box[1] - box[2])
        height_b = np.linalg.norm(box[0] - box[3])
        width = max(int(max(width_a, width_b)), 1)
        height = max(int(max(height_a, height_b)), 1)

        destination = np.array(
            [[0, 0], [width - 1, 0], [width - 1, height - 1], [0, height - 1]],
            dtype=np.float32,
        )
        matrix = cv2.getPerspectiveTransform(box.astype(np.float32), destination)
        warped = cv2.warpPerspective(img_rgb, matrix, (width, height))
        marker_count = self._count_corner_fiducials(warped)

        return {
            "warped": warped,
            "matrix": matrix,
            "marker_count": marker_count,
            "source": "aruco" if marker_count else "sheet",
            "sheet_style": "precision-white",
        }

    def _count_corner_fiducials(self, warped_rgb: np.ndarray) -> int:
        """
        Count the printed corner fiducials on the rectified calibration sheet.
        """
        gray = cv2.cvtColor(warped_rgb, cv2.COLOR_RGB2GRAY)
        h, w = gray.shape[:2]
        corner_rois = [
            gray[: max(24, int(h * 0.16)), : max(24, int(w * 0.16))],
            gray[: max(24, int(h * 0.16)), max(0, w - max(24, int(w * 0.16))) :],
            gray[max(0, h - max(24, int(h * 0.16))) :, max(0, w - max(24, int(w * 0.16))) :],
            gray[max(0, h - max(24, int(h * 0.16))) :, : max(24, int(w * 0.16))],
        ]
        count = 0
        for roi in corner_rois:
            if roi.size == 0:
                continue
            _, mask = cv2.threshold(roi, 115, 255, cv2.THRESH_BINARY_INV)
            mask = cv2.morphologyEx(
                mask,
                cv2.MORPH_OPEN,
                cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3)),
            )
            contours_info = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            contours = contours_info[0] if len(contours_info) == 2 else contours_info[1]
            roi_area = float(roi.size)
            best_area = 0.0
            found = False
            for contour in contours:
                area = cv2.contourArea(contour)
                if area < roi_area * 0.006 or area > roi_area * 0.50:
                    continue
                peri = cv2.arcLength(contour, True)
                approx = cv2.approxPolyDP(contour, 0.05 * peri, True)
                if len(approx) != 4:
                    continue
                x, y, ww, hh = cv2.boundingRect(approx)
                aspect = ww / float(hh + 1e-6)
                if 0.6 <= aspect <= 1.5 and area > best_area:
                    best_area = area
                    found = True
            if found:
                count += 1
        return count

    def _detect_marker_count(self, img_rgb: np.ndarray) -> int:
        """
        Count visible fiducials using ArUco when available, otherwise fall back to
        square marker contour detection.
        """
        aruco = getattr(cv2, "aruco", None)
        if aruco is not None:
            try:
                gray = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2GRAY)
                dictionary = None
                for dict_name in ("DICT_4X4_50", "DICT_5X5_50", "DICT_6X6_50"):
                    if hasattr(aruco, dict_name):
                        marker_dict = getattr(aruco, dict_name)
                        if hasattr(aruco, "getPredefinedDictionary"):
                            dictionary = aruco.getPredefinedDictionary(marker_dict)
                        elif hasattr(aruco, "Dictionary_get"):
                            dictionary = aruco.Dictionary_get(marker_dict)
                        break
                if dictionary is not None:
                    parameters = (
                        aruco.DetectorParameters_create()
                        if hasattr(aruco, "DetectorParameters_create")
                        else aruco.DetectorParameters()
                    )
                    if hasattr(aruco, "ArucoDetector"):
                        detector = aruco.ArucoDetector(dictionary, parameters)
                        corners, ids, _ = detector.detectMarkers(gray)
                    else:
                        corners, ids, _ = aruco.detectMarkers(gray, dictionary, parameters=parameters)
                    if ids is not None:
                        return int(len(ids))
            except Exception:
                pass

        gray = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2GRAY)
        _, mask = cv2.threshold(gray, 120, 255, cv2.THRESH_BINARY_INV)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, self.morph_kernel)
        contours_info = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contours = contours_info[0] if len(contours_info) == 2 else contours_info[1]
        count = 0
        img_area = float(img_rgb.shape[0] * img_rgb.shape[1])
        for contour in contours:
            area = cv2.contourArea(contour)
            if area < img_area * 0.0004 or area > img_area * 0.04:
                continue
            peri = cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, 0.04 * peri, True)
            if len(approx) == 4:
                x, y, w, h = cv2.boundingRect(approx)
                if w > 10 and h > 10 and 0.7 <= (w / float(h)) <= 1.4:
                    count += 1
        return count

    def _measure_grid_spacing(self, warped_rgb: np.ndarray) -> Tuple[Optional[float], Optional[float], float]:
        """
        Measure the spacing between grid lines in pixels using a rectified sheet.
        """
        gray = cv2.cvtColor(warped_rgb, cv2.COLOR_RGB2GRAY)
        h, w = gray.shape[:2]
        inner = gray[int(h * 0.08): int(h * 0.92), int(w * 0.08): int(w * 0.92)]
        if inner.size == 0:
            inner = gray

        blackhat_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (21, 21))
        blackhat = cv2.morphologyEx(inner, cv2.MORPH_BLACKHAT, blackhat_kernel)
        blackhat = cv2.GaussianBlur(blackhat, (5, 5), 0)

        vertical_profile = np.mean(blackhat, axis=0)
        horizontal_profile = np.mean(blackhat, axis=1)

        spacing_v = self._estimate_profile_spacing(vertical_profile)
        spacing_h = self._estimate_profile_spacing(horizontal_profile)

        confidence = 0.0
        if spacing_v is not None:
            confidence += 0.40
        if spacing_h is not None:
            confidence += 0.40
        if np.max(blackhat) > 0:
            confidence += 0.20
        return spacing_v, spacing_h, float(min(confidence, 1.0))

    def _estimate_profile_spacing(self, profile: np.ndarray) -> Optional[float]:
        if profile.size < 10:
            return None

        smoothed = cv2.GaussianBlur(profile.reshape(1, -1).astype(np.float32), (1, 9), 0).ravel()
        if float(np.max(smoothed) - np.min(smoothed)) < 1e-3:
            return None

        peaks, props = find_peaks(
            smoothed,
            prominence=max(1.0, float(np.std(smoothed) * 0.28)),
            distance=max(4, int(profile.size / 140)),
        )
        if len(peaks) < 3:
            return None

        spacings = np.diff(np.sort(peaks))
        spacings = spacings[(spacings >= 3) & (spacings <= profile.size / 8)]
        if len(spacings) < 2:
            return None
        return float(np.median(spacings))

    def _detect_reference_patch(self, warped_rgb: np.ndarray) -> bool:
        """
        Detect the neutral reference strip near the sheet edge.
        """
        hsv = cv2.cvtColor(warped_rgb, cv2.COLOR_RGB2HSV)
        h, w = hsv.shape[:2]
        strips = [
            hsv[:, : max(8, int(w * 0.10))],
            hsv[:, w - max(8, int(w * 0.10)) :],
        ]
        for strip in strips:
            if strip.size == 0:
                continue
            saturation = float(np.mean(strip[:, :, 1]))
            value = float(np.mean(strip[:, :, 2]))
            if saturation < 65.0 and 45.0 <= value <= 230.0:
                return True
        return False

    def _detect_sample_field(self, img_rgb: np.ndarray) -> Optional[Dict[str, Any]]:
        """
        Detect the blue-bordered grain field that constrains the calibrated sample area.
        """
        sample_box = self._detect_blue_sample_box(img_rgb)
        if sample_box is None:
            return None

        source = (
            "printed-active-zone"
            if sample_box.get("source") == "active-zone-box"
            else "printed-blue-grid"
        )
        x, y, w, h = sample_box["bbox"]
        return {
            "bbox": (int(x), int(y), int(w), int(h)),
            "area_px": float(max(1, w * h)),
            "source": source,
        }

    def _infer_sample_field_from_grain_mask(
        self,
        grain_mask: np.ndarray,
        img_rgb: Optional[np.ndarray] = None,
    ) -> Optional[Dict[str, Any]]:
        """
        Fallback sample region from the detected grain spread when no printed box is found.
        """
        mask = (grain_mask > 0.5).astype(np.uint8)
        if img_rgb is not None:
            hsv = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2HSV)
            lab = cv2.cvtColor(cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR), cv2.COLOR_BGR2LAB)
            h, s, v = hsv[:, :, 0], hsv[:, :, 1], hsv[:, :, 2]
            a_channel, b_channel = lab[:, :, 1], lab[:, :, 2]
            grain_color = (
                ((h <= 35) | (h >= 160))
                & (s >= 35)
                & (v >= 35)
                & (a_channel >= 128)
                & (b_channel >= 105)
            )
            mask = (mask & grain_color.astype(np.uint8)).astype(np.uint8)
            mask = cv2.morphologyEx(
                mask,
                cv2.MORPH_CLOSE,
                cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)),
            )
        points = cv2.findNonZero(mask)
        if points is None:
            return None
        coords = points.reshape(-1, 2)
        if len(coords) >= 50:
            x1_q, y1_q = np.percentile(coords, 3, axis=0)
            x2_q, y2_q = np.percentile(coords, 97, axis=0)
            x = int(max(0, x1_q))
            y = int(max(0, y1_q))
            w = int(max(1, x2_q - x1_q))
            h = int(max(1, y2_q - y1_q))
        else:
            x, y, w, h = cv2.boundingRect(points)
        img_h, img_w = mask.shape[:2]
        pad = int(max(w, h) * 0.10)
        x1 = max(0, x - pad)
        y1 = max(0, y - pad)
        x2 = min(img_w, x + w + pad)
        y2 = min(img_h, y + h + pad)
        return {
            "bbox": (int(x1), int(y1), int(x2 - x1), int(y2 - y1)),
            "area_px": float(max(1, (x2 - x1) * (y2 - y1))),
            "source": "grain-mask-field",
        }

    def _compute_calibrated_grain_geometry(
        self,
        grain_mask: np.ndarray,
        calibration: Dict[str, Any],
        sample_field: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Convert mask areas into physical units when scale calibration is available.
        """
        mm_per_pixel = calibration.get("mm_per_pixel")
        if not calibration.get("available") or not mm_per_pixel:
            return {
                "available": False,
                "grain_area_mm2": None,
                "grain_density_per_cm2": None,
                "median_equiv_diameter_mm": None,
                "clump_equiv_diameter_mm": None,
                "grain_fill_ratio": None,
            }

        mask = (grain_mask > 0.5).astype(np.uint8)
        if sample_field is not None and sample_field.get("bbox"):
            x, y, w, h = sample_field["bbox"]
            field_mask = np.zeros_like(mask)
            cv2.rectangle(field_mask, (x, y), (x + w, y + h), 1, thickness=-1)
            mask = (mask * field_mask).astype(np.uint8)

        num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
        areas_px = []
        for idx in range(1, num_labels):
            area_px = float(stats[idx, cv2.CC_STAT_AREA])
            if area_px < 4:
                continue
            areas_px.append(area_px)

        if not areas_px:
            return {
                "available": True,
                "grain_area_mm2": 0.0,
                "grain_density_per_cm2": 0.0,
                "median_equiv_diameter_mm": 0.0,
                "clump_equiv_diameter_mm": 0.0,
                "grain_fill_ratio": float(np.sum(mask) / mask.size),
            }

        areas_px_arr = np.array(areas_px, dtype=np.float32)
        area_mm2 = areas_px_arr * (mm_per_pixel ** 2)
        equiv_diameters_mm = 2.0 * np.sqrt(area_mm2 / np.pi)
        total_area_mm2 = float(np.sum(area_mm2))
        field_area_mm2 = None
        if sample_field is not None and sample_field.get("area_px"):
            field_area_mm2 = float(sample_field["area_px"]) * (mm_per_pixel ** 2)
        if field_area_mm2 is None or field_area_mm2 <= 0:
            field_area_mm2 = float(mask.size) * (mm_per_pixel ** 2)
        grain_density_per_cm2 = float(len(areas_px_arr) / max(field_area_mm2 / 100.0, 1e-6))
        clump_equiv_diameter_mm = float(np.percentile(equiv_diameters_mm, 90))
        median_equiv_diameter_mm = float(np.median(equiv_diameters_mm))
        grain_fill_ratio = float(np.sum(mask) * (mm_per_pixel ** 2) / max(field_area_mm2, 1e-6))

        return {
            "available": True,
            "grain_area_mm2": round(total_area_mm2, 3),
            "grain_density_per_cm2": round(grain_density_per_cm2, 3),
            "median_equiv_diameter_mm": round(median_equiv_diameter_mm, 3),
            "clump_equiv_diameter_mm": round(clump_equiv_diameter_mm, 3),
            "grain_fill_ratio": round(grain_fill_ratio, 4),
            "field_area_mm2": round(field_area_mm2, 3),
        }

    def _compute_physical_properties(
        self,
        img_rgb: np.ndarray,
        grain_mask: np.ndarray,
        calibration: Dict[str, Any],
        sample_field: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Summarize grain-level physical properties: size, shape, shine, and tone.
        """
        mm_per_pixel = calibration.get("mm_per_pixel") if calibration else None
        mask = (grain_mask > 0.5).astype(np.uint8)
        if sample_field is not None and sample_field.get("bbox"):
            x, y, w, h = sample_field["bbox"]
            field_mask = np.zeros_like(mask)
            cv2.rectangle(field_mask, (x, y), (x + w, y + h), 1, thickness=-1)
            mask = (mask * field_mask).astype(np.uint8)

        hsv = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2HSV)
        lab = cv2.cvtColor(cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR), cv2.COLOR_BGR2LAB)
        v_channel = hsv[:, :, 2].astype(np.float32)
        s_channel = hsv[:, :, 1].astype(np.float32)
        l_channel = lab[:, :, 0].astype(np.float32)

        contours_info = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contours = contours_info[0] if len(contours_info) == 2 else contours_info[1]

        diameters_mm: List[float] = []
        areas_mm2: List[float] = []
        aspect_ratios: List[float] = []
        roundness_values: List[float] = []
        shine_values: List[float] = []
        component_samples: List[Dict[str, Any]] = []
        component_count = 0

        min_area_px = 3.0
        max_area_px = mask.size * 0.08
        for contour in contours:
            area_px = float(cv2.contourArea(contour))
            if area_px < min_area_px or area_px > max_area_px:
                continue
            x, y, w, h = cv2.boundingRect(contour)
            if w < 2 or h < 2:
                continue

            component_mask = np.zeros(mask.shape, dtype=np.uint8)
            cv2.drawContours(component_mask, [contour], -1, 1, thickness=-1)
            pixels = component_mask > 0
            if not np.any(pixels):
                continue

            component_count += 1
            area_mm2 = area_px * (float(mm_per_pixel) ** 2) if mm_per_pixel else None
            if area_mm2 is not None:
                diameter_mm = 2.0 * np.sqrt(max(area_mm2, 1e-6) / np.pi)
                areas_mm2.append(float(area_mm2))
                diameters_mm.append(float(diameter_mm))
            else:
                diameter_mm = None

            aspect_ratio = max(w, h) / float(min(w, h) + 1e-6)
            perimeter = cv2.arcLength(contour, True)
            roundness = (4.0 * np.pi * area_px / (perimeter * perimeter + 1e-6)) if perimeter else 0.0
            highlight_cutoff = max(145.0, float(np.percentile(v_channel[pixels], 92)))
            highlight_ratio = float(np.mean(v_channel[pixels] >= highlight_cutoff))
            shine_index = float(
                np.clip(
                    (np.mean(v_channel[pixels]) / 255.0) * 55.0
                    + highlight_ratio * 45.0
                    + (np.mean(s_channel[pixels]) / 255.0) * 10.0,
                    0.0,
                    100.0,
                )
            )

            aspect_ratios.append(float(aspect_ratio))
            roundness_values.append(float(roundness))
            shine_values.append(shine_index)
            if len(component_samples) < 30:
                component_samples.append(
                    {
                        "bbox": [int(x), int(y), int(w), int(h)],
                        "area_px": round(area_px, 2),
                        "diameter_mm": round(float(diameter_mm), 3) if diameter_mm is not None else None,
                        "aspect_ratio": round(float(aspect_ratio), 3),
                        "roundness": round(float(roundness), 3),
                        "shine_index": round(shine_index, 2),
                    }
                )

        grain_pixels = mask > 0
        if not np.any(grain_pixels):
            return {
                "available": False,
                "component_count": 0,
                "size_class": "unknown",
                "reflectiveness_class": "unknown",
                "shape_class": "unknown",
                "per_grain_samples": [],
            }

        v_values = v_channel[grain_pixels]
        l_values = l_channel[grain_pixels]
        dark_fraction = float(np.mean(v_values < 70.0))
        light_fraction = float(np.mean(v_values > 150.0))
        highlight_fraction = float(np.mean(v_values >= max(150.0, np.percentile(v_values, 92))))
        reflectiveness_index = float(
            np.clip((np.mean(v_values) / 255.0) * 65.0 + highlight_fraction * 35.0, 0.0, 100.0)
        )

        if highlight_fraction >= 0.22 or reflectiveness_index >= 58:
            reflectiveness_class = "high_shine"
        elif reflectiveness_index <= 28 or dark_fraction >= 0.45:
            reflectiveness_class = "dull"
        else:
            reflectiveness_class = "normal"

        size_class = "uncalibrated"
        diameter_median = None
        diameter_p10 = None
        diameter_p90 = None
        diameter_cv = None
        if diameters_mm:
            diam = np.array(diameters_mm, dtype=np.float32)
            diameter_median = float(np.median(diam))
            diameter_p10 = float(np.percentile(diam, 10))
            diameter_p90 = float(np.percentile(diam, 90))
            diameter_cv = float(np.std(diam) / (np.mean(diam) + 1e-6) * 100.0)
            if diameter_cv > 45.0 or (diameter_p10 > 0 and diameter_p90 / diameter_p10 > 2.2):
                size_class = "mixed"
            elif diameter_median < 1.0:
                size_class = "small"
            elif diameter_median > 2.2:
                size_class = "large"
            else:
                size_class = "normal"

        aspect_median = float(np.median(aspect_ratios)) if aspect_ratios else 0.0
        roundness_median = float(np.median(roundness_values)) if roundness_values else 0.0
        if aspect_median >= 2.0 or roundness_median < 0.45:
            shape_class = "elongated_or_broken"
        elif aspect_median >= 1.45:
            shape_class = "slightly_irregular"
        else:
            shape_class = "rounded"

        return {
            "available": True,
            "component_count": int(component_count),
            "single_grain_candidate_count": int(len(diameters_mm) or len(component_samples)),
            "size_class": size_class,
            "median_diameter_mm": round(diameter_median, 3) if diameter_median is not None else None,
            "p10_diameter_mm": round(diameter_p10, 3) if diameter_p10 is not None else None,
            "p90_diameter_mm": round(diameter_p90, 3) if diameter_p90 is not None else None,
            "size_cv_percent": round(diameter_cv, 2) if diameter_cv is not None else None,
            "median_aspect_ratio": round(aspect_median, 3),
            "median_roundness": round(roundness_median, 3),
            "shape_class": shape_class,
            "reflectiveness_index": round(reflectiveness_index, 2),
            "reflectiveness_class": reflectiveness_class,
            "highlight_fraction": round(highlight_fraction, 4),
            "dark_fraction": round(dark_fraction, 4),
            "light_fraction": round(light_fraction, 4),
            "luma_mean": round(float(np.mean(l_values)), 2),
            "luma_std": round(float(np.std(l_values)), 2),
            "per_grain_samples": component_samples,
        }

    def _analyze_grid_boxes(
        self,
        img_rgb: np.ndarray,
        grain_mask: np.ndarray,
        calibration: Dict[str, Any],
        sample_field: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Measure grain placement against the printed calibration-grid boxes.

        For Sheet 1 this reports the 100 mm active box as 10x10 major boxes
        and 100x100 minor 1 mm cells. It also estimates the larger visible
        grid area around the active field for overlay/debug display.
        """
        mm_per_pixel = calibration.get("mm_per_pixel") if calibration else None
        pixels_per_mm = calibration.get("pixels_per_mm") if calibration else None
        if not calibration.get("available") or not mm_per_pixel or not sample_field:
            return {"available": False, "reason": "missing-calibration-or-field"}
        if not sample_field.get("bbox"):
            return {"available": False, "reason": "missing-sample-field"}

        x, y, w, h = [int(v) for v in sample_field["bbox"]]
        img_h, img_w = grain_mask.shape[:2]
        x = int(np.clip(x, 0, max(0, img_w - 1)))
        y = int(np.clip(y, 0, max(0, img_h - 1)))
        w = int(np.clip(w, 1, img_w - x))
        h = int(np.clip(h, 1, img_h - y))

        mask = (grain_mask > 0.5).astype(np.uint8)
        field_mask = np.zeros_like(mask)
        cv2.rectangle(field_mask, (x, y), (x + w, y + h), 1, thickness=-1)
        field_grain_mask = (mask * field_mask).astype(np.uint8)
        crop = field_grain_mask[y: y + h, x: x + w]

        field_width_mm = float(w * mm_per_pixel)
        field_height_mm = float(h * mm_per_pixel)
        major_cell_mm = 10.0
        if calibration.get("sheet_style") == "blue-grading" and calibration.get("grid_spacing_mm"):
            major_cell_mm = float(calibration["grid_spacing_mm"])
        minor_cell_mm = 1.0

        major_cols = max(1, int(round(field_width_mm / major_cell_mm)))
        major_rows = max(1, int(round(field_height_mm / major_cell_mm)))
        major_occupancy = self._grid_occupancy(crop, major_rows, major_cols)

        minor_cols = max(1, int(round(field_width_mm / minor_cell_mm)))
        minor_rows = max(1, int(round(field_height_mm / minor_cell_mm)))
        occupied_minor_cells = 0
        if crop.size and np.count_nonzero(crop):
            coords_yx = np.argwhere(crop > 0)
            minor_col = np.clip(
                np.floor(coords_yx[:, 1] * float(mm_per_pixel) / minor_cell_mm).astype(int),
                0,
                minor_cols - 1,
            )
            minor_row = np.clip(
                np.floor(coords_yx[:, 0] * float(mm_per_pixel) / minor_cell_mm).astype(int),
                0,
                minor_rows - 1,
            )
            occupied_minor_cells = int(
                len(np.unique(minor_row.astype(np.int64) * minor_cols + minor_col.astype(np.int64)))
            )

        contours_info = cv2.findContours(field_grain_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contours = contours_info[0] if len(contours_info) == 2 else contours_info[1]
        per_grain_samples: List[Dict[str, Any]] = []
        diameters_mm: List[float] = []
        for contour in contours:
            area_px = float(cv2.contourArea(contour))
            if area_px < 3.0 or area_px > crop.size * 0.08:
                continue
            bx, by, bw, bh = cv2.boundingRect(contour)
            if bw < 2 or bh < 2:
                continue
            moments = cv2.moments(contour)
            if moments["m00"]:
                cx = float(moments["m10"] / moments["m00"])
                cy = float(moments["m01"] / moments["m00"])
            else:
                cx = float(bx + bw / 2.0)
                cy = float(by + bh / 2.0)

            rel_x_mm = max(0.0, (cx - x) * float(mm_per_pixel))
            rel_y_mm = max(0.0, (cy - y) * float(mm_per_pixel))
            diameter_mm = 2.0 * np.sqrt((area_px * (float(mm_per_pixel) ** 2)) / np.pi)
            diameters_mm.append(float(diameter_mm))

            if len(per_grain_samples) < 40:
                per_grain_samples.append(
                    {
                        "bbox": [int(bx), int(by), int(bw), int(bh)],
                        "diameter_mm": round(float(diameter_mm), 3),
                        "width_mm": round(float(bw * mm_per_pixel), 3),
                        "height_mm": round(float(bh * mm_per_pixel), 3),
                        "active_major_cell": {
                            "row": int(np.clip(np.floor(rel_y_mm / major_cell_mm), 0, major_rows - 1) + 1),
                            "col": int(np.clip(np.floor(rel_x_mm / major_cell_mm), 0, major_cols - 1) + 1),
                            "cell_mm": major_cell_mm,
                        },
                        "active_minor_cell": {
                            "row": int(np.clip(np.floor(rel_y_mm / minor_cell_mm), 0, minor_rows - 1) + 1),
                            "col": int(np.clip(np.floor(rel_x_mm / minor_cell_mm), 0, minor_cols - 1) + 1),
                            "cell_mm": minor_cell_mm,
                        },
                    }
                )

        big_sheet_grid = self._detect_big_sheet_grid(img_rgb, sample_field, calibration)
        median_diameter_mm = float(np.median(diameters_mm)) if diameters_mm else 0.0
        p90_diameter_mm = float(np.percentile(diameters_mm, 90)) if diameters_mm else 0.0

        return {
            "available": True,
            "calibration_source": calibration.get("source", "none"),
            "sheet_style": calibration.get("sheet_style", "unknown"),
            "active_field": {
                "bbox": [int(x), int(y), int(w), int(h)],
                "source": sample_field.get("source", "unknown"),
                "width_mm": round(field_width_mm, 2),
                "height_mm": round(field_height_mm, 2),
                "major_cell_mm": major_cell_mm,
                "major_rows": int(major_rows),
                "major_cols": int(major_cols),
                "major_occupied_cells": int(major_occupancy["occupied_cells"]),
                "major_total_cells": int(major_rows * major_cols),
                "major_max_fill_ratio": major_occupancy["max_fill_ratio"],
                "major_mean_fill_ratio": major_occupancy["mean_fill_ratio"],
                "densest_major_cell": major_occupancy["densest_cell"],
                "minor_cell_mm": minor_cell_mm,
                "minor_rows": int(minor_rows),
                "minor_cols": int(minor_cols),
                "minor_occupied_cells": int(occupied_minor_cells),
                "minor_total_cells": int(minor_rows * minor_cols),
            },
            "grain_count": int(len(diameters_mm)),
            "median_diameter_mm": round(median_diameter_mm, 3),
            "p90_diameter_mm": round(p90_diameter_mm, 3),
            "per_grain_grid_samples": per_grain_samples,
            "big_sheet_grid": big_sheet_grid,
        }

    def _grid_occupancy(self, crop_mask: np.ndarray, rows: int, cols: int) -> Dict[str, Any]:
        rows = max(1, int(rows))
        cols = max(1, int(cols))
        h, w = crop_mask.shape[:2]
        occupied = 0
        fill_values: List[float] = []
        densest = {"row": 1, "col": 1, "fill_ratio": 0.0}
        for row in range(rows):
            y1 = int(round(row * h / rows))
            y2 = int(round((row + 1) * h / rows))
            for col in range(cols):
                x1 = int(round(col * w / cols))
                x2 = int(round((col + 1) * w / cols))
                cell = crop_mask[y1:y2, x1:x2]
                if cell.size == 0:
                    fill = 0.0
                else:
                    fill = float(np.count_nonzero(cell) / cell.size)
                fill_values.append(fill)
                if fill > 0:
                    occupied += 1
                if fill > densest["fill_ratio"]:
                    densest = {
                        "row": int(row + 1),
                        "col": int(col + 1),
                        "fill_ratio": round(fill, 4),
                    }

        return {
            "occupied_cells": int(occupied),
            "max_fill_ratio": round(float(max(fill_values) if fill_values else 0.0), 4),
            "mean_fill_ratio": round(float(np.mean(fill_values) if fill_values else 0.0), 4),
            "densest_cell": densest,
        }

    def _detect_big_sheet_grid(
        self,
        img_rgb: np.ndarray,
        sample_field: Optional[Dict[str, Any]],
        calibration: Dict[str, Any],
    ) -> Dict[str, Any]:
        if (
            not sample_field
            or not sample_field.get("bbox")
            or not calibration.get("pixels_per_mm")
            or calibration.get("sheet_style") != "precision-white"
        ):
            return {"available": False}

        x, y, w, h = [int(v) for v in sample_field["bbox"]]
        spacing_px = float(calibration["pixels_per_mm"]) * 10.0
        if spacing_px <= 0:
            return {"available": False}

        gray = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2GRAY)
        hsv = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2HSV)
        dark_lines = ((gray < 170) & (hsv[:, :, 1] < 130)).astype(np.uint8)

        img_h, img_w = gray.shape[:2]
        x1 = max(0, int(x - spacing_px * 4.5))
        x2 = min(img_w, int(x + w + spacing_px * 4.5))
        y1 = max(0, int(y - spacing_px * 8.0))
        y2 = min(img_h, int(y + h + spacing_px * 10.0))
        roi = dark_lines[y1:y2, x1:x2]
        if roi.size == 0:
            return {"available": False}

        col_profile = np.mean(roi, axis=0)
        row_profile = np.mean(roi, axis=1)
        x_span = self._expected_spacing_peak_span(col_profile, spacing_px)
        y_span = self._expected_spacing_peak_span(row_profile, spacing_px)
        if x_span is None or y_span is None:
            return {"available": False}

        gx1 = int(x1 + x_span[0])
        gx2 = int(x1 + x_span[1])
        gy1 = int(y1 + y_span[0])
        gy2 = int(y1 + y_span[1])
        if gx2 <= gx1 or gy2 <= gy1:
            return {"available": False}

        return {
            "available": True,
            "bbox": [gx1, gy1, gx2 - gx1, gy2 - gy1],
            "major_cell_mm": 10.0,
            "major_spacing_px": round(spacing_px, 2),
            "estimated_cols": int(max(1, round((gx2 - gx1) / spacing_px))),
            "estimated_rows": int(max(1, round((gy2 - gy1) / spacing_px))),
            "source": "detected-sheet1-major-grid",
        }

    def _expected_spacing_peak_span(
        self,
        profile: np.ndarray,
        expected_spacing_px: float,
    ) -> Optional[Tuple[int, int]]:
        if profile.size < 20 or expected_spacing_px <= 0:
            return None

        smoothed = cv2.GaussianBlur(profile.reshape(1, -1).astype(np.float32), (1, 9), 0).ravel()
        peaks, _ = find_peaks(
            smoothed,
            prominence=max(0.005, float(np.std(smoothed) * 0.30)),
            distance=max(4, int(expected_spacing_px * 0.55)),
        )
        if len(peaks) < 4:
            return None

        min_gap = expected_spacing_px * 0.55
        max_gap = expected_spacing_px * 1.55
        runs: List[List[int]] = []
        current: List[int] = [int(peaks[0])]
        for prev, nxt in zip(peaks[:-1], peaks[1:]):
            gap = float(nxt - prev)
            if min_gap <= gap <= max_gap:
                current.append(int(nxt))
            else:
                runs.append(current)
                current = [int(nxt)]
        runs.append(current)

        best = max(runs, key=len)
        if len(best) < 4:
            return None
        return int(best[0]), int(best[-1])

    def _order_points(self, pts: np.ndarray) -> np.ndarray:
        """Return points ordered as top-left, top-right, bottom-right, bottom-left."""
        rect = np.zeros((4, 2), dtype=np.float32)
        s = pts.sum(axis=1)
        diff = np.diff(pts, axis=1).ravel()
        rect[0] = pts[np.argmin(s)]
        rect[2] = pts[np.argmax(s)]
        rect[1] = pts[np.argmin(diff)]
        rect[3] = pts[np.argmax(diff)]
        return rect

    def _segment_grain_region(self, img_rgb: np.ndarray) -> np.ndarray:
        """
        Conservative grain region segmentation using color-based thresholding.
        Returns binary mask where 1 = grain region, 0 = background.
        """
        hsv = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2HSV)
        lab = cv2.cvtColor(cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR), cv2.COLOR_BGR2LAB)
        h, s, v = hsv[:, :, 0], hsv[:, :, 1], hsv[:, :, 2]
        l_channel, a_channel, b_channel = lab[:, :, 0], lab[:, :, 1], lab[:, :, 2]

        brown_hue = ((h <= 32) | (h >= 168)) & (s >= 28) & (v >= 18) & (v <= 235)
        lab_brown = (a_channel >= 132) & (b_channel >= 118) & (l_channel <= 205)
        dark_red = (a_channel >= 126) & (s >= 18) & (v >= 16) & (v <= 160)
        blue_border = (h >= 85) & (h <= 140) & (s >= 35)
        white_sheet = (s <= 24) & (v >= 135)

        grain_mask = ((brown_hue | lab_brown | dark_red) & ~blue_border & ~white_sheet).astype(np.uint8) * 255

        small_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        grain_mask = cv2.morphologyEx(grain_mask, cv2.MORPH_OPEN, small_kernel)
        grain_mask = cv2.morphologyEx(grain_mask, cv2.MORPH_CLOSE, small_kernel)

        return grain_mask / 255.0

    def _compute_texture_entropy(self, img_rgb: np.ndarray, mask: np.ndarray) -> float:
        """
        Compute Shannon entropy of surface texture (Laplacian magnitude).
        
        High entropy = varied micro-roughness (typical of dry grain)
        Low entropy = smooth surface (indicator of moisture/clumping)
        """
        gray = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2GRAY)

        # Compute Laplacian (edge/texture detection)
        laplacian = cv2.Laplacian(gray, cv2.CV_32F)
        laplacian_abs = np.abs(laplacian)

        # Apply mask to grain region only
        masked_laplacian = laplacian_abs[mask > 0.5]

        if len(masked_laplacian) == 0:
            return 0.0

        # Normalize to 0-255 range for entropy calculation
        laplacian_norm = (masked_laplacian - masked_laplacian.min()) / (
            masked_laplacian.max() - masked_laplacian.min() + 1e-6
        ) * 255

        # Bin into histogram (16 bins)
        hist, _ = np.histogram(laplacian_norm, bins=16, range=(0, 256))
        hist = hist / hist.sum()
        hist = hist[hist > 0]  # Remove zero bins

        # Shannon entropy
        text_entropy = -np.sum(hist * np.log2(hist + 1e-10))

        return text_entropy

    def _extract_lab_features(self, img_rgb: np.ndarray, mask: np.ndarray) -> Dict[str, float]:
        """
        Extract CIE-LAB color features to detect moisture absorption.
        
        Moisture absorbed by grain → darker appearance (lower L*)
        LAB color shift correlates with moisture content.
        """
        img_bgr = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR)
        lab = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)

        # Extract L*, a*, b* channels
        l_channel = lab[:, :, 0]
        a_channel = lab[:, :, 1]
        b_channel = lab[:, :, 2]

        # Apply mask
        masked_l = l_channel[mask > 0.5]
        masked_a = a_channel[mask > 0.5]
        masked_b = b_channel[mask > 0.5]

        if masked_l.size == 0:
            return {
                "l_mean": 255.0,
                "l_std": 0.0,
                "a_mean": 128.0,
                "b_mean": 128.0,
                "color_darkness_index": 0.0,
            }

        l_mean = float(np.mean(masked_l))
        l_std = float(np.std(masked_l))
        a_mean = float(np.mean(masked_a))
        b_mean = float(np.mean(masked_b))

        # Darkness index: inverted L* (higher = darker grain = higher moisture)
        # Normalize L* to 0-100 scale
        color_darkness_index = float(np.clip(100 - (l_mean / 255.0) * 100, 0.0, 100.0))

        return {
            "l_mean": l_mean,
            "l_std": l_std,
            "a_mean": a_mean,
            "b_mean": b_mean,
            "color_darkness_index": color_darkness_index,
        }

    def _compute_clumping_density(self, img_rgb: np.ndarray, mask: np.ndarray) -> Dict[str, float]:
        """
        Connected-components analysis to detect capillary clumping.
        
        Wet grains stick together → large connected regions
        Clumping density metric correlates with moisture level
        """
        # Create a more aggressive binary mask for clumping detection
        gray = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2GRAY)

        # Use local contrast to find grain boundaries
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(gray)

        # Binary threshold for individual grains
        _, binary = cv2.threshold(enhanced, 100, 255, cv2.THRESH_BINARY)

        # Apply initial mask
        binary = (binary / 255.0) * mask

        # Connected components
        num_labels, labels = cv2.connectedComponents(binary.astype(np.uint8))

        # Analyze cluster sizes
        cluster_sizes = []
        for label_id in range(1, num_labels):  # Skip background (0)
            cluster_size = np.sum(labels == label_id)
            cluster_sizes.append(cluster_size)

        if len(cluster_sizes) == 0:
            return {
                "density": 0.0,
                "cluster_count": 0,
                "avg_cluster_size": 0.0,
            }

        cluster_sizes = np.array(cluster_sizes)
        avg_cluster_size = np.mean(cluster_sizes)
        max_cluster_size = np.max(cluster_sizes)

        # Clumping density: ratio of max cluster to total grain pixels
        total_grain_pixels = np.sum(mask)
        clumping_density = (
            max_cluster_size / (total_grain_pixels + 1e-6)
            if total_grain_pixels > 0
            else 0.0
        )

        return {
            "density": clumping_density,
            "cluster_count": len(cluster_sizes),
            "avg_cluster_size": avg_cluster_size,
        }

    def _compute_surface_roughness(self, img_rgb: np.ndarray, mask: np.ndarray) -> float:
        """
        Laplacian variance as roughness metric.
        
        High variance = rough surface (dry grain)
        Low variance = smooth surface (wet/clumped grain)
        """
        gray = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2GRAY)
        laplacian = cv2.Laplacian(gray, cv2.CV_32F)

        masked_laplacian = laplacian[mask > 0.5]

        if len(masked_laplacian) == 0:
            return 0.0

        roughness = np.var(masked_laplacian)
        # Normalize to 0-100 scale
        roughness_norm = min(100.0, roughness / 100.0)

        return roughness_norm

    def _compute_specular_highlights(self, img_rgb: np.ndarray, mask: np.ndarray) -> float:
        """
        Ratio of bright pixels (specular highlights) to grain region.
        
        High highlights = dry grain surface
        Low highlights = matte/dull surface (moisture indicator)
        
        In diffused lighting, highlights are minimal; this acts as a
        quality check rather than moisture primary indicator.
        """
        gray = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2GRAY)

        # Define "bright" pixels: intensity > 200 (out of 255)
        bright_pixels = gray > 200

        # Apply mask
        masked_bright = bright_pixels[mask > 0.5]
        total_masked = np.sum(mask > 0.5)

        if total_masked == 0:
            return 0.0

        specular_ratio = np.sum(masked_bright) / total_masked

        return specular_ratio

    def _compute_uniformity(self, img_rgb: np.ndarray, mask: np.ndarray) -> float:
        """
        Grain color uniformity score.
        
        High uniformity (narrow color range) = Grade A (consistent grain quality)
        Low uniformity (bimodal/wide distribution) = Grade C (mixed quality)
        """
        # Use HSV value (brightness) channel for uniformity
        hsv = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2HSV)
        v_channel = hsv[:, :, 2].astype(np.float32)

        masked_v = v_channel[mask > 0.5]

        if len(masked_v) == 0:
            return 0.0

        # Compute coefficient of variation (normalized std dev)
        mean_v = np.mean(masked_v)
        std_v = np.std(masked_v)
        coeff_var = (std_v / (mean_v + 1e-6)) * 100

        # Convert to uniformity score: lower CV = higher uniformity
        # Score 0-100, normalized
        uniformity_score = max(0.0, 100.0 - coeff_var)

        return uniformity_score


# Batch processing utility
def process_image_batch(
    image_paths: List[str], extractor: PhysicsProxiesExtractor = None
) -> List[Dict[str, Any]]:
    """
    Process multiple images and return proxy features for each.
    Useful for batch analysis and dataset preparation.
    """
    if extractor is None:
        extractor = PhysicsProxiesExtractor()

    results = []
    for img_path in image_paths:
        try:
            proxy_dict = extractor.extract_all_proxies(img_path)
            results.append(proxy_dict)
        except Exception as e:
            logger.warning(f"Skipped {img_path}: {e}")
            continue

    logger.info(f"✓ Processed {len(results)}/{len(image_paths)} images")
    return results


if __name__ == "__main__":
    # Example usage
    import sys

    if len(sys.argv) < 2:
        print("Usage: python physics_proxies.py <image_path>")
        sys.exit(1)

    image_path = sys.argv[1]
    extractor = PhysicsProxiesExtractor()
    result = extractor.extract_all_proxies(image_path)

    print("\n" + "=" * 60)
    print("PHYSICS PROXIES EXTRACTION RESULT")
    print("=" * 60)
    import json

    print(json.dumps(result, indent=2))

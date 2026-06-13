"""
Moisture Calibration for Ragi Grain Analysis
============================================

Maps internal optical/physics proxy scores (0-100) to calibrated moisture percentages.
Based on specification bands in UNIFIED_RAGI_QUALITY_AND_MOISTURE_SPEC.md.

Author: Copilot
Date: 2026-04-29
"""

from typing import Dict, Any, Tuple

class MoistureCalibrator:
    """
    Handles the mapping from raw physics-based moisture score to 
    calibrated moisture percentage using piece-wise linear interpolation.
    """
    
    def __init__(self):
        # Default mapping based on provisional thresholds in spec:
        # (raw_score, moisture_percent)
        # Score 0-30 -> <= 11.5% (LOW)
        # Score 31-50 -> 11.5% - 13.0% (MODERATE)
        # Score 51-70 -> 13.0% - 15.0% (HIGH)
        # Score 71-100 -> >= 15.0% (CRITICAL)
        
        # We use a set of control points for interpolation
        self.control_points = [
            (0.0, 9.0),    # Extremely dry
            (30.0, 11.5),  # Boundary LOW/MODERATE
            (50.0, 13.0),  # Boundary MODERATE/HIGH
            (70.0, 15.0),  # Boundary HIGH/CRITICAL
            (100.0, 22.0)  # Extremely wet (capillary saturation)
        ]

    def calibrate(self, raw_score: float) -> float:
        """
        Convert raw score (0-100) to calibrated moisture percentage.
        """
        raw_score = max(0.0, min(100.0, raw_score))
        
        # Find the segment
        for i in range(len(self.control_points) - 1):
            s0, m0 = self.control_points[i]
            s1, m1 = self.control_points[i+1]
            
            if s0 <= raw_score <= s1:
                # Linear interpolation within the segment
                ratio = (raw_score - s0) / (s1 - s0)
                moisture_percent = m0 + ratio * (m1 - m0)
                return round(moisture_percent, 1)
        
        return self.control_points[-1][1]

    def get_is_calibrated(self) -> bool:
        """
        Returns True as this class provides a calibration mapping.
        """
        return True

if __name__ == "__main__":
    calibrator = MoistureCalibrator()
    test_scores = [10, 30, 40, 50, 60, 70, 85, 100]
    for s in test_scores:
        m = calibrator.calibrate(s)
        print(f"Raw Score: {s:3.0f} | Calibrated Moisture: {m:4.1f}%")

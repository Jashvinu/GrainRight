import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = REPO_ROOT / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from ai_grain_grade.vision_rag_pipeline import VisionRAGPipeline
from ai_grain_grade.physics_proxies import PhysicsProxiesExtractor
import json

def test_calibration():
    # Setup
    image_path = "Callibration garin garde sample.jpeg"
    
    extractor = PhysicsProxiesExtractor()
    pipeline = VisionRAGPipeline(
        qwen_model="qwen3-vl:8b",
        use_ollama=True,
        ollama_url="http://localhost:11434/v1"
    )
    
    print(f"--- Running Analysis on: {image_path} (Using local Ollama) ---")
    
    # 1. Extract Proxies
    proxies = extractor.extract_all_proxies(image_path)
    
    # 2. Run Inference (this will use fallback if API key is invalid)
    result = pipeline.infer(image_path, proxies)
    
    # 3. Print Moisture Results
    print("\n[MOISTURE ASSESSMENT]")
    print(f"Risk Level: {result.moisture_risk}")
    print(f"Calibrated: {result.moisture_estimate_calibrated}")
    print(f"Percentage: {result.moisture_percent_estimate}%")
    
    # 4. Print Quality Results
    print("\n[QUALITY ASSESSMENT]")
    print(f"Grade: {result.quality_grade}")
    print(f"Score: {result.quality_score}")
    print(f"Reject Recommended: {result.reject_recommended}")
    if result.reject_reasons:
        print(f"Reasons: {', '.join(result.reject_reasons)}")

if __name__ == "__main__":
    test_calibration()

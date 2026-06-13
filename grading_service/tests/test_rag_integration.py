"""
Tests for RAG Engine and its Integration with VisionRAGPipeline.
"""

import pytest
from pathlib import Path
from ai_grain_grade.rag_engine import RAGEngine
from ai_grain_grade.vision_rag_pipeline import VisionRAGPipeline

def test_rag_engine_indexing_and_retrieval(tmp_path):
    """Test that RAGEngine can index documents and retrieve relevant chunks."""
    index_path = tmp_path / "test_rag_index.json"
    engine = RAGEngine(index_path=index_path)
    
    # Create a dummy markdown file
    dummy_doc = tmp_path / "test_grading_spec.md"
    dummy_doc.write_text("""
# Ragi Grading Spec
## Grade A
Grade A ragi must have less than 5% off-tone grains.
## Grade C
Grade C ragi has high moisture and visible mold.
    """, encoding="utf-8")
    
    try:
        engine.index_documents([str(dummy_doc)])
        assert len(engine.chunks) >= 2
        
        # Test retrieval
        results = engine.retrieve("What is Grade A?")
        assert len(results) > 0
        assert "Grade A" in results[0]["title"]
        assert "5%" in results[0]["content"]
        
        results_c = engine.retrieve("visible mold")
        assert len(results_c) > 0
        assert "Grade C" in results_c[0]["title"]
        
    finally:
        if dummy_doc.exists():
            dummy_doc.unlink()
        if index_path.exists():
            index_path.unlink()

def test_pipeline_uses_rag_engine():
    """Test that VisionRAGPipeline correctly uses the RAGEngine for context."""
    pipeline = VisionRAGPipeline(siliconflow_api_key="test-key")
    
    # Mock proxies that should trigger moisture query
    proxies = {
        "texture_entropy": 2.5,
        "clumping": {"density": 0.4},
        "lab_features": {"color_darkness_index": 60}
    }
    
    context = pipeline._retrieve_rag_context(proxies)
    
    assert isinstance(context, list)
    # Since it indexed the real docs in __init__, it should find something
    assert len(context) > 0
    assert any("moisture" in c["content"].lower() or "grading" in c["content"].lower() for c in context)

if __name__ == "__main__":
    pytest.main([__file__, "-v"])

#!/bin/bash
# Deployment script for Millets Now
# Streamlit-based Ragi Quality Grading System

set -e

echo "🌾 Millets Now - Deployment Script"
echo "===================================="

# 1. Check Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3 not found. Please install Python 3.9+"
    exit 1
fi
echo "✓ Python: $(python3 --version)"

# 2. Create virtual environment (optional)
if [ "$1" == "--venv" ]; then
    echo "📦 Setting up virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    echo "✓ Virtual environment activated"
fi

# 3. Install dependencies
echo "📥 Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt
echo "✓ Dependencies installed"

# 4. Environment setup
echo "⚙️ Configuring environment..."

if [ ! -f ".env" ]; then
    cat > .env << EOF
# Required: SiliconFlow API key for Qwen2.5-VL inference
SILICONFLOW_API_KEY=sk-your-key-here

# Optional: Hugging Face credentials for active learning
HF_TOKEN=hf_your-token-here
HF_DATASET_ID=username/ragi-feedback-data

# Optional: Vector DB configuration
VECTOR_DB_TYPE=local
# SUPABASE_URL=https://xxx.supabase.co
# SUPABASE_KEY=xxx
# PINECONE_API_KEY=xxx
# PINECONE_INDEX=ragi-grading
EOF
    echo "✓ Created .env file (fill in your API keys)"
else
    echo "✓ .env file exists"
fi

# 5. Create data directories
echo "📁 Setting up data directories..."
mkdir -p data/feedback/feedback_data
mkdir -p data/rag
mkdir -p models
mkdir -p results
mkdir -p logs
echo "✓ Directories created"

# 6. Download/setup RAG knowledge base
echo "📚 Setting up RAG knowledge base..."
if [ ! -f "data/rag/rag_chunks.json" ]; then
    cat > data/rag/rag_chunks.json << 'EOF'
{
  "chunks": [
    {
      "id": "grade-a-rule",
      "content": "Grade A: Premium food grade. Assign only if: off-tone < 5%, size deviation < 5%, shape defect < 5%, foreign matter < 1%, no biological hazards, no dullness.",
      "section": "Grading Rules"
    },
    {
      "id": "grade-b-rule",
      "content": "Grade B: Commercial food grade. Typical: off-tone 5-10%, minor size/shape variance, foreign matter 1-3%, no hazards.",
      "section": "Grading Rules"
    },
    {
      "id": "grade-c-rule",
      "content": "Grade C: Processing or low-quality. Bimodal color, off-tone 10-35%, size deviation 15-30%, shape defect 10-25%, or visible degradation.",
      "section": "Grading Rules"
    },
    {
      "id": "safety-gate",
      "content": "Hard safety gate: If mold, stones, webbing, insect damage, or foreign matter > 3% detected → Grade C + reject_recommended=true.",
      "section": "Safety"
    },
    {
      "id": "moisture-critical",
      "content": "Moisture CRITICAL risk: >= 15.0%. Indicators: significant darkening, high clumping, risk of mold.",
      "section": "Moisture"
    }
  ]
}
EOF
    echo "✓ Created data/rag/rag_chunks.json"
fi

# 7. Test imports
echo "🧪 Testing imports..."
python3 -c "import streamlit, cv2, torch, transformers; print('✓ All imports successful')" || {
    echo "❌ Import test failed"
    exit 1
}

# 8. Deployment info
echo ""
echo "✅ DEPLOYMENT READY!"
echo "===================="
echo ""
echo "To start the Streamlit app:"
echo "  streamlit run app.py --server.port 8501"
echo ""
echo "Then open: http://localhost:8501"
echo ""
echo "Important:"
echo "  1. Fill in API keys in .env file"
echo "  2. Upload grain images for testing"
echo "  3. Collect feedback to trigger LoRA training at 500 samples"
echo ""
echo "Production deployment:"
echo "  - Streamlit Cloud: https://streamlit.io/cloud"
echo "  - Docker: Build and deploy to Kubernetes/Cloud Run"
echo "  - Alternative: FastAPI backend + React frontend"
echo ""

# AI Grain Grading System - Crop Knowledge Base

## Purpose

This file is the master crop routing file used by the AI Grain Grading System.

Functions:
- Crop Identification
- Crop Routing
- Parameter Selection
- Knowledge Retrieval
- Variety Discovery

---

## Supported Crop Types

### Bajari

Scientific Name: Pennisetum glaucum

Available Varieties:
- ICTP8203
- AHB1200
- Local Maharashtra Bajari

Knowledge Files:
- knowledge_base/Bajari/Bajari.MD
- knowledge_base/Bajari/Variety/ICTP8203.MD
- knowledge_base/Bajari/Variety/AHB1200.MD
- knowledge_base/Bajari/Variety/LocalMaharashtraBajari.MD

Common Parameters:
- Moisture
- Organic Extraneous Matter
- Inorganic Extraneous Matter
- Other Edible Grains
- Damaged Grains
- Immature Grains
- Weevilled Grains
- Color
- Size
- Shape
- Surface Defects

---

### Finger Millets

Scientific Name: Eleusine coracana

Available Varieties:
- GPU28
- GPU45
- GPU48
- Dapoli Nachani

Knowledge Files:
- knowledge_base/FingerMillets/FingerMillets.MD
- knowledge_base/FingerMillets/Variety/GPU28.MD
- knowledge_base/FingerMillets/Variety/GPU45.MD
- knowledge_base/FingerMillets/Variety/GPU48.MD
- knowledge_base/FingerMillets/Variety/DapoliNachani.MD

Common Parameters:
- Moisture
- Organic Extraneous Matter
- Inorganic Extraneous Matter
- Damaged Grains
- Immature Grains
- Weevilled Grains
- Color
- Size
- Shape
- Surface Defects

---

### Rice

Scientific Name: Oryza sativa

Available Varieties:
- Indrayani
- Basmati
- Kolam

Knowledge Files:
- knowledge_base/Rice/Rice.MD
- knowledge_base/Rice/Variety/Indrayani.MD
- knowledge_base/Rice/Variety/Basmati.MD
- knowledge_base/Rice/Variety/Kolam.MD

Common Parameters:
- Moisture
- Broken Grains
- Damaged Grains
- Chalky Grains
- Foreign Matter
- Other Rice Varieties
- Color
- Size
- Shape
- Surface Defects

---

## AI Grading Workflow

Crop Selection
→ Variety Selection
→ Moisture Meter Capture
→ OCR Extraction
→ Moisture Value
→ Grain Image Capture
→ OpenCV Analysis
→ Feature Extraction
→ RAG Search
→ Rule Engine
→ Grade Calculation
→ Final Output

---

## Rule Files

- grading_rules/bajari_rules.yaml
- grading_rules/fingermillet_rules.yaml
- grading_rules/rice_rules.yaml

---

## Final Output

- Crop Type
- Variety
- Moisture
- Detected Features
- Quality Score
- Grade
- Confidence Score

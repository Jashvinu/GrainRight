# Authorized Ragi Data and Physical-Property Sources

This file is a retrieval anchor for improving the ragi grading model with
public, official, or institutionally authoritative sources. It is not a claim
that the app certifies grain. Legal procurement, food-safety, and trade
decisions still require applicable official sampling, lab measurement, and
inspection procedures.

## Official Threshold and Assaying Sources

- e-NAM RAGI assaying specification:
  https://www.enam.gov.in/NAMV2/infrastructure/RAGI.pdf
- Food Corporation of India public procurement specifications:
  https://fci.gov.in/fci-storage/storage/app/uploads/662297b721c361713543095.pdf
- Food Safety and Standards Authority of India cereal and cereal-products
  standards:
  https://www.fssai.gov.in/upload/uploadfiles/files/Chapter%202_4_Cereals_and_Cereal_products.pdf
- FAO grain-quality and storage guidance:
  https://www.fao.org/4/t1838e/t1838e0h.htm
  https://www.fao.org/4/t1838e/t1838e0i.htm
  https://www.fao.org/4/V5380E/V5380E06.htm

Use these sources for moisture, foreign matter, damaged grains, insect/mould
hazards, storage condition, sampling vocabulary, and operator-facing reject or
hold rules.

## Agmark and Market Data Sources

- AGMARKNET / Directorate of Marketing and Inspection market information:
  https://agmarknet.gov.in/
- data.gov.in crop statistics for ragi area, production, and yield:
  https://www.data.gov.in/
- data.gov.in and AGMARKNET market arrivals/prices can be used as market
  context datasets. They should not be used as image labels.

Use market data for trend analysis, region/crop metadata, and operational
dashboards. Do not train visual quality labels from price alone; price is
confounded by market, season, variety, seller, and procurement policy.

## Physical Properties To Extract From Images

The model should inspect these calibrated physical properties for each lot:

- Size: median equivalent grain diameter, p10/p90 diameter, size class
  (`small`, `normal`, `large`, `mixed`), and coefficient of variation.
- Shape: aspect ratio, roundness, elongated or broken-looking components,
  shrivelled/immature-looking small components, and clumped large components.
- Surface reflectance: shine index, highlight fraction, dullness, dark fraction,
  and glare risk.
- Colour and tone: darkness index, LAB L/a/b shift, off-tone fraction, bimodal
  colour, and uniformity.
- Texture: entropy, roughness, smooth/moisture-like surface, and high-contrast
  broken or foreign particles.
- Layout and capture quality: calibrated sample field, mask coverage, grain-fill
  ratio, grid or marker confidence, reference patch visibility, blur, exposure,
  and retake flags.

## Dataset Rules

Production training data must store:

- raw original image without destructive resize
- calibrated crop and visual overlay artifacts
- calibration source (`aruco-grid`, `marker-grid`, `grid-only`, or fallback)
- pixels-per-mm and grid spacing used
- per-grain physical-property summary
- operator grade correction
- measured moisture percentage when available, with method and device
- source of legal threshold used for the decision

Recommended splits:

- split by farm, market, phone/camera family, and capture date to avoid leakage
- keep flash/no-flash and repeat captures together in the same split
- hold out at least one region or market for robustness checks

Do not create moisture ground truth from visual appearance alone. Visual features
can support moisture-risk estimation, but calibrated moisture percentages need
meter or laboratory measurements.

# FAO and BIS-Aligned Ragi Rule Anchors

This file is the authoritative rule anchor used by the local lexical RAG layer.
It combines FAO grain-quality guidance with public Indian ragi market and
procurement thresholds that reference BIS-style foodgrain analysis terminology
and sampling methods.

The app is an operator-assist tool. It does not certify a lot. Official trade,
procurement, or food-safety decisions still require laboratory measurement,
sampling, and applicable legal standards.

## Source Notes

- FAO grain quality guidance describes moisture content, foreign matter,
  infested or infected grain, mixed varieties, colour, and bulk density as major
  quality and storage factors.
- FAO safe-storage guidance treats moisture control, clean stores, absence of
  insects, absence of mould odour, and inspection for heating or discoloured
  grain as essential storage controls.
- Public Indian ragi quality documents define ragi as finger millet
  (`Eleusine coracana`) and require it to be clean, wholesome, reasonably
  uniform in size, shape, and colour, and free from mould, weevils, obnoxious
  smell, fungus infestation, and deleterious substances.
- Public Indian procurement material references BIS foodgrain terminology,
  analysis, and sampling methods for refractions such as foreign matter,
  damaged grains, and impurities.

Reference URLs used when preparing this rule anchor:

- https://www.fao.org/4/t1838e/t1838e0h.htm
- https://www.fao.org/4/t1838e/t1838e0i.htm
- https://www.fao.org/4/V5380E/V5380E06.htm
- https://www.enam.gov.in/NAMV2/infrastructure/RAGI.pdf
- https://fci.gov.in/fci-storage/storage/app/uploads/662297b721c361713543095.pdf

## Hard Reject or Hold Gates

Assign `C` and recommend reject or hold if any of these are detected:

- visible mould or fungal growth
- live insects, weevils, webbing, or clear insect contamination
- obnoxious smell, sour smell, or visible heating/wet storage signs
- stones, glass, metallic pieces, mud lumps, or deleterious substances
- foreign matter greater than `1.0%`
- moisture greater than `14.0%` by weight for visual market grading
- damaged, weevilled, immature, and shrivelled grains greater than `9.5%`
- animal-origin impurities greater than `0.10%` if known
- mineral matter greater than `0.25%` if known

## Grade A Rule

Assign `A` only when all visible and measured evidence is in the premium range:

- moisture `<= 12.0%`
- foreign matter `<= 0.10%`
- other edible grains `<= 1.0%`
- damaged, weevilled, immature, and shrivelled grains `<= 3.1%`
- off-tone grain fraction `< 5.0%`
- size deviation `< 5.0%`
- shape defect fraction `< 5.0%`
- no mould, no insect evidence, no webbing, no stones, no strong clumping
- lot is visually uniform in size, shape, and colour

## Grade B Rule

Assign `B` only when the lot is usable but not premium:

- moisture `> 12.0% and <= 13.0%`, or visual moisture risk is moderate
- foreign matter `> 0.10% and <= 0.75%`
- other edible grains `> 1.0% and <= 2.0%`
- damaged, weevilled, immature, and shrivelled grains `> 3.1% and <= 6.3%`
- small off-tone or size variation is present but no hard reject gate is present

## Grade C Rule

Assign `C` when the lot is poor quality but still inside the outer visual market
range and no immediate food-safety hazard is proven:

- moisture `> 13.0% and <= 14.0%`
- foreign matter `> 0.75% and <= 1.0%`
- other edible grains `> 2.0% and <= 4.0%`
- damaged, weevilled, immature, and shrivelled grains `> 6.3% and <= 9.5%`
- off-tone grain fraction `> 10.0%`
- size deviation `> 15.0%`
- shape defect fraction `> 10.0%`
- broken or damaged grain estimate `> 5.0%`
- bimodal colour, mixed lot appearance, heavy dullness, or moisture clumping

## Moisture Interpretation

For this app, moisture is a separate safety/storage axis and can downgrade a
quality grade:

- `LOW`: `<= 12.0%`, Grade A may be allowed if all quality gates pass.
- `MODERATE`: `> 12.0% and <= 13.0%`, Grade A is blocked.
- `HIGH`: `> 13.0% and <= 14.0%`, Grade C or hold is preferred.
- `CRITICAL`: `> 14.0%`, reject or dry immediately before storage.

FAO safe-storage guidance is broader for millet storage, but Indian ragi market
grading is stricter. The rule engine therefore uses the stricter ragi thresholds
for grade decisions.

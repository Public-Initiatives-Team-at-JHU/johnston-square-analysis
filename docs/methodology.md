# Methodology

How the study area was chosen, how the estimates and margins of error are
calculated, and what to keep in mind when using them.

- [1. The study area](#1-the-study-area)
- [2. The 2005-2009 boundary change](#2-the-2005-2009-boundary-change)
- [3. Data](#3-data)
- [4. How the numbers are calculated](#4-how-the-numbers-are-calculated)
- [5. Reporting guidance](#5-reporting-guidance)
- [6. Known limitations](#6-known-limitations)

---

## 1. The study area

**Census Tract 1001, Baltimore City (GEOID `24510100100`)** stands in for the
Johnston Square neighborhood in every period. For 2005-2009 only, part of a
neighboring tract is added (see [section 2](#2-the-2005-2009-boundary-change)).

| ACS period | Tracts | Weight |
|---|---|---|
| 2005-2009 | `24510100100` + `24510100400` | 1.0 + **0.271** |
| 2010-2014 | `24510100100` | 1.0 |
| 2015-2019 | `24510100100` | 1.0 |
| 2020-2024 | `24510100100` | 1.0 |

The definition lives in [`R/js_study_area.R`](../R/js_study_area.R), and a
reference map is at `output/figures/00_study_area_map.png`.

### Why a census tract?

The American Community Survey (ACS) does not publish data for neighborhoods.
Its smallest reliable geography for these tables is the census tract, and
tracts don't line up with neighborhood boundaries. So the study area is an
approximation: the tract (or tracts) that best represent the neighborhood.

### How tract 1001 was chosen

The method is population-weighted areal apportionment. Census blocks fit
inside tracts and are small enough to split a neighborhood, so block
population can be divided between the neighborhood and the tracts:

1. Johnston Square's official boundary comes from Baltimore City's
   **Neighborhood Statistical Area (NSA)** layer on Open Baltimore
   (saved in `geo/johnston_square_nsa.geojson`).
2. 2020 census blocks were intersected with that boundary. Each block's 2020
   population was split by the share of its area inside the neighborhood.
3. The split population was summed by tract.

Re-run this with `Rscript R/js_geography.R`. It writes
`geo/js_tract_apportionment.csv`:

| Tract | Johnston Sq. residents in tract | % of Johnston Square | % of tract that is Johnston Square |
|---|---|---|---|
| **24510100100** | **1,638** | **81.9%** | **84.7%** |
| 24510090900 | 310 | 15.5% | 12.9% |
| 24510100200 | 26 | 1.3% | 1.0% |
| 24510120500 | 16 | 0.8% | 0.7% |
| 24510100300 | 11 | 0.5% | 0.5% |

*(2020 census. With 2010 blocks, 93.5% of Johnston Square falls in tract 1001.)*

Tract 1001 is mostly Johnston Square. The other 15% of its population lives
in Oliver, east of Ensor St / N. Eden St.

### Why not add tract 0909 too?

Adding tract 0909 would capture 97% of Johnston Square instead of 82%, but it
would make the study area *mostly not Johnston Square*:

|  | Tract 1001 only | 1001 + 0909 |
|---|---|---|
| Johnston Square residents captured | 1,638 | 1,948 |
| Other residents included | 296 | 2,391 |
| **Share of study area that is Johnston Square** | **84.7%** | **44.9%** |

Tract 0909 is 86% Oliver. Picking up its 310 Johnston Square residents would
bring in 2,079 Oliver residents.

**Where the line runs:** the tract's north edge is **E. Preston St**. Johnston
Square south of Preston St is all in tract 1001. The strip between Preston St
and E. Hoffman St (the neighborhood's north edge) is in tract 0909.

```
──────────── E. Hoffman St ────────────── (north edge of neighborhood)
   tract 0909 strip    7 blocks,   310 people
════════ E. Preston St ═══════ tract boundary ════════
   tract 1001 bulk    37 blocks, 1,638 people
──────────── E. Eager St ──────────────── (south edge of neighborhood and tract)
```

### For comparison: the EBDI study area

The method here comes from JHU's earlier East Baltimore Development
Initiative (EBDI) analysis. That study area is three whole tracts, and none
of them is more than 52% any one neighborhood. At 84.7%, tract 1001 is a
closer match to its neighborhood than the EBDI tracts were to theirs.

### The ReBUILD Johnston Square footprint

We checked whether ReBUILD Metro's redevelopment footprint should replace the
NSA boundary. It doesn't change the choice of tract:

- No published GIS boundary for the footprint exists. We checked Open
  Baltimore, rebuildmetro.com, city DHCD/LDA material, and parcel ownership
  records.
- ReBUILD's named project sites geocode to tract 1001: 700 Mura St,
  1100 and 1200 Greenmount Ave, and 800 E Chase St. The one exception is
  1300 Homewood Ave, which is in 0909.
- The footprint is part of the neighborhood, so using it could only make
  tract 1001 a closer fit, not a worse one.

---

## 2. The 2005-2009 boundary change

Census redrew tract boundaries for 2010. Tract 1001 grew from 0.211 to
0.293 sq mi by absorbing part of tract **1004** (`24510100400`), which was
then retired. The 2005-2009 ACS is published on the *old* boundaries, so
tract 1001 alone covers less ground in that period than it does later.

Neither simple fix is right:

| Approach | 2005-09 population | Problem |
|---|---|---|
| Tract 1001 alone | 2,044 | Understates by ~10%: misses the absorbed piece |
| Tract 1001 + all of 1004 | 2,852 | **Overstates by ~26%**: 73% of tract 1004 lies outside today's tract 1001 |
| **1001 + 0.271 × 1004** | **2,263** | **Used** |

**The weight 0.271** is the share of tract 1004's population (2010 census
blocks) that falls inside the modern tract 1001 boundary. Each tract 1004
estimate and margin of error is multiplied by 0.271 before anything is summed.
This is standard areal interpolation, the same approach NHGIS uses for its
time-series tables. The derivation is in `R/js_geography.R`, and its result
is saved in `geo/js_1004_weight.txt`.

**Why it matters:** without the adjustment, 2005-09 → 2020-24 reads as a 51%
population drop (2,852 → 1,404). With it, the drop is 38% (2,263 → 1,404).
That is still a steep decline, but about a quarter of the unadjusted drop
would be an artifact of the boundary change.

**Assumption to footnote:** the weight assumes people in tract 1004 had the
same characteristics throughout the tract. Treat it as accurate to about two
significant figures.

---

## 3. Data

| What | Source |
|---|---|
| Estimates | ACS 5-year detailed tables via the Census API ([`tidycensus`](https://walker-data.com/tidycensus/)): 2005-09, 2010-14, 2015-19, 2020-24 |
| Margins of error, 2010-14 onward | Census [Variance Replicate Tables](https://www.census.gov/programs-surveys/acs/data/variance-tables.html) (80 replicate estimates per cell), downloaded automatically into `data/replicate_weights/` |
| Neighborhood boundary | Open Baltimore, Neighborhood Statistical Areas |
| Tract and block geometry | TIGER/Line via `tigris` (2000, 2010 and 2020 versions) |
| Block population (for the study area only) | 2010 and 2020 Census redistricting data (PL 94-171) |

The four periods don't overlap. Census advises against comparing overlapping
5-year periods.

---

## 4. How the numbers are calculated

### Study-area estimates

For each ACS variable, the study-area estimate is the weighted sum of its
tracts. The MOE comes from the Census formula for a sum,
`moe_sum()` = √(Σ MOE²). Weights are applied to the tract rows *before*
summing (`apply_study_area()`), which works because MOE(a·X) = a·MOE(X).

### Shares (the descriptive tables)

Most indicators are reported as shares. For tables broken out by race, each
row has two:

- **`SPct` (share of the sub-total):** this race's count over the count for
  all races on the same table line. For example, among residents aged 35-44,
  the share who are Black.
- **`TPct` (share of the grand total):** this race's count on that line over
  the table's grand total. For example, Black residents aged 35-44 as a share
  of all residents.

All-race totals are rebuilt by summing the race-iteration tables (B, C, D, E,
F, G, H, I). Table "A" (White alone) is left out and "H" (White alone, not
Hispanic) is used instead, so White Hispanic residents aren't counted twice.

### Margins of error

- **Totals, 2010-14 onward:** from the 80 replicate estimates in the Variance
  Replicate Tables, as SE = √(4/80 · Σ(rep − est)²) and MOE = 1.96 × SE. This
  is more accurate than summing published MOEs.
- **Totals, 2005-09:** no replicate tables exist for this period, so these
  come from `moe_sum()`.
- **Shares:** Census's derived-proportion formula,
  MOE(P) = (1/den) · √(MOE_num² − P² · MOE_den²). When the term under the
  square root is negative, it falls back to the derived-ratio formula
  (+ instead of −), as Census recommends. R prints "NaNs produced" warnings
  when this happens. They are expected.

All MOEs are at the 95% confidence level. In the descriptive tables they are
in percentage points.

### Income

`income_*` files divide **aggregate** household income (B19025) by the number
of households (B11001), for each race of householder. This is *average*
household income, not median. Each period is in its own end year's dollars
(the ACS adjusts within the five years to the last one), so **periods are not
inflation-adjusted against each other**. Use the CPI-U to put them in
constant dollars before comparing.

---

## 5. Reporting guidance

- **No significance tests are reported** (decided September 2026). The study
  area is about 1,400 people today, too small for most period-to-period tests
  to give a clear answer. The EBDI analysis's Z-test code was removed from this
  repository for that reason.
- **Show or footnote MOEs whenever you compare periods.** The total-population
  MOE is about ±9-14% in 2005-09 and 2010-14, and about **±20-24%** in 2015-19
  and 2020-24. A small change between periods may just be noise.
- **Call it "Census Tract 1001" or "the Johnston Square study area"** when
  precision matters. It is 85% Johnston Square and 15% Oliver.
- **Footnote the 2005-2009 weight** wherever that period appears (see
  [section 2](#2-the-2005-2009-boundary-change)).

---

## 6. Known limitations

These are inherited from the EBDI analysis. They are kept as-is so results
stay comparable with it and with this project's frozen baseline. Changing any
of them changes the outputs; see [maintenance.md](maintenance.md).

1. **Citywide vacancy and income summaries leave out some tracts after 2009.**
   `city_vacants.csv` and `city_income_summary.csv` only include tracts that
   existed in the 2005-2009 ACS. From 2010-14 on, the 7-8 tracts that were
   renumbered are dropped, about **4% of city housing units**. For example,
   in 2020-24 they count 282,788 of 295,032 units. Rates are probably close
   to the true citywide figure, but counts are understated. Other `city_*`
   files use county-level data and are not affected.
2. **Some MOE cells are blank.** When a denominator is zero (e.g. a race with
   no residents in the study area), the share and its MOE can't be computed.
3. **2005-09 employment MOEs use the largest tract MOE** rather than
   `moe_sum()`. This quirk is inherited from EBDI.
4. **Labels come from the 2009 variable list.** Every period is labelled with
   2009's wording, which can differ slightly from later releases. For
   example, income labels say "2009 inflation-adjusted dollars" in every
   period.
5. **The 0.271 weight assumes tract 1004 was uniform in composition.** See
   [section 2](#2-the-2005-2009-boundary-change).

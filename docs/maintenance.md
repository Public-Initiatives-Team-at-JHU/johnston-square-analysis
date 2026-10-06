# Maintaining and extending the analysis

- [How the code fits together](#how-the-code-fits-together)
- [Checking a change](#checking-a-change)
- [Accepting new numbers](#accepting-new-numbers)
- [Adding a new ACS period](#adding-a-new-acs-period)
- [Reusing this for another neighborhood](#reusing-this-for-another-neighborhood)
- [Regenerating the geography and map](#regenerating-the-geography-and-map)
- [Troubleshooting](#troubleshooting)

---

## How the code fits together

```
js_analysis_2026.R          the pipeline: run this
 ├─ R/helpers.R             packages, API key check, MOE/replicate-weight math
 ├─ R/acs_variables.R       which ACS variables each indicator uses
 ├─ R/js_study_area.R       the study area's tracts and weights; apply_study_area()
 ├─ R/build_indicators.R    one builder per indicator; downloads replicate weights
 └─ R/js_plots.R            figures, drawn from the output CSVs

R/check_env.R               setup check
R/js_geography.R            re-derives the study area (standalone)
R/js_map.R                  draws the study-area map (standalone)

tests/test_study_area.R     unit checks for the tract weighting (seconds, offline)
tests/verify_baseline.R     compares output/ against tests/golden/
tests/golden/               the accepted output CSVs
```

`js_analysis_2026.R` runs in four steps:

1. **Build each period.** `build_vintage(year)` returns one study-area frame
   per indicator. Every raw ACS frame goes through `apply_study_area()`, which
   keeps the study area's tracts and multiplies each by its weight, before
   anything is summed.
2. **Descriptive tables.** `over_time()` lines the four periods up side by side
   and writes the ten `js_*_results.csv` / `js_educ_summary.csv` tables.
3. **Summaries.** Population by race (B03002), vacancy and income, for the
   study area and the city.
4. **Figures.** `make_js_plots()` reads the CSVs back in and draws the PNGs.

To iterate on the figures alone, without calling the Census API, run
`Rscript R/js_plots.R`. It takes seconds.

---

## Checking a change

After any change to the R code, run:

```bash
Rscript tests/test_study_area.R    # seconds: tract weighting unit checks
Rscript js_analysis_2026.R         # ~2 min: full run
Rscript tests/verify_baseline.R    # seconds: output/ vs tests/golden/
```

`verify_baseline.R` compares every CSV in `tests/golden/` with the same file
in `output/`. Numbers must agree to a relative tolerance of 1e-9, and text
must match exactly. **A refactor is safe only if it reports ALL PASS.**

Why two checks: the baseline proves results are *unchanged*. But a mistake in
the weighting can only show up in 2005-2009, the one period with a weight
other than 1, so `test_study_area.R` checks the weighting directly.

---

## Accepting new numbers

Sometimes numbers *should* change: Census revises a release, you fix a known
limitation, or you add a period. When that happens:

1. Run the analysis and `tests/verify_baseline.R`. Confirm that only the files
   and columns you expected have changed.
2. Re-freeze the baseline:

   ```bash
   cp output/*.csv tests/golden/
   ```

3. Commit `output/` and `tests/golden/` together, with a commit message saying
   why the numbers moved.

---

## Adding a new ACS period

The four periods don't overlap, following Census guidance. The next
non-overlapping period is **2025-2029**. If you want a more recent period
sooner (for example, swapping 2020-24 for 2021-25), note in the write-up that
periods overlap.

To add a period ending in year `YYYY` (two-digit suffix `YY`):

1. **`js_analysis_2026.R`**: add `"YY" = YYYY` to `VINTAGES`. In the
   `CITYWIDE AVG` block, add an `avg_income_YY` line, and in
   `city_pop_change.csv` add a `pop_YYYY` line.
2. **`R/js_study_area.R`**: add `YYYY` to `ANALYSIS_YEARS`. If Census redrew
   tract 1001 (expected for the 2030 census, which first affects ACS
   2026-2030), work out new weights the way section 2 of the
   [methodology](methodology.md#2-the-2005-2009-boundary-change) describes.
3. **`R/helpers.R`**: add `YYYY` to `REPLICATE_YEARS`, once Census has
   published the Variance Replicate Tables for that period. Census releases
   them separately from the main tables, sometimes later.
4. **`R/js_plots.R`**: add the period to `PERIODS` and `SUF`.
5. Check that the ACS variables still exist. Census occasionally renames or
   drops lines, especially in C23002 (employment) and C15002 (education).
6. Run, check, and re-freeze, as described above.

---

## Reusing this for another neighborhood

Only the study area is specific to Johnston Square:

1. Choose tracts with the apportionment method in
   [methodology.md](methodology.md#how-tract-1001-was-chosen).
   `R/js_geography.R` is a template: replace the boundary file in `geo/`.
2. In `R/js_study_area.R`, set `STUDY_AREA$label`, `STUDY_AREA$prefix` (used
   to name output files) and `STUDY_AREA$weights`. That is one row per
   (year, tract), with weight 1 for whole tracts. If any of the tracts changed
   boundaries in 2010, apportion them for 2009 as section 2 of the
   methodology describes.
3. Figure titles and the weighting footnote are generated from `STUDY_AREA`,
   but `R/js_map.R` names tract 1001 and its streets directly, so update it by
   hand.
4. Delete `tests/golden/` and freeze a new baseline from the first run.

---

## Regenerating the geography and map

Neither script is part of the main run, because the geography doesn't change
between runs.

```bash
Rscript R/js_geography.R   # re-derives the tract apportionment and the 0.271 weight
Rscript R/js_map.R         # redraws output/figures/00_study_area_map.png
```

Both download TIGER/Line shapefiles, which `tigris` caches after the first
run. `js_geography.R` also calls the Census API for block populations, and it
stops with an error if the weight it derives no longer matches 0.271.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `CENSUS_API_KEY is not set` | Run `tidycensus::census_api_key("YOUR KEY", install = TRUE)`, then restart R |
| A replicate-weight download times out | Re-run. Finished files are kept, and only missing ones are fetched. Or delete the partial file in `data/replicate_weights/YYYY/` |
| `GEOID(s) not found in input` | A study-area tract is missing from a Census response: check the API, the year, and the GEOIDs in `R/js_study_area.R` |
| `NaNs produced` warnings | Expected: the derived-proportion MOE formula falling back to the ratio formula (see [methodology](methodology.md#margins-of-error)) |
| Figures use a different font | Tahoma isn't installed. Numbers are unaffected |
| API errors or empty results | The Census API rate-limits and has occasional outages. Wait and re-run |

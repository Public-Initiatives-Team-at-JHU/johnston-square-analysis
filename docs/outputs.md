# Outputs

Everything the analysis writes to `output/`. Files starting with `js_` describe
the Johnston Square study area (Census Tract 1001). Files starting with `city_`
describe Baltimore City.

Periods are ACS 5-year estimates, labelled by their last year in column names:

| Suffix | Period |
|---|---|
| `09` / `2009` | 2005-2009 |
| `14` / `2014` | 2010-2014 |
| `19` / `2019` | 2015-2019 |
| `24` / `2024` | 2020-2024 |

> **Watch the units.** The descriptive tables (`*_results.csv`,
> `js_educ_summary.csv`) report **percentages from 0 to 100**. The summary
> files (`*_summary.csv`, `*_vacants.csv`) report **fractions from 0 to 1**.

- [Figures](#figures)
- [Population](#population)
- [Housing vacancy](#housing-vacancy)
- [Household income](#household-income)
- [Descriptive tables](#descriptive-tables)

---

## Figures

`output/figures/` holds PNGs at 300 dpi, sized for slides. Each figure is drawn
from the CSVs below, so it always matches the numbers delivered with it.

| File | Shows |
|---|---|
| `00_study_area_map.png` | Tract 1001 against the Johnston Square neighborhood boundary (made by `R/js_map.R`, not the main run) |
| `01_total_population.png` | Study-area population by period |
| `02_population_change.png` | % change between consecutive periods, study area vs city |
| `03_non_hispanic_black_share.png` | Non-Hispanic Black share of population, study area vs city |
| `04_hispanic_share.png` | Hispanic or Latino share, study area vs city |
| `05_household_income.png` | Average household income, study area vs city |
| `06_poverty_rate.png` | Poverty rate among Black residents of the study area |
| `07_educational_attainment.png` | Educational attainment, residents 25 and over |
| `08_vacancy_rate.png` | Vacancy rate, study area (with MOE error bars) vs city |

Colors stand for **geography** (dark blue = study area, light blue =
Baltimore City), never race, following JHU Public Impact brand guidance.

---

## Population

ACS table **B03002** (Hispanic or Latino origin by race).

### `js_pop_race_summary.csv`, `city_pop_race_summary.csv`

Population by race, with Hispanic and non-Hispanic members of each race
combined. One row per race.

| Column | Meaning |
|---|---|
| `label` | Race, e.g. `Black or African American alone` |
| `estimate_total_YY` | Number of people |
| `race_pct_pop_YY` | Share of the total population (0-1) |

Total population for a period is the sum of `estimate_total_YY`. 2005-09
study-area counts are fractional because of the 0.271 weight on tract 1004
(see [methodology](methodology.md#2-the-2005-2009-boundary-change)).

### `js_pop_hisp_summary.csv`, `city_pop_hisp_summary.csv`

Same columns, with two rows: Hispanic or Latino, and Not Hispanic or Latino.

### `js_non_hisp_black_summary.csv`, `city_non_hisp_black_summary.csv`

| Column | Meaning |
|---|---|
| `non_hisp_pct_YYYY` | Non-Hispanic Black residents as a share of the total population (0-1) |

### `city_pop_change.csv`

| Column | Meaning |
|---|---|
| `pop_YYYY` | Baltimore City total population |

---

## Housing vacancy

ACS table **B25002** (occupancy status).

### `js_vacants.csv`, `city_vacants.csv`

One row per period.

| Column | Meaning |
|---|---|
| `js_vacants` / `city_vacants` | Vacant housing units |
| `js_total_housing` / `city_total_housing` | All housing units |
| `js_vac_rate` / `city_vac_rate` | Vacant ÷ all units (0-1) |
| `year` | Last year of the period |

The study-area vacancy rate's MOE is in `js_vacants_results.csv` (below).
`city_vacants.csv` leaves out some renumbered tracts after 2009; see
[known limitations](methodology.md#6-known-limitations).

---

## Household income

ACS tables **B19025** (aggregate household income by race of householder) and
**B11001** (households by race of householder).

### `js_income_summary.csv`, `city_income_summary.csv`

One row per race of householder. The city file adds a `CITYWIDE AVG` row,
calculated as total income ÷ total households (not an average of the
per-race averages).

| Column | Meaning |
|---|---|
| `Race` | Race of householder |
| `tot_income_YY` | Aggregate household income, dollars |
| `tot_hh_YY` | Number of households |
| `avg_income_YY` | Average income per household, dollars |

These are **averages, not medians**. Each period is in its own end year's
dollars and is **not adjusted for inflation** between periods. `avg_income`
is blank where there are no households of that race. `city_income_summary.csv`
leaves out some renumbered tracts after 2009; see
[known limitations](methodology.md#6-known-limitations).

---

## Descriptive tables

Ten tables, one per ACS indicator, giving the study area's shares and their
margins of error in every period. All values are **percentages (0-100)**, and
MOEs are in percentage points at 95% confidence.

### Columns

| Column | Meaning |
|---|---|
| `Order` | Line number in the ACS table (race tables only) |
| `label` | ACS line description, e.g. `Estimate Total Female Bachelor's degree or higher` |
| `Race` | Race iteration of the ACS table (race tables only) |
| `SPct_YY` / `SMoe_YY` | **Share of the sub-total** and its MOE |
| `TPct_YY` / `TMoe_YY` | **Share of the grand total** and its MOE (race tables only) |

**Reading a race table.** Take the row `Estimate Total Female Bachelor's
degree or higher` / `BLACK OR AFRICAN` in `js_educ_summary.csv`:

- `SPct` = Black women with a bachelor's degree as a % of **all** women with a
  bachelor's degree in the study area (all races).
- `TPct` = Black women with a bachelor's degree as a % of **everyone** in the
  table's universe (all residents 25 and over).

For rates *within* a group (e.g. the poverty rate among Black residents),
divide the group's below-poverty row by its total row, using `TPct` (or the
underlying counts). `R/js_plots.R` does this for the poverty and education
figures.

Rows with 0 people in the denominator have blank shares and MOEs.

### The ten tables

| File | ACS table | Universe | By race? |
|---|---|---|---|
| `js_demographics_results.csv` | B01001 Sex by age | All residents | Yes |
| `js_tenure_results.csv` | B25003 Tenure (owner/renter) | Occupied housing units, by race of householder | Yes |
| `js_poverty_results.csv` | B17001 Poverty status in the past 12 months | Residents whose poverty status is determined | Yes |
| `js_educ_summary.csv` | C15002 Educational attainment by sex | Residents 25 and over | Yes |
| `js_occupancy_results.csv` | B25014 Occupants per room (crowding) | Occupied housing units | Yes |
| `js_employment_results.csv` | C23002 Employment status by sex and age | Residents 16 and over | Yes |
| `js_income_results.csv` | B19025 Aggregate household income | Households | Yes, see note |
| `js_rent_results.csv` | B25070 Gross rent as % of household income | Renter-occupied units | No |
| `js_mortgage_results.csv` | B25091 Owner costs as % of household income, by mortgage status | Owner-occupied units | No |
| `js_vacants_results.csv` | B25002 Occupancy status (vacant share) | All housing units | No |

**Income note.** In `js_income_results.csv`, `SPct` is each race's share of
all household income in the study area. `TPct`/`TMoe` are **average household
income in dollars**, not percentages. The label says "2009 inflation-adjusted
dollars" for every period because all labels come from the 2009 variable
list. In fact each period is in its own end year's dollars.

**Rent and mortgage note.** Each band's `SPct` is a share of the *whole*
table: all renter units, or all owner units with and without a mortgage. It
is not a share within its mortgage-status group.

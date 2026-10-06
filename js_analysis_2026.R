###############################################################################
# Johnston Square Analysis
#
# Describes the Johnston Square neighborhood of East Baltimore -- approximated
# by Census Tract 1001 -- across four non-overlapping ACS 5-year periods
# (2005-09, 2010-14, 2015-19, 2020-24), alongside Baltimore City.
#
# Pipeline
#   1. For each period, build ten study-area indicators (R/build_indicators.R).
#   2. Write the descriptive tables: each indicator's shares and MOEs over time.
#   3. Write the population, vacancy and income summaries for the study area
#      and for Baltimore City.
#   4. Draw the figures (R/js_plots.R).
#
# Run from the project root:   Rscript js_analysis_2026.R
# Needs CENSUS_API_KEY set (see README.md). Replicate-weight files (~550MB)
# are downloaded into data/replicate_weights/ on the first run only.
#
# Method adapted from the EBDI analysis (Marlene Caceres, 2021; consolidated
# 2026). See docs/methodology.md.
###############################################################################

message("Analysis start: ", Sys.time())
tic <- Sys.time()

source("R/helpers.R")           # libraries, API key check, statistical helpers
source("R/acs_variables.R")     # ACS variable lists, replicate-weight mvar maps
source("R/js_study_area.R")     # the study area's tracts and weights
source("R/build_indicators.R")  # one builder per indicator type

dir.create("output", showWarnings = FALSE)
ensure_replicate_weights(REPLICATE_YEARS)


###############################################################################
# 1. BUILD EACH PERIOD
###############################################################################

VINTAGES <- c("09" = 2009, "14" = 2014, "19" = 2019, "24" = 2024)

vintages <- list()
for (yy in names(VINTAGES)) {
  vintages[[yy]] <- build_vintage(VINTAGES[[yy]])
  message(VINTAGES[[yy]], " ACS data retrieved. Elapsed: ", format(Sys.time() - tic))
}

# Baltimore City tracts as defined in the 2005-2009 period. Inherited from the
# EBDI analysis, this list filters the citywide vacancy and income summaries
# in EVERY period -- see "Known limitations" in docs/methodology.md.
city_tracts <- sort(unique(vintages[["09"]]$vac_tracts$GEOID))


###############################################################################
# 2. DESCRIPTIVE TABLES
###############################################################################
#   SPct/SMoe = share of the sub-total (and its MOE), in percent
#   TPct/TMoe = share of the grand total (race indicators only)

races <- data.frame(
  Symbol = c("C", "D", "B", "I", "E", "F", "G", "H"),
  Race   = c("AMERICAN INDIAN AND ALASKA NATIVE", "ASIAN", "BLACK OR AFRICAN ",
             "HISPANIC OR LATINO", "NATIVE HAWAIIAN AND OTHER PACIFIC ISLANDER",
             "SOME OTHER RACE ", "TWO OR MORE", "WHITE, NOT HISPANIC OR LATINO")
)

#' One indicator's shares and MOEs across all periods, one row per variable.
over_time <- function(indicator, by_race) {
  stats <- c(SPct = "areaP", SMoe = "areamoep",
             if (by_race) c(TPct = "areaP2", TMoe = "areamoep2"))
  per_year <- lapply(names(VINTAGES), function(yy) {
    df <- vintages[[yy]][[indicator]][, c("variable", paste0(stats, yy))]
    setNames(df, c("variable", paste0(names(stats), "_", yy)))
  })
  df <- Reduce(function(a, b) full_join(a, b, by = "variable"), per_year)
  value_cols <- setdiff(names(df), "variable")    # SPct_09, SMoe_09, ..., in period order

  df$Order  <- as.numeric(substr(df$variable, 9, 11))
  df$Symbol <- substr(df$variable, 7, 7)
  df <- df %>%
    left_join(acs_labels, by = "variable") %>%
    left_join(races, by = "Symbol")
  df <- df[order(df$Order, df$Race), ]

  df[, c(if (by_race) c("Order", "label", "Race") else "label", value_cols)]
}

DESCRIPTIVE_TABLES <- list(
  demographics_results = list(indicator = "age",  by_race = TRUE),
  tenure_results       = list(indicator = "tenu", by_race = TRUE),
  poverty_results      = list(indicator = "pove", by_race = TRUE),
  educ_summary         = list(indicator = "educ", by_race = TRUE),
  occupancy_results    = list(indicator = "occu", by_race = TRUE),
  employment_results   = list(indicator = "labr", by_race = TRUE),
  income_results       = list(indicator = "inc",  by_race = TRUE),
  rent_results         = list(indicator = "rent", by_race = FALSE),
  mortgage_results     = list(indicator = "mort", by_race = FALSE),
  vacants_results      = list(indicator = "vac",  by_race = FALSE)
)

for (stem in names(DESCRIPTIVE_TABLES)) {
  t <- DESCRIPTIVE_TABLES[[stem]]
  write_csv(over_time(t$indicator, t$by_race), area_file(stem))
}


###############################################################################
# 3. STUDY AREA vs CITY SUMMARIES
###############################################################################

# B03002 (Hispanic or Latino origin by race), mutually exclusive groups.
race_tables <- c(
  "B03002_003E", "B03002_004E", "B03002_005E", "B03002_006E", "B03002_007E",
  "B03002_008E", "B03002_010E", "B03002_011E",                 # not Hispanic
  "B03002_013E", "B03002_014E", "B03002_015E", "B03002_016E", "B03002_017E",
  "B03002_018E", "B03002_020E", "B03002_021E"                  # Hispanic
)
hisp_tables <- c("B03002_002E", "B03002_012E")                 # not Hispanic / Hispanic

#' B03002 for Baltimore City ("county") or the study area ("tract"), labelled.
get_b03002 <- function(variables, year, geography) {
  df <- get_acs(geography = geography, variables = variables, year = year,
                state = "MD", county = CITY_COUNTY, survey = "acs5",
                moe_level = 95, show_call = FALSE)
  if (geography == "tract") df <- apply_study_area(df, year)
  left_join(df, acs_labels, by = "variable")
}

#' Population and share by label for one period, e.g. estimate_total_19 and
#' race_pct_pop_19. With `combine_hispanic`, Hispanic and non-Hispanic members
#' of the same race are combined by stripping the label prefix.
composition <- function(df, yy, combine_hispanic = FALSE) {
  if (combine_hispanic) {
    df <- mutate(df,
                 label = gsub("Estimate Total Not Hispanic or Latino ", "", label),
                 label = gsub("Estimate Total Hispanic or Latino ", "", label))
  }
  tot <- paste0("estimate_total_", yy)
  df %>%
    group_by(label) %>%
    summarise(!!tot := sum(estimate)) %>%
    mutate(!!paste0("race_pct_pop_", yy) := .data[[tot]] / sum(.data[[tot]]))
}

#' Non-Hispanic Black share of the total population for one period.
non_hisp_black_share <- function(df, year) {
  total <- sum(df$estimate)
  df %>%
    filter(variable == "B03002_004") %>%
    group_by(label) %>%
    summarise(estimate = sum(estimate)) %>%
    mutate(!!paste0("non_hisp_pct_", year) := estimate / total) %>%
    select(label, all_of(paste0("non_hisp_pct_", year)))
}

#' Join per-period results side by side.
join_vintages <- function(frames, by = "label") {
  Reduce(function(a, b) left_join(a, b, by = by), frames)
}

# --- population by race / ethnicity ---
for (geo in c("county", "tract")) {
  out  <- if (geo == "county") function(stem) file.path("output", paste0("city_", stem, ".csv")) else area_file
  race <- lapply(VINTAGES, function(y) get_b03002(race_tables, y, geo))
  hisp <- lapply(VINTAGES, function(y) get_b03002(hisp_tables, y, geo))

  pop_race <- join_vintages(Map(composition, race, names(VINTAGES), combine_hispanic = TRUE))
  write_csv(pop_race, out("pop_race_summary"))
  write_csv(join_vintages(Map(non_hisp_black_share, race, VINTAGES)), out("non_hisp_black_summary"))
  write_csv(join_vintages(Map(composition, hisp, names(VINTAGES))), out("pop_hisp_summary"))

  if (geo == "county") {
    pop_race %>%
      summarise(pop_2009 = sum(estimate_total_09),
                pop_2014 = sum(estimate_total_14),
                pop_2019 = sum(estimate_total_19),
                pop_2024 = sum(estimate_total_24)) %>%
      write_csv("output/city_pop_change.csv")
  }
}

# --- vacancy ---
city_vacants <- bind_rows(lapply(names(VINTAGES), function(yy) {
  vintages[[yy]]$vac_tracts %>%
    filter(GEOID %in% city_tracts) %>%
    summarise(city_vacants = sum(vacant), city_total_housing = sum(units)) %>%
    mutate(city_vac_rate = city_vacants / city_total_housing, year = VINTAGES[[yy]])
}))
area_vacants <- bind_rows(lapply(names(VINTAGES), function(yy) {
  v <- vintages[[yy]]$vac
  tibble(js_vacants       = v[[paste0("E_est",  yy)]],     # vacant units
         js_total_housing = v[[paste0("E_estT", yy)]]) %>%
    mutate(js_vac_rate = js_vacants / js_total_housing, year = VINTAGES[[yy]])
}))
write_csv(city_vacants, "output/city_vacants.csv")
write_csv(area_vacants, area_file("vacants"))

# --- average household income by race ---
#' Aggregate income / households by race, one period. `df` has variable,
#' income and households columns.
income_by_race <- function(df, yy) {
  df %>%
    mutate(Symbol = substr(variable, 7, 7)) %>%
    left_join(races, by = "Symbol") %>%
    group_by(Race) %>%
    summarise(!!paste0("tot_income_", yy) := sum(income),
              !!paste0("tot_hh_", yy)     := sum(households)) %>%
    mutate(!!paste0("avg_income_", yy) :=
             .data[[paste0("tot_income_", yy)]] / .data[[paste0("tot_hh_", yy)]])
}

city_income_summary <- join_vintages(by = "Race", lapply(names(VINTAGES), function(yy) {
  income_by_race(filter(vintages[[yy]]$inc_tracts, GEOID %in% city_tracts), yy)
}))
# Citywide row: aggregate income / aggregate households (NOT the mean of the
# per-race averages).
city_income_summary <- city_income_summary %>%
  bind_rows(
    city_income_summary %>%
      summarise(across(starts_with("tot_"), sum)) %>%
      mutate(Race          = "CITYWIDE AVG",
             avg_income_09 = tot_income_09 / tot_hh_09,
             avg_income_14 = tot_income_14 / tot_hh_14,
             avg_income_19 = tot_income_19 / tot_hh_19,
             avg_income_24 = tot_income_24 / tot_hh_24)
  )
write_csv(city_income_summary, "output/city_income_summary.csv")

area_income_summary <- join_vintages(by = "Race", lapply(names(VINTAGES), function(yy) {
  v <- vintages[[yy]]$inc
  income_by_race(tibble(variable   = v$variable,
                        income     = v[[paste0("E_est",   yy)]],
                        households = v[[paste0("E_estT2", yy)]]), yy)
}))
write_csv(area_income_summary, area_file("income_summary"))

message("Analysis complete. Elapsed: ", format(Sys.time() - tic))


###############################################################################
# 4. FIGURES
###############################################################################

source("R/js_plots.R")
make_js_plots()

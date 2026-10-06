###############################################################################
# js_study_area.R
#
# The Johnston Square study area: a YEAR-KEYED table of (tract GEOID, weight).
#
# For 2010-2014 onward it is simply Census Tract 1001 (24510100100). For
# 2005-2009 it also includes part of tract 1004 (24510100400), because 1001
# absorbed part of 1004 when tract boundaries were redrawn for 2010. 1004 enters
# at a population weight of 0.271. See docs/methodology.md.
###############################################################################

suppressPackageStartupMessages({library(dplyr); library(tibble); library(tidyr)})

# The share of retired tract 24510100400's population that fell inside the
# modern tract-24510100100 footprint, measured with 2010 census blocks.
# Re-derive with R/js_geography.R.
TRACT_1004_WEIGHT <- 0.271

ANALYSIS_YEARS <- c(2009, 2014, 2019, 2024)

STUDY_AREA <- list(
  label   = "Johnston Square",
  prefix  = "js",     # output file prefix: output/js_*.csv
  weights = bind_rows(
    crossing(year = ANALYSIS_YEARS, GEOID = "24510100100") %>% mutate(w = 1),
    tibble(year = 2009, GEOID = "24510100400", w = TRACT_1004_WEIGHT)
  )
)

#' Restrict an ACS frame to the study area, scaling each tract by its weight.
#'
#' Scales `estimate`, `moe` and, in replicate tables, the 80 Var_Rep columns.
#' Scaling raw rows before any aggregation means every later sum and moe_sum()
#' works unchanged: MOE(aX) = a * MOE(X) for a constant a.
#'
#' @param df ACS frame with GEOID, estimate and moe columns
#' @param year ACS end year (2009, 2014, 2019 or 2024)
#' @param replicate TRUE for Census Variance Replicate Tables, whose GEOIDs
#'   carry a "14000US" prefix
apply_study_area <- function(df, year, area = STUDY_AREA, replicate = FALSE) {
  w <- area$weights[area$weights$year == year, c("GEOID", "w")]
  if (nrow(w) == 0) stop("study area '", area$label, "' has no weights for ", year)
  if (replicate) w$GEOID <- paste0("14000US", w$GEOID)

  # Fail loudly if a tract is absent -- e.g. a GEOID-format mismatch -- rather
  # than silently summing fewer tracts than the study area contains.
  missing <- setdiff(w$GEOID, df$GEOID)
  if (length(missing) > 0) {
    stop("study area '", area$label, "' (", year, "): GEOID(s) not found in input: ",
         paste(missing, collapse = ", "))
  }
  if (!all(c("estimate", "moe") %in% names(df))) {
    stop("apply_study_area: frame needs estimate and moe columns (columns: ",
         paste(names(df), collapse = ", "), ")")
  }

  value_cols <- c("estimate", "moe", grep("^Var_Rep[0-9]+$", names(df), value = TRUE))
  df %>%
    inner_join(w, by = "GEOID") %>%
    mutate(across(all_of(value_cols), ~ .x * w)) %>%
    select(-w)
}

# Output file for this study area, e.g. area_file("vacants") -> output/js_vacants.csv
area_file <- function(stem) file.path("output", paste0(STUDY_AREA$prefix, "_", stem, ".csv"))

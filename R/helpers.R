###############################################################################
# helpers.R
#
# Setup and the statistical helpers. Sourced at the top of js_analysis_2026.R.
#
# Adapted from the EBDI analysis (JHU Public Impact, 2021-2026). The arithmetic
# is unchanged from that project; any edit here must leave output/ matching
# tests/golden/ -- see docs/verification.md.
###############################################################################

suppressPackageStartupMessages({
  library(tidycensus)
  library(tidyverse)
})

# --- Census API key ----------------------------------------------------------
# tidycensus reads the key from the CENSUS_API_KEY environment variable. Set it
# once per machine with
#   tidycensus::census_api_key("YOUR KEY", install = TRUE)
# then restart R. Free keys: https://api.census.gov/data/key_signup.html
if (!nzchar(Sys.getenv("CENSUS_API_KEY"))) {
  stop("CENSUS_API_KEY is not set. See 'Quick start' in README.md.", call. = FALSE)
}

# --- shared constants --------------------------------------------------------

# Baltimore City's county FIPS code (state 24, Maryland).
CITY_COUNTY <- "510"

# Where the Census Variance Replicate Table CSVs are downloaded to (see
# ensure_replicate_weights() in R/build_indicators.R). Not committed to git.
REPLICATE_DIR <- file.path("data", "replicate_weights")

# The ACS 5-year vintages that carry replicate weights. 2005-2009 has none, so
# its MOEs are derived from published MOEs instead.
REPLICATE_YEARS <- c(2014, 2019, 2024)

# The 80 successive-difference replicate columns in the replicate tables.
REP_COLS <- paste0("Var_Rep", 1:80)

# --- ACS variable labels -----------------------------------------------------
# Readable label for each variable code, e.g. "Estimate Total Male". Every
# vintage is labelled from the 2009 table, as in the EBDI analysis (changing it
# would change the labels in the output CSVs).
acs_labels <- load_variables(2009, "acs5") %>%
  select(variable = name, label) %>%
  mutate(label = gsub("!!", " ", label))


# --- replicate-weight helpers ------------------------------------------------

#' Aggregate estimates, MOEs and the 80 replicate columns within groups.
#'
#' IMPORTANT: dplyr evaluates summarise() arguments in order, so the `estimate`
#' passed to moe_sum() is the ALREADY-SUMMED value from the line above, not the
#' original vector. The EBDI code relied on this, so the order is load-bearing.
sum_reps <- function(df, ...) {
  df %>%
    group_by(...) %>%
    summarise(estimate = sum(estimate),
              moe      = moe_sum(moe, estimate),
              across(all_of(REP_COLS), sum))
}

#' Standard error from Census successive-difference replicate weights.
#'
#'   Variance = (4 / 80) * sum_{i=1..80} (Var_Rep_i - estimate)^2
#'   SE       = sqrt(Variance)
#'   moef     = SE * 1.96          (95% MOE, matching moe_level = 95 below)
replicate_se <- function(df, estimate_col = "estimate") {
  reps <- as.matrix(dplyr::select(ungroup(df), all_of(REP_COLS)))
  df$Variance <- (rowSums((reps - df[[estimate_col]])^2) * 4) / 80
  df$SE       <- sqrt(df$Variance)
  df$moef     <- df$SE * 1.96
  df
}


# --- derived proportion MOE --------------------------------------------------

#' Margin of error for a derived proportion, with the Census ratio fallback.
#'
#' The Census Bureau's derived-PROPORTION formula is
#'
#'   MOE(P) = (1 / den) * sqrt( num_moe^2 - P^2 * den_moe^2 )
#'
#' When the radicand goes negative the square root is NaN, and the Bureau
#' directs you to fall back to the derived-RATIO formula, which adds instead of
#' subtracts. (A run prints "NaNs produced" warnings for exactly this reason;
#' they are expected.)
#'
#' `P_fallback` preserves a quirk of the EBDI original: in the share-of-grand-
#' total series the fallback uses the PRIMARY proportion. It shaped the
#' published EBDI numbers, so it is reproduced rather than corrected.
derived_moe <- function(P, num_moe, den, den_moe, P_fallback = P) {
  m <- ((1 / den) * (sqrt(((num_moe^2) - ((P^2) * (den_moe^2))))))
  if_else(is.na(m),
          ((1 / den) * (sqrt(((num_moe^2) + ((P_fallback^2) * (den_moe^2)))))),
          m)
}

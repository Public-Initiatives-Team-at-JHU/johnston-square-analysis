#!/usr/bin/env Rscript
###############################################################################
# test_study_area.R
#
# Unit checks for apply_study_area() in R/js_study_area.R. Runs in seconds,
# offline:
#
#   Rscript tests/test_study_area.R
#
# These matter because the baseline check (tests/verify_baseline.R) only
# proves results are unchanged; it cannot tell you a brand-new weighting is
# right. The 2005-2009 weight of 0.271 is the one place where a scaling bug
# would change numbers, so it is tested directly here.
###############################################################################
suppressPackageStartupMessages(library(dplyr))
source("R/js_study_area.R")

fails <- 0
check <- function(label, expr) {
  res <- tryCatch(isTRUE(expr), error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n"); FALSE
  })
  cat(sprintf("%-62s %s\n", label, if (res) "PASS" else "FAIL"))
  if (!res) fails <<- fails + 1
}
eq <- function(a, b) isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = 1e-9))
raises <- function(expr, pattern = NULL) {
  e <- tryCatch({ force(expr); NULL }, error = function(e) e)
  inherits(e, "error") && (is.null(pattern) || grepl(pattern, conditionMessage(e), fixed = TRUE))
}

# A minimal ACS-shaped frame: both study-area tracts plus an unrelated one.
fake <- tibble::tibble(
  GEOID    = c("24510100100", "24510100400", "24510999999"),
  variable = "B01003_001",
  estimate = c(1000, 1000, 9999),
  moe      = c(100, 100, 999)
)

# --- 2005-2009: tract 1004 enters at 0.271 -----------------------------------
a09 <- apply_study_area(fake, 2009)
check("2009 returns exactly the 2 study-area tracts",  setequal(a09$GEOID, c("24510100100", "24510100400")))
check("2009 tract 1001 estimate unscaled",             eq(a09$estimate[a09$GEOID == "24510100100"], 1000))
check("2009 tract 1004 estimate scaled by the weight",
      eq(a09$estimate[a09$GEOID == "24510100400"], 1000 * TRACT_1004_WEIGHT))
check("2009 MOE scales linearly with the weight",
      eq(a09$moe[a09$GEOID == "24510100400"], 100 * TRACT_1004_WEIGHT))
check("2009 sum is weighted, not naive and not tract 1001 alone",
      eq(sum(a09$estimate), 1000 + 1000 * TRACT_1004_WEIGHT))
check("weight column is not left behind",              !"w" %in% names(a09))

# --- later periods: tract 1001 only, unscaled --------------------------------
for (y in c(2014, 2019, 2024)) {
  ay <- apply_study_area(fake, y)
  check(sprintf("%d returns only tract 1001, unscaled", y),
        identical(ay$GEOID, "24510100100") && eq(ay$estimate, 1000) && eq(ay$moe, 100))
}

# --- whole tracts at weight 1 behave exactly like a plain filter -------------
whole <- list(label = "whole tracts", weights = tibble::tibble(
  year = 2014, GEOID = c("24510100100", "24510100400"), w = 1))
check("weight-1 area equals filter(GEOID %in% ...)",
      isTRUE(all.equal(apply_study_area(fake, 2014, area = whole),
                       filter(fake, GEOID %in% c("24510100100", "24510100400")))))

# --- replicate tables: 14000US-prefixed GEOIDs, Var_Rep columns scale --------
fake_rep <- tibble::tibble(
  GEOID    = c("14000US24510100100", "14000US24510100400", "14000US24510999999"),
  estimate = c(1000, 1000, 9999),
  moe      = c(100, 100, 999),
  Var_Rep1 = c(1010, 1010, 9999),
  Var_Rep2 = c( 990,  990, 9999)
)
r24 <- apply_study_area(fake_rep, 2024, replicate = TRUE)
check("replicate: matches the 14000US prefix",          nrow(r24) == 1)
check("replicate: 2024 Var_Rep unscaled at weight 1",   eq(r24$Var_Rep1, 1010))
r09 <- apply_study_area(fake_rep, 2009, replicate = TRUE)
check("replicate: Var_Rep scales by the weight",
      eq(r09$Var_Rep2[r09$GEOID == "14000US24510100400"], 990 * TRACT_1004_WEIGHT))
check("replicate: estimate scales by the weight",
      eq(r09$estimate[r09$GEOID == "14000US24510100400"], 1000 * TRACT_1004_WEIGHT))

# --- mismatches must raise, never silently return fewer tracts ---------------
check("errors on 14000US GEOIDs without replicate = TRUE",
      raises(apply_study_area(fake_rep, 2024)))
check("errors on plain GEOIDs with replicate = TRUE",
      raises(apply_study_area(fake, 2024, replicate = TRUE)))
check("errors, naming the tract, when a 2009 tract is missing",
      raises(apply_study_area(filter(fake, GEOID != "24510100400"), 2009), "24510100400"))
check("errors for a year with no weights",
      raises(apply_study_area(fake, 2011)))
check("errors, naming the columns, when estimate/moe are absent",
      raises(apply_study_area(rename(fake, Population = estimate), 2024), "Population"))

# Long-format frames carry several rows per tract. Dropping tract 1004 still
# leaves more matched rows than weight rows, so coverage must be checked by
# GEOID set, not row count.
fake_long <- tibble::tibble(
  GEOID    = c(rep("24510100100", 3), "24510100400"),
  variable = c("B01003_001", "B01001_001", "B17001_002", "B01003_001"),
  estimate = c(1000, 900, 250, 1000),
  moe      = c(100, 90, 25, 100)
)
check("long-format frame sums correctly",
      eq(sum(apply_study_area(fake_long, 2009)$estimate),
         1000 + 900 + 250 + 1000 * TRACT_1004_WEIGHT))
check("missing tract caught even when rows outnumber weights",
      raises(apply_study_area(filter(fake_long, GEOID != "24510100400"), 2009), "24510100400"))

cat(sprintf("\n%d failure(s)\n", fails))
quit(status = if (fails == 0) 0 else 1)

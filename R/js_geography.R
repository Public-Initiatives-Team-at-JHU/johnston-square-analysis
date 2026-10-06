#!/usr/bin/env Rscript
###############################################################################
# js_geography.R
#
# Re-derives the Johnston Square tract selection in docs/methodology.md.
# Standalone -- the analysis does not source this. Needs CENSUS_API_KEY.
#
#   Rscript R/js_geography.R
###############################################################################
suppressPackageStartupMessages({
  library(sf); library(tigris); library(tidycensus); library(dplyr)
})
options(tigris_use_cache = TRUE, tigris_progress = FALSE)

js <- st_read("geo/johnston_square_nsa.geojson", quiet = TRUE) %>% st_transform(3857)

blocks_pop <- function(year, var) {
  b <- blocks(state = "MD", county = "510", year = year) %>% st_transform(3857)
  names(b)[names(b) %in% c("GEOID20", "GEOID10")] <- "GEOID"
  p <- get_decennial("block", variables = var, state = "MD", county = "510",
                     year = year, sumfile = "pl") %>% select(GEOID, pop = value)

  # Fail loudly rather than let a degraded API response reach the output files.
  # Every PL-94-171 block carries a population (possibly 0), so an NA here means
  # the join failed, not that data is legitimately missing.
  stopifnot(nrow(b) > 0, nrow(p) > 0)
  out <- b %>% select(GEOID) %>% left_join(p, by = "GEOID") %>%
    mutate(ba = as.numeric(st_area(geometry)))
  stopifnot(!any(is.na(out$pop)))
  out
}

# --- 1. apportion Johnston Square across 2020 tracts -------------------------
b20 <- blocks_pop(2020, "P1_001N")
i   <- st_intersection(b20, st_geometry(js))
i$oa <- as.numeric(st_area(i))
ap <- i %>% st_drop_geometry() %>%
  mutate(frac = oa / ba, pop_in = pop * frac, tract = substr(GEOID, 1, 11)) %>%
  filter(frac > 0.01) %>%
  group_by(tract) %>% summarise(js_pop = round(sum(pop_in)), .groups = "drop")
tot <- b20 %>% st_drop_geometry() %>% mutate(tract = substr(GEOID, 1, 11)) %>%
  group_by(tract) %>% summarise(tract_pop = sum(pop), .groups = "drop")
ap <- ap %>% left_join(tot, by = "tract") %>%
  mutate(pct_of_JS    = round(100 * js_pop / sum(js_pop), 1),
         pct_of_tract = round(100 * js_pop / tract_pop, 1)) %>%
  arrange(desc(js_pop))
write.csv(ap, "geo/js_tract_apportionment.csv", row.names = FALSE)
cat("\n--- Johnston Square by 2020 tract ---\n"); print(as.data.frame(ap), row.names = FALSE)

# --- 2. derive the 2009 weight for retired tract 1004 ------------------------
t00 <- tracts("MD", "510", year = 2000) %>% st_transform(3857)
t00$G <- t00$CTIDFP00
t20 <- tracts("MD", "510", year = 2020) %>% st_transform(3857)
b10 <- blocks_pop(2010, "P001001")
pop_in <- function(poly) {
  x <- st_intersection(b10, poly); x$oa <- as.numeric(st_area(x))
  sum(x$pop * x$oa / x$ba)
}
g1004 <- st_geometry(t00[t00$G == "24510100400", ])
g1001 <- st_geometry(t20[t20$GEOID == "24510100100", ])
w <- pop_in(st_intersection(g1004, g1001)) / pop_in(g1004)
cat(sprintf("\nTract 1004 weight for 2005-2009: %.4f\n", w))
writeLines(c(
  sprintf("# %s  derived by R/js_geography.R", Sys.Date()),
  "# share of 2000-vintage tract 24510100400 population falling inside the",
  "# 2020-vintage tract 24510100100 footprint, apportioned with 2010 blocks",
  sprintf("%.4f", w)
), "geo/js_1004_weight.txt")

stopifnot(abs(w - 0.271) < 0.01)
cat("\nMatches TRACT_1004_WEIGHT in R/js_study_area.R\n")

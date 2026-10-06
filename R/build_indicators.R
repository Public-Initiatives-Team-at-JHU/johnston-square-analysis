###############################################################################
# build_indicators.R
#
# One builder per indicator type. Each returns a STUDY-AREA frame for one ACS
# vintage, one row per ACS variable:
#
#   E_est/E_moe       the study-area estimate and MOE (sum over its tracts)
#   E_estT/E_moeT     the matching table total            -> share of sub-total
#   E_estT2/E_moeT2   the table's grand total             -> share of everyone
#   areaP/areamoep    share of the sub-total and its MOE, in percent
#   areaP2/areamoep2  share of the grand total and its MOE, in percent
#
# Column names carry a two-digit vintage suffix (E_est19, areaP219, ...).
#
# Two data sources:
#   * 2005-2009: published ACS tables only (no replicate weights exist), so
#     totals are built by summing the race tables and MOEs come from moe_sum().
#   * 2010-2014 onward: totals come from the Census Variance Replicate Tables,
#     so their MOEs come from the 80 replicate weights (replicate_se()).
#
# Adapted from the EBDI analysis. Several steps look inconsistent between
# tables (e.g. employment 2009 MOEs use max()); they are inherited and kept so
# results match the published method. Each is commented where it occurs.
###############################################################################

# --- small utilities ---------------------------------------------------------

#' Two-digit suffix used in column names: 2019 -> "19".
year_suffix <- function(year) substr(as.character(year), 3, 4)

#' Strip the race-iteration letter: "B01001B_013" -> "B01001_013".
race_to_mvar <- function(variable) {
  paste(substr(variable, 1, 6), substr(variable, 8, 11), sep = "")
}

#' Append the vintage suffix to every column except the join keys.
suffix_year <- function(df, yy, keep = c("GEOID", "variable", "mvar")) {
  rename_with(df, ~ paste0(.x, yy), .cols = !any_of(keep))
}

#' Fetch one ACS 5-year table for every tract in Baltimore City.
get_city_acs <- function(variables, year) {
  get_acs(geography = "tract", variables = variables, year = year,
          state = "MD", county = CITY_COUNTY, survey = "acs5",
          moe_level = 95, show_call = FALSE)
}

#' Shares of the sub-total (and grand total, when `two_series`) with their
#' derived MOEs, converted to percentages. The grand-total MOE falls back on
#' the PRIMARY proportion -- the inherited P_fallback quirk (see derived_moe()).
add_share_stats <- function(df, two_series = TRUE) {
  df$areaP <- df$E_est / df$E_estT
  if (two_series) df$areaP2 <- df$E_est / df$E_estT2

  df$areamoep <- derived_moe(df$areaP, df$E_moe, df$E_estT, df$E_moeT)
  if (two_series) {
    df$areamoep2 <- derived_moe(df$areaP2, df$E_moe, df$E_estT2, df$E_moeT2, df$areaP)
  }

  pct <- intersect(c("areaP", "areamoep", "areaP2", "areamoep2"), names(df))
  df[pct] <- lapply(df[pct], function(x) x * 100)
  df
}


# --- replicate-weight files ---------------------------------------------------

REPLICATE_TABLES <- c("B01001", "B25003", "B17001", "B15002", "B25014",
                      "B25002", "B25070", "B25091", "B23001")

REPLICATE_BASE_URL <- "https://www2.census.gov/programs-surveys/acs/replicate_estimates/"

#' Local path of one replicate-weight CSV. The "_24" is Maryland's state FIPS
#' code, not a year: these are the Maryland tract-level files.
replicate_path <- function(table, year) {
  file.path(REPLICATE_DIR, year, paste0(table, "_24.csv"))
}

#' Download and extract any replicate-weight CSV that isn't already on disk.
#'
#' Files already present are never touched, so the ~550MB download happens
#' once. Delete a CSV to force it to be fetched again.
ensure_replicate_weights <- function(years = REPLICATE_YEARS) {
  old <- options(timeout = max(1200, getOption("timeout")))
  on.exit(options(old))

  for (year in years) {
    for (table in REPLICATE_TABLES) {
      csv <- replicate_path(table, year)
      if (file.exists(csv) && file.size(csv) > 0) next

      dir.create(dirname(csv), recursive = TRUE, showWarnings = FALSE)
      # Census publishes 2014 as .gz and later vintages as .zip.
      ext     <- if (year == 2014) ".gz" else ".zip"
      archive <- paste0(csv, ext)
      url     <- paste0(REPLICATE_BASE_URL, year, "/data/5-year/140/",
                        basename(csv), ext)               # 140 = census tract
      message("Downloading ", url)
      download.file(url, destfile = archive, mode = "wb")

      if (ext == ".gz") {
        R.utils::gunzip(archive, destname = csv, remove = TRUE, overwrite = TRUE)
      } else {
        unzip(archive, exdir = dirname(csv), overwrite = TRUE)
        # The .zip archives store the CSV under a "140/" folder.
        nested <- file.path(dirname(csv), "140", basename(csv))
        if (file.exists(nested)) file.rename(nested, csv)
        unlink(file.path(dirname(csv), "140"), recursive = TRUE)
        unlink(archive)
      }
      if (!file.exists(csv)) stop("Could not extract ", csv)
    }
  }
}

#' Read one replicate-weight file and normalise it across vintages.
#'
#'  * drops the two title/universe header rows (all-NA numeric columns);
#'  * 2019+ files use ESTIMATE/MOE, 2014 uses estimate/moe;
#'  * 2024 files write tract GEOIDs as "1400000US..." instead of "14000US...".
read_replicate <- function(table, year) {
  df <- read_csv(replicate_path(table, year), show_col_types = FALSE,
                 progress = FALSE)
  df <- na.omit(df)
  if ("ESTIMATE" %in% names(df)) df <- rename(df, estimate = ESTIMATE, moe = MOE)
  df$GEOID <- sub("^1400000US", "14000US", df$GEOID)
  df
}

#' Replicate-weight totals summed over the study area, one row per mvar, with
#' MOE from the replicate weights. Returns mvar, E_estT, E_moeT.
area_replicate_totals <- function(rep, year) {
  e <- rep %>%
    apply_study_area(year, replicate = TRUE) %>%
    sum_reps(mvar) %>%
    replicate_se()
  e <- e[, c("mvar", "estimate", "moef")]
  rename(e, E_estT = estimate, E_moeT = moef)
}

#' Keep the single grand-total row and rename its columns to the "2" series,
#' e.g. E_estT -> E_estT2.
grand_total <- function(df, total_mvar) {
  df <- filter(df, mvar == total_mvar)
  df <- rename_with(df, ~ paste0(.x, "2"), .cols = c("E_estT", "E_moeT"))
  df$mvar <- NULL
  df
}

#' Study-area sum per ACS variable, from a raw get_acs() frame.
area_sum <- function(acs, year, agg_moe = moe_sum) {
  apply_study_area(acs, year) %>%
    group_by(variable) %>%
    summarise(E_est = sum(estimate), E_moe = agg_moe(moe, estimate))
}


# --- SET A: indicators broken down by race -----------------------------------

# One entry per race-table indicator. `replicate` is the all-races table whose
# replicate weights supply the totals from 2010-2014 on.
SET_A_TABLES <- list(
  age  = list(vars = agebysexV, replicate = "B01001", total = "B01001_001"),
  tenu = list(vars = teu,       replicate = "B25003", total = "B25003_001"),
  pove = list(vars = poe,       replicate = "B17001", total = "B17001_001"),
  educ = list(vars = edu,       replicate = "B15002", total = "C15002_001"),
  occu = list(vars = ocu,       replicate = "B25014", total = "B25014_001"),
  labr = list(vars = labV,      replicate = "B23001", total = "C23002_001")
)

#' Race-table indicator for a replicate-weight vintage (2014 onward).
build_race_table <- function(year, spec) {
  rep <- read_replicate(spec$replicate, year)
  rep$mvar <- if (spec$replicate %in% names(MVAR_MAPS)) {
    assign_mvar(rep$ORDER, spec$replicate)
  } else {
    sprintf("%s_%03d", rep$TBLID, rep$ORDER)
  }
  e_tot <- area_replicate_totals(rep, year)

  e <- area_sum(get_city_acs(spec$vars, year), year)
  e$mvar <- race_to_mvar(e$variable)
  e <- left_join(e, e_tot, by = "mvar")
  e <- merge(e, grand_total(e_tot, spec$total))   # attach the one grand-total row

  suffix_year(add_share_stats(e), year_suffix(year))
}

#' Race-table indicator for 2005-2009 (published tables only): totals are the
#' sum of the race tables.
#'
#' Inherited quirk: employment (labr) aggregates MOEs with max() rather than
#' moe_sum() -- pass `agg_moe = function(m, e) max(m)`.
build_race_table_2009 <- function(spec, agg_moe = moe_sum) {
  rows <- apply_study_area(get_city_acs(spec$vars, 2009), 2009)
  rows$mvar <- race_to_mvar(rows$variable)

  e <- rows %>%
    group_by(variable) %>%
    summarise(E_est = sum(estimate), E_moe = agg_moe(moe, estimate))
  e$mvar <- race_to_mvar(e$variable)
  e_tot <- rows %>%
    group_by(mvar) %>%
    summarise(E_estT = sum(estimate), E_moeT = agg_moe(moe, estimate))
  e <- merge(left_join(e, e_tot, by = "mvar"), grand_total(e_tot, spec$total))

  suffix_year(add_share_stats(e), "09")
}

#' Aggregate household income by race (B19025) per household (B11001).
#'
#' The primary series is each race's share of all aggregate income; the "2"
#' series is average income per household (dollars, not a percentage, and its
#' MOE uses the derived-RATIO formula). Income never uses replicate weights.
#'
#' Returns list(area = study-area frame, tracts = per-tract income and
#' households for every city tract, used for the citywide summary).
build_income <- function(year) {
  yy <- year_suffix(year)

  # Negative MOEs are Census annotation codes, not real values; they are
  # zeroed along with any missing values.
  inc <- get_city_acs(i_num, year)
  inc$moe <- if_else(inc$moe < 0, 0, inc$moe)
  inc[is.na(inc)] <- 0

  # Households by race, relabelled B11001x_001 -> B19025x_001 to line up.
  hh <- get_city_acs(i_den, year)
  hh$variable <- paste("B19025", substr(hh$variable, 7, 11), sep = "")

  e <- area_sum(inc, year)
  e$mvar <- race_to_mvar(e$variable)
  e_tot <- e %>%
    group_by(mvar) %>%
    summarise(E_estT = sum(E_est), E_moeT = moe_sum(E_moe, E_est))
  e_hh <- area_sum(hh, year) %>% rename(E_estT2 = E_est, E_moeT2 = E_moe)

  area <- e %>%
    left_join(e_tot, by = "mvar") %>%
    left_join(e_hh,  by = "variable")
  area <- add_share_stats(area, two_series = FALSE)
  area$areaP2    <- area$E_est / area$E_estT2
  area$areamoep2 <- ((1 / area$E_estT2) * (sqrt(((area$E_moe^2) + ((area$areaP2^2) * (area$E_moeT2^2))))))

  tracts <- inc %>%
    select(GEOID, variable, income = estimate) %>%
    left_join(select(hh, GEOID, variable, households = estimate),
              by = c("GEOID", "variable"))

  list(area = suffix_year(area, yy), tracts = tracts)
}


# --- SET B: housing indicators (not by race) ---------------------------------

#' Vacancy (B25002_003 vacant / B25002_001 all units).
#'
#' Returns list(area = study-area frame, tracts = vacant and total units for
#' every city tract, used for the citywide summary).
build_vacancy <- function(year) {
  yy <- year_suffix(year)

  if (year == 2009) {
    num <- get_city_acs(vacv,  2009)
    den <- get_city_acs(vactx, 2009)
    area <- area_sum(num, year) %>%
      mutate(mvar = vactx) %>%
      left_join(area_sum(den, year) %>% rename(mvar = variable, E_estT = E_est, E_moeT = E_moe),
                by = "mvar")
  } else {
    rep <- read_replicate("B25002", year)
    rep <- rep[startsWith(rep$GEOID, paste0("14000US24", CITY_COUNTY)), ]
    num <- filter(rep, ORDER == 3) %>% mutate(mvar = vacv)
    den <- filter(rep, ORDER == 1) %>% mutate(mvar = vactx)
    v <- area_replicate_totals(num, year)
    u <- area_replicate_totals(den, year)
    area <- tibble(variable = vacv, mvar = vactx,
                   E_est = v$E_estT, E_moe = v$E_moeT, E_estT = u$E_estT, E_moeT = u$E_moeT)
    num$GEOID <- substr(num$GEOID, 8, 18)
    den$GEOID <- substr(den$GEOID, 8, 18)
  }

  tracts <- select(num, GEOID, vacant = estimate) %>%
    left_join(select(den, GEOID, units = estimate), by = "GEOID")

  list(area = suffix_year(add_share_stats(area, two_series = FALSE), yy),
       tracts = tracts)
}

#' Housing-cost burden distribution (rent B25070 or mortgage B25091) from the
#' replicate tables (2014 onward): each band's share of the table total.
build_burden_table <- function(year, table) {
  total <- paste0(table, "_001")
  rep <- read_replicate(table, year)
  rep$variable <- sprintf("%s_%03d", table, rep$ORDER)
  rep$mvar     <- total

  area_reps <- function(df) {
    df %>%
      apply_study_area(year, replicate = TRUE) %>%
      group_by(ORDER, variable, mvar) %>%
      summarise(est = sum(estimate), across(all_of(REP_COLS), sum),
                .groups = "drop") %>%
      replicate_se("est")
  }
  e_num <- area_reps(filter(rep, ORDER != 1))
  e_num <- rename(e_num[, c("variable", "mvar", "est", "moef")], E_est = est, E_moe = moef)
  e_den <- area_reps(filter(rep, ORDER == 1))
  e_den <- rename(e_den[, c("mvar", "est", "moef")], E_estT = est, E_moeT = moef)

  out <- left_join(e_num, e_den, by = "mvar")
  suffix_year(add_share_stats(out, two_series = FALSE), year_suffix(year))
}

#' Housing-cost burden for 2005-2009 (published tables): each band over the
#' table total.
build_burden_table_2009 <- function(num_vars, den_var) {
  e_num <- area_sum(get_city_acs(num_vars, 2009), 2009)
  e_num$mvar <- den_var
  e_den <- area_sum(get_city_acs(den_var, 2009), 2009) %>%
    rename(mvar = variable, E_estT = E_est, E_moeT = E_moe)

  out <- left_join(e_num, e_den, by = "mvar")
  suffix_year(add_share_stats(out, two_series = FALSE), "09")
}


# --- one vintage, all indicators ---------------------------------------------

#' Build every indicator for one vintage. Returns a named list of study-area
#' frames -- age, inc, labr, occu, pove, tenu, educ (SET A, by race) and vac,
#' rent, mort (SET B, housing) -- plus the per-tract city frames `vac_tracts`
#' and `inc_tracts`.
build_vintage <- function(year) {
  vac <- build_vacancy(year)
  inc <- build_income(year)

  ind <- if (year == 2009) {
    t <- SET_A_TABLES
    list(
      age  = build_race_table_2009(t$age),
      tenu = build_race_table_2009(t$tenu),
      pove = build_race_table_2009(t$pove),
      educ = build_race_table_2009(t$educ),
      occu = build_race_table_2009(t$occu),
      labr = build_race_table_2009(t$labr, agg_moe = function(m, e) max(m)),
      rent = build_burden_table_2009(r_num, r_den),
      mort = build_burden_table_2009(m_num, m_den)
    )
  } else {
    c(lapply(SET_A_TABLES, function(spec) build_race_table(year, spec)),
      list(rent = build_burden_table(year, "B25070"),
           mort = build_burden_table(year, "B25091")))
  }

  c(ind, list(inc = inc$area, vac = vac$area,
              inc_tracts = inc$tracts, vac_tracts = vac$tracts))
}

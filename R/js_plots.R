###############################################################################
# js_plots.R
#
# Deck-ready figures from the output CSVs. Sourced at the end of
# js_analysis_2026.R; also runs standalone against an existing output/ in a
# few seconds, which is the fast way to iterate on the figures:
#
#   Rscript R/js_plots.R
#
# Writes PNGs to output/figures/. Reads only the CSVs, so a figure can never
# disagree with the numbers delivered alongside it.
#
# Reporting rules (decided 2026-09-29): no significance tests; show MOEs where
# the CSVs carry them (vacancy). JHU PII brand: Tahoma, Heritage Blue leads.
# Series colours denote geography, never race -- race appears only as a
# filter ("Black households"), per the brand's rule against race-colour
# mappings.
###############################################################################

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(ggplot2); library(scales)
})

if (!exists("STUDY_AREA")) {
  source("R/js_study_area.R")
}

JS_COL <- c(
  heritage = "#002D72",   # study area
  spirit   = "#68ACE5",   # Baltimore City
  homewood = "#008767",   # third series
  grid     = "#D9D9D6",
  muted    = "#5B6770",
  ink      = "#31261D"
)
EDU_RAMP <- c("#B9D8F3", "#68ACE5", "#0077D8", "#002D72")   # less -> more education
PERIODS  <- c("2005-2009", "2010-2014", "2015-2019", "2020-2024")
SUF      <- c("09", "14", "19", "24")

theme_js <- function() {
  theme_minimal(base_family = "Tahoma", base_size = 11) +
    theme(
      plot.title         = element_text(face = "bold", colour = JS_COL[["heritage"]], size = 14),
      plot.subtitle      = element_text(colour = JS_COL[["muted"]], size = 10,
                                        margin = margin(b = 8)),
      plot.caption       = element_text(colour = JS_COL[["muted"]], size = 8, hjust = 0,
                                        margin = margin(t = 10), lineheight = 1.2),
      plot.caption.position = "plot",
      plot.title.position   = "plot",
      axis.text          = element_text(colour = JS_COL[["muted"]]),
      axis.title         = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.minor   = element_blank(),
      panel.grid.major.y = element_line(colour = JS_COL[["grid"]], linewidth = 0.3),
      legend.position    = "top",
      legend.justification = "left",
      legend.title       = element_blank(),
      legend.text        = element_text(colour = JS_COL[["ink"]]),
      plot.background    = element_rect(fill = "white", colour = NA),
      plot.margin        = margin(12, 16, 10, 12)
    )
}

make_js_plots <- function(out_dir = "output", fig_dir = file.path(out_dir, "figures"),
                          area = STUDY_AREA) {
  dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)
  rd    <- function(f) read_csv(file.path(out_dir, f), show_col_types = FALSE)
  area_csv <- function(stem) paste0(area$prefix, "_", stem, ".csv")
  label <- area$label
  city  <- "Baltimore City"
  geo_cols <- setNames(c(JS_COL[["heritage"]], JS_COL[["spirit"]]), c(label, city))
  src <- "Source: U.S. Census Bureau, American Community Survey 5-year estimates."

  # Footnote any fractional tract weight (Johnston Square's 2005-2009 apportionment).
  frac <- filter(area$weights, w < 1)
  weight_note <- if (nrow(frac)) {
    paste0(" 2005-2009 includes retired tract ", frac$GEOID[1], " at a population weight of ",
           format(frac$w[1]), ", to match the post-2010 boundary.")
  } else ""

  period <- function(x) factor(x, levels = PERIODS)
  wide_to_long <- function(df, prefix, geo) {
    tibble(geo = geo, period = period(PERIODS),
           value = unlist(df[1, paste0(prefix, SUF)], use.names = FALSE))
  }
  bar_labels <- function(fmt, ...) {
    geom_text(aes(label = fmt(value)), vjust = -0.5, size = 3.2, family = "Tahoma",
              colour = JS_COL[["ink"]], ...)
  }
  dodge <- position_dodge(width = 0.8)
  save <- function(p, name, w = 8, h = 4.8) {
    cap <- p$labels$caption
    if (!is.null(cap)) {
      p$labels$caption <- paste(strwrap(unlist(strsplit(cap, "\n")), width = 150), collapse = "\n")
    }
    ggsave(file.path(fig_dir, name), p, width = w, height = h, dpi = 300,
           device = ragg::agg_png, bg = "white")
    name
  }
  written <- character()

  # 1. Total population ----------------------------------------------------------
  pr  <- rd(area_csv("pop_race_summary"))
  pop <- tibble(period = period(PERIODS),
                value  = vapply(SUF, function(s) sum(pr[[paste0("estimate_total_", s)]]), 0))
  p <- ggplot(pop, aes(period, value)) +
    geom_col(fill = JS_COL[["heritage"]], width = 0.6) +
    bar_labels(label_comma(accuracy = 1)) +
    scale_y_continuous(labels = label_comma(), expand = expansion(mult = c(0, 0.1))) +
    labs(title = paste(label, "total population"),
         caption = paste0(src, weight_note)) +
    theme_js()
  written <- c(written, save(p, "01_total_population.png"))

  # 2. Population change between periods ------------------------------------------
  cp  <- rd("city_pop_change.csv")
  cpv <- unlist(cp[1, paste0("pop_20", SUF)], use.names = FALSE)
  steps <- c("2005-09 to 2010-14", "2010-14 to 2015-19", "2015-19 to 2020-24")
  chg <- function(x) diff(x) / head(x, -1)
  pc <- tibble(geo   = factor(rep(c(label, city), each = 3), levels = c(label, city)),
               step  = factor(rep(steps, 2), levels = steps),
               value = c(chg(pop$value), chg(cpv)))
  p <- ggplot(pc, aes(step, value, fill = geo)) +
    geom_col(position = dodge, width = 0.75) +
    geom_text(aes(label = label_percent(accuracy = 0.1)(value),
                  vjust = ifelse(value < 0, 1.5, -0.5)),
              position = dodge, size = 3.2, family = "Tahoma", colour = JS_COL[["ink"]]) +
    geom_hline(yintercept = 0, colour = JS_COL[["muted"]], linewidth = 0.3) +
    scale_fill_manual(values = geo_cols) +
    scale_y_continuous(labels = label_percent(), expand = expansion(mult = 0.15)) +
    labs(title = "Population change between periods",
         subtitle = "Percent change between consecutive ACS 5-year periods",
         caption = paste0(src, weight_note)) +
    theme_js()
  written <- c(written, save(p, "02_population_change.png"))

  # 3. Non-Hispanic Black share ----------------------------------------------------
  nhb <- bind_rows(
    wide_to_long(rd(area_csv("non_hisp_black_summary")), "non_hisp_pct_20", label),
    wide_to_long(rd("city_non_hisp_black_summary.csv"), "non_hisp_pct_20", city)
  ) %>% mutate(geo = factor(geo, levels = c(label, city)))
  p <- ggplot(nhb, aes(period, value, fill = geo)) +
    geom_col(position = dodge, width = 0.75) +
    bar_labels(label_percent(accuracy = 1), position = dodge) +
    scale_fill_manual(values = geo_cols) +
    scale_y_continuous(labels = label_percent(), limits = c(0, 1.08),
                       expand = expansion(mult = c(0, 0))) +
    labs(title = "Non-Hispanic Black share of population",
         subtitle = "Black or African American alone, not Hispanic or Latino",
         caption = paste0(src, weight_note)) +
    theme_js()
  written <- c(written, save(p, "03_non_hispanic_black_share.png"))

  # 4. Hispanic or Latino share -------------------------------------------------------
  hl <- "Estimate Total Hispanic or Latino"
  hs <- bind_rows(
    wide_to_long(filter(rd(area_csv("pop_hisp_summary")), label == hl), "race_pct_pop_", label),
    wide_to_long(filter(rd("city_pop_hisp_summary.csv"), label == hl), "race_pct_pop_", city)
  ) %>% mutate(geo = factor(geo, levels = c(label, city)))
  p <- ggplot(hs, aes(period, value, fill = geo)) +
    geom_col(position = dodge, width = 0.75) +
    bar_labels(label_percent(accuracy = 0.1), position = dodge) +
    scale_fill_manual(values = geo_cols) +
    scale_y_continuous(labels = label_percent(), expand = expansion(mult = c(0, 0.12))) +
    labs(title = "Hispanic or Latino share of population",
         subtitle = "Hispanic or Latino of any race",
         caption = paste0(src, " Small counts: period-to-period movement for ", label,
                          " is within the margin of error.")) +
    theme_js()
  written <- c(written, save(p, "04_hispanic_share.png"))

  # 5. Average household income ---------------------------------------------------------
  inc  <- rd(area_csv("income_summary"))  %>% mutate(Race = trimws(Race))
  cinc <- rd("city_income_summary.csv") %>% mutate(Race = trimws(Race))
  inc_levels <- c(paste(label, "Black households", sep = ", "),
                  "Baltimore City, Black households", "Baltimore City, all households")
  ic <- bind_rows(
    wide_to_long(filter(inc,  Race == "BLACK OR AFRICAN"), "avg_income_", inc_levels[1]),
    wide_to_long(filter(cinc, Race == "BLACK OR AFRICAN"), "avg_income_", inc_levels[2]),
    wide_to_long(filter(cinc, Race == "CITYWIDE AVG"),     "avg_income_", inc_levels[3])
  ) %>% mutate(geo = factor(geo, levels = inc_levels))
  d3 <- position_dodge(width = 0.85)
  p <- ggplot(ic, aes(period, value, fill = geo)) +
    geom_col(position = d3, width = 0.8) +
    geom_text(aes(label = label_dollar(accuracy = 1, scale = 1e-3, suffix = "k")(value)),
              position = d3, vjust = -0.5, size = 2.9, family = "Tahoma",
              colour = JS_COL[["ink"]]) +
    scale_fill_manual(values = setNames(c(JS_COL[["heritage"]], JS_COL[["spirit"]],
                                          JS_COL[["homewood"]]), inc_levels)) +
    scale_y_continuous(labels = label_dollar(scale = 1e-3, suffix = "k"),
                       expand = expansion(mult = c(0, 0.1))) +
    guides(fill = guide_legend(nrow = 1)) +
    labs(title = "Average household income",
         subtitle = "Aggregate household income / households",
         caption = paste0(src, " Each period is in its own end-year dollars, not adjusted to ",
                          "a common year.\n", label, " shows Black households only; other ",
                          "groups have too few households to estimate.")) +
    theme_js()
  written <- c(written, save(p, "05_household_income.png"))

  # 6. Poverty rate, Black residents -----------------------------------------------------
  pv <- rd(area_csv("poverty_results")) %>%
    mutate(Race = trimws(Race)) %>% filter(Race == "BLACK OR AFRICAN")
  tot <- filter(pv, label == "Estimate Total")
  blw <- filter(pv, label == "Estimate Total Income in the past 12 months below poverty level")
  stopifnot(nrow(tot) == 1, nrow(blw) == 1)
  povr <- tibble(period = period(PERIODS),
                 value  = vapply(SUF, function(s) blw[[paste0("TPct_", s)]] /
                                                  tot[[paste0("TPct_", s)]], 0))
  p <- ggplot(povr, aes(period, value)) +
    geom_col(fill = JS_COL[["heritage"]], width = 0.6) +
    bar_labels(label_percent(accuracy = 1)) +
    scale_y_continuous(labels = label_percent(), expand = expansion(mult = c(0, 0.1))) +
    labs(title = paste0("Poverty rate, Black residents of ", label),
         subtitle = "Share with income in the past 12 months below the poverty level",
         caption = paste0(src, weight_note)) +
    theme_js()
  written <- c(written, save(p, "06_poverty_rate.png"))

  # 7. Educational attainment ---------------------------------------------------------------
  ed <- rd(area_csv("educ_summary"))
  lv <- c("Less than high school"        = "Less than high school diploma",
          "High school graduate or GED"  = "High school graduate, GED, or alternative",
          "Some college or associate's"  = "Some college or associate's degree",
          "Bachelor's degree or higher"  = "Bachelor's degree or higher")
  edu <- bind_rows(lapply(names(lv), function(nm) {
    rows <- filter(ed, label %in% paste("Estimate Total", c("Male", "Female"), lv[[nm]]))
    tibble(level = nm, period = period(PERIODS),
           value = vapply(SUF, function(s) sum(rows[[paste0("TPct_", s)]]) / 100, 0))
  })) %>%
    group_by(period) %>% mutate(value = value / sum(value)) %>% ungroup() %>%
    mutate(level = factor(level, levels = rev(names(lv))))
  p <- ggplot(edu, aes(period, value, fill = level)) +
    geom_col(width = 0.6, colour = "white", linewidth = 0.4) +
    geom_text(aes(label = label_percent(accuracy = 1)(value), group = level,
                  colour = level %in% names(lv)[3:4]),
              position = position_stack(vjust = 0.5), size = 3.2, family = "Tahoma",
              show.legend = FALSE) +
    scale_colour_manual(values = c(`TRUE` = "white", `FALSE` = JS_COL[["ink"]]), guide = "none") +
    scale_fill_manual(values = setNames(rev(EDU_RAMP), rev(names(lv))),
                      breaks = names(lv)) +
    scale_y_continuous(labels = label_percent(), expand = expansion(mult = c(0, 0.02))) +
    guides(fill = guide_legend(nrow = 1)) +
    labs(title = "Educational attainment, residents 25 and over",
         caption = paste0(src, " Male + female, summed across race groups (the EBDI method), ",
                          "then normalised to 100%.", weight_note)) +
    theme_js()
  written <- c(written, save(p, "07_educational_attainment.png"))

  # 8. Vacancy rate, with MOE ------------------------------------------------------------------
  vac  <- rd(area_csv("vacants")) %>% arrange(year)
  cvac <- rd("city_vacants.csv") %>% arrange(year)
  moe  <- unlist(rd(area_csv("vacants_results"))[1, paste0("SMoe_", SUF)], use.names = FALSE) / 100
  vr <- bind_rows(
    tibble(geo = label, period = period(PERIODS), value = vac$js_vac_rate, moe = moe),
    tibble(geo = city,  period = period(PERIODS), value = cvac$city_vac_rate, moe = NA_real_)
  ) %>% mutate(geo = factor(geo, levels = c(label, city)))
  p <- ggplot(vr, aes(period, value, fill = geo)) +
    geom_col(position = dodge, width = 0.75) +
    geom_errorbar(aes(ymin = pmax(value - moe, 0), ymax = value + moe),
                  position = dodge, width = 0.2, colour = JS_COL[["muted"]], linewidth = 0.4,
                  na.rm = TRUE) +
    geom_text(aes(y = ifelse(is.na(moe), value, value + moe),
                  label = label_percent(accuracy = 1)(value)),
              position = dodge, vjust = -0.6, size = 3.2, family = "Tahoma",
              colour = JS_COL[["ink"]]) +
    scale_fill_manual(values = geo_cols) +
    scale_y_continuous(labels = label_percent(), expand = expansion(mult = c(0, 0.1))) +
    labs(title = "Vacant housing units, share of all units",
         subtitle = paste0("Error bars: ", label, " margin of error (1.96 x standard error)"),
         caption = paste0(src, " No significance tests are reported.", weight_note)) +
    theme_js()
  written <- c(written, save(p, "08_vacancy_rate.png"))

  cat("wrote", length(written), "figures to", fig_dir, "\n")
  invisible(file.path(fig_dir, written))
}

# Standalone: Rscript R/js_plots.R
if (sys.nframe() == 0) make_js_plots()

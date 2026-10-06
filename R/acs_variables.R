###############################################################################
# acs_variables.R
#
# ACS variable lists and the replicate-weight "mvar" maps. Data, not logic.
# Adapted unchanged from the EBDI analysis.
###############################################################################

# --- ACS variable lists ------------------------------------------------------

# ACS race iteration codes. "A" (White alone) is deliberately excluded: study-area
# totals are rebuilt by summing the race tables, and "H" (White alone, not
# Hispanic) is used in its place so White Hispanics are not double counted.
#   B Black   C AIAN   D Asian   E NHPI   F Other   G Two+   H White non-Hisp   I Hispanic
RACES <- c("B", "C", "D", "E", "F", "G", "H", "I")

#' Variable codes for one table across all eight race iterations, e.g.
#' race_vars("B25003", 1:3) -> B25003B_001, B25003B_002, ..., B25003I_003.
#' Race varies slowest, matching the order the original script listed them in.
race_vars <- function(table, lines) {
  as.vector(t(outer(RACES, lines,
                    function(r, n) sprintf("%s%s_%03d", table, r, n))))
}

# SET A: indicators broken down by race.
agebysexV <- race_vars("B01001", 1:31)                         # age by sex
teu       <- race_vars("B25003", 1:3)                          # tenure
poe       <- race_vars("B17001", c(1, 2, 3, 17, 31, 32, 46))   # poverty
edu       <- race_vars("C15002", 1:11)                         # education
ocu       <- race_vars("B25014", 1:3)                          # occupants per room
labV      <- race_vars("C23002", 1:27)                         # employment
i_num     <- race_vars("B19025", 1)                            # aggregate household income
i_den     <- race_vars("B11001", 1)                            # households

# SET B: housing indicators, not broken down by race (2005-2009 only; later
# vintages read these tables from the replicate-weight files).
vacv  <- "B25002_003"                                # vacant units
vactx <- "B25002_001"                                # all housing units
r_num <- sprintf("B25070_%03d", 2:11)                # rent burden bands
r_den <- "B25070_001"
m_num <- sprintf("B25091_%03d", 2:23)                # mortgage burden bands
m_den <- "B25091_001"


# --- replicate-weight mvar maps ----------------------------------------------
#
# The replicate-weight files only exist for the all-races tables (B01001,
# B15002, B25014, B23001), which are more detailed than the race-iteration
# tables they are compared against. These maps collapse each detailed row
# (identified by its ORDER, i.e. line number) onto the race-table line it
# corresponds to -- the "matching variable" or mvar.
#
# Rows whose ORDER is not listed fall into "<table>_999", which never matches
# anything downstream.
#
# The maps are identical for 2014, 2019 and 2024. (Two errors in the old 2023
# maps were fixed in the EBDI project in Aug 2026.)

MVAR_MAPS <- list(
  B01001 = list(                               # age by sex -> B01001 race tables
    default = "B01001_999",
    map = list(
      B01001_001 = 1,  B01001_002 = 2,  B01001_003 = 3,  B01001_004 = 4,
      B01001_005 = 5,  B01001_006 = 6,  B01001_007 = 7,
      B01001_008 = c(8, 9, 10),       B01001_009 = 11,  B01001_010 = 12,
      B01001_011 = c(13, 14),         B01001_012 = c(15, 16),
      B01001_013 = c(17, 18, 19),     B01001_014 = c(20, 21, 22),
      B01001_015 = c(23, 24),         B01001_016 = 25,  B01001_017 = 26,
      B01001_018 = 27,  B01001_019 = 28,  B01001_020 = 29,  B01001_021 = 30,
      B01001_022 = 31,  B01001_023 = c(32, 33, 34),     B01001_024 = 35,
      B01001_025 = 36,  B01001_026 = c(37, 38),         B01001_027 = c(39, 40),
      B01001_028 = c(41, 42, 43),     B01001_029 = c(44, 45, 46),
      B01001_030 = c(47, 48),         B01001_031 = 49
    )
  ),
  B15002 = list(                               # education -> C15002 race tables
    default = "C15002_999",
    map = list(
      C15002_001 = 1,  C15002_002 = 2,  C15002_003 = 3:10,  C15002_004 = 11,
      C15002_005 = 12:14,  C15002_006 = 15:18,  C15002_007 = 19,
      C15002_008 = 20:27,  C15002_009 = 28,  C15002_010 = 29:31,
      C15002_011 = 32:35
    )
  ),
  B25014 = list(                               # occupants per room
    default = "B25014_999",
    map = list(
      B25014_001 = 1,
      B25014_002 = c(3, 4, 9, 10),
      B25014_003 = c(5, 6, 7, 11, 12, 13)
    )
  ),
  B23001 = list(                               # employment -> C23002 race tables
    default = "C23002_999",
    map = list(
      C23002_001 = 1,  C23002_002 = 2,
      # Male, 16-64: seven-row blocks, one block per age band (10 bands)
      C23002_003 = seq(3, 66, 7),  C23002_004 = seq(4, 67, 7),
      C23002_005 = seq(5, 68, 7),  C23002_006 = seq(6, 69, 7),
      C23002_007 = seq(7, 70, 7),  C23002_008 = seq(8, 71, 7),
      C23002_009 = seq(9, 72, 7),
      # Male, 65+: five-row blocks (3 bands)
      C23002_010 = c(73, 78, 83),  C23002_011 = c(74, 79, 84),
      C23002_012 = c(75, 80, 85),  C23002_013 = c(76, 81, 86),
      C23002_014 = c(77, 82, 87),
      C23002_015 = 88,
      # Female, 16-64
      C23002_016 = seq(89, 152, 7),  C23002_017 = seq(90, 153, 7),
      C23002_018 = seq(91, 154, 7),  C23002_019 = seq(92, 155, 7),
      C23002_020 = seq(93, 156, 7),  C23002_021 = seq(94, 157, 7),
      C23002_022 = seq(95, 158, 7),
      # Female, 65+
      C23002_023 = c(159, 164, 169),  C23002_024 = c(160, 165, 170),
      C23002_025 = c(161, 166, 171),  C23002_026 = c(162, 167, 172),
      C23002_027 = c(163, 168, 173)
    )
  )
)

#' Look up the mvar for each ORDER in a replicate-weight file.
assign_mvar <- function(order, table) {
  spec <- MVAR_MAPS[[table]]
  lookup <- setNames(rep(names(spec$map), lengths(spec$map)),
                     unlist(spec$map, use.names = FALSE))
  out <- unname(lookup[as.character(order)])
  ifelse(is.na(out), spec$default, out)
}

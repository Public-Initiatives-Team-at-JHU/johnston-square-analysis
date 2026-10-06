#!/usr/bin/env Rscript
###############################################################################
# verify_baseline.R
#
# Regression check: are the output CSVs unchanged?
#
# Compares every CSV in tests/golden/ against the same file in output/.
# Numeric columns are compared with a relative tolerance (default 1e-9);
# text columns must match exactly. Run it after js_analysis_2026.R:
#
#   Rscript tests/verify_baseline.R [golden_dir] [test_dir] [tolerance]
#
# A code change is safe only when this reports ALL PASS. If numbers changed on
# purpose (e.g. a new ACS release), re-freeze with
#   cp output/*.csv tests/golden/
# and say why in the commit message.
###############################################################################
suppressPackageStartupMessages(library(readr))

args       <- commandArgs(trailingOnly = TRUE)
golden_dir <- if (length(args) >= 1) args[1] else "tests/golden"
test_dir   <- if (length(args) >= 2) args[2] else "output"
tol        <- if (length(args) >= 3) as.numeric(args[3]) else 1e-9

# --- helpers ----------------------------------------------------------------

# Read every column as character so that type-guessing differences between the
# two files can never masquerade as a data difference. We decide numeric-ness
# ourselves, below, using BOTH files' contents.
read_all_chr <- function(path) {
  read_csv(path,
           col_types = cols(.default = col_character()),
           progress  = FALSE,
           show_col_types = FALSE)
}

# TRUE if every non-missing entry parses cleanly as a number.
is_numericish <- function(x) {
  x_trim <- trimws(x)
  present <- !is.na(x_trim) & x_trim != ""
  if (!any(present)) return(TRUE)          # all-empty column: treat as numeric-compatible
  parsed <- suppressWarnings(as.numeric(x_trim[present]))
  !any(is.na(parsed))
}

# Compare one column. Returns list(ok, detail).
compare_column <- function(g, t, tol) {
  # Normalise missingness: "" and NA are the same absence in a CSV round-trip.
  norm <- function(x) { x <- trimws(x); x[x == ""] <- NA_character_; x }
  g <- norm(g); t <- norm(t)

  na_mismatch <- xor(is.na(g), is.na(t))
  if (any(na_mismatch)) {
    idx <- which(na_mismatch)
    return(list(ok = FALSE, detail = sprintf(
      "NA pattern differs at %d row(s); first at row %d (golden=%s, test=%s)",
      length(idx), idx[1],
      ifelse(is.na(g[idx[1]]), "NA", g[idx[1]]),
      ifelse(is.na(t[idx[1]]), "NA", t[idx[1]]))))
  }

  both <- !is.na(g)
  if (!any(both)) return(list(ok = TRUE, detail = "all NA"))

  if (is_numericish(g) && is_numericish(t)) {
    gn <- as.numeric(g[both]); tn <- as.numeric(t[both])
    # Absolute-or-relative tolerance: robust for both tiny and huge magnitudes.
    denom <- pmax(1, abs(gn))
    diff  <- abs(gn - tn) / denom
    bad   <- which(diff > tol)
    if (length(bad)) {
      i <- bad[which.max(diff[bad])]
      return(list(ok = FALSE, detail = sprintf(
        "%d numeric cell(s) exceed tol; worst rel.diff %.3g (golden=%.10g test=%.10g)",
        length(bad), max(diff[bad]), gn[i], tn[i])))
    }
    return(list(ok = TRUE, detail = sprintf("numeric, max rel.diff %.3g", max(diff))))
  }

  bad <- which(g[both] != t[both])
  if (length(bad)) {
    return(list(ok = FALSE, detail = sprintf(
      "%d text cell(s) differ; first: golden=%s test=%s",
      length(bad), g[both][bad[1]], t[both][bad[1]])))
  }
  list(ok = TRUE, detail = "text exact")
}

compare_file <- function(fname, golden_dir, test_dir, tol) {
  gpath <- file.path(golden_dir, fname)
  tpath <- file.path(test_dir,  fname)

  if (!file.exists(tpath)) {
    return(list(file = fname, status = "MISSING", detail = "not produced by test run"))
  }

  g <- read_all_chr(gpath)
  t <- read_all_chr(tpath)

  if (nrow(g) != nrow(t)) {
    return(list(file = fname, status = "FAIL",
                detail = sprintf("row count %d -> %d", nrow(g), nrow(t))))
  }
  if (!identical(names(g), names(t))) {
    only_g <- setdiff(names(g), names(t)); only_t <- setdiff(names(t), names(g))
    if (length(only_g) || length(only_t)) {
      return(list(file = fname, status = "FAIL", detail = sprintf(
        "columns differ (golden-only: %s | test-only: %s)",
        paste(only_g, collapse = ","), paste(only_t, collapse = ","))))
    }
    return(list(file = fname, status = "FAIL", detail = "column ORDER differs"))
  }

  fails <- character(0); worst <- ""
  for (nm in names(g)) {
    res <- compare_column(g[[nm]], t[[nm]], tol)
    if (!res$ok) fails <- c(fails, sprintf("  [%s] %s", nm, res$detail))
  }
  if (length(fails)) {
    return(list(file = fname, status = "FAIL",
                detail = paste0(sprintf("%d column(s) differ:\n", length(fails)),
                                paste(head(fails, 5), collapse = "\n"))))
  }
  list(file = fname, status = "PASS",
       detail = sprintf("%d rows x %d cols", nrow(g), ncol(g)))
}

# --- run --------------------------------------------------------------------

if (!dir.exists(golden_dir)) {
  stop(sprintf("Golden directory '%s' does not exist. Snapshot it first.", golden_dir))
}
golden_files <- sort(basename(list.files(golden_dir, pattern = "\\.csv$")))
if (!length(golden_files)) stop(sprintf("No CSVs found in '%s'.", golden_dir))

cat(sprintf("\nGolden : %s\nTest   : %s\nTol    : %g (relative)\n\n",
            golden_dir, test_dir, tol))

results <- lapply(golden_files, compare_file, golden_dir, test_dir, tol)

w <- max(nchar(golden_files))
cat(sprintf("%-*s  %-7s  %s\n", w, "FILE", "RESULT", "DETAIL"))
cat(strrep("-", w + 40), "\n")
for (r in results) {
  first <- strsplit(r$detail, "\n")[[1]][1]
  cat(sprintf("%-*s  %-7s  %s\n", w, r$file, r$status, first))
}

failed <- Filter(function(r) r$status != "PASS", results)
extra  <- setdiff(sort(basename(list.files(test_dir, pattern = "\\.csv$"))), golden_files)

if (length(failed)) {
  cat("\n---- FAILURE DETAIL ----\n")
  for (r in failed) cat(sprintf("\n%s (%s):\n%s\n", r$file, r$status, r$detail))
}
if (length(extra)) {
  cat(sprintf("\nNote: %d extra CSV(s) in test dir not in golden: %s\n",
              length(extra), paste(extra, collapse = ", ")))
}

cat(sprintf("\n==== %d/%d PASS ====\n",
            length(results) - length(failed), length(results)))

if (length(failed)) {
  cat("VERIFICATION FAILED - do not accept this change.\n\n")
  quit(status = 1)
}
cat("All outputs match golden master. The change is safe to accept.\n\n")

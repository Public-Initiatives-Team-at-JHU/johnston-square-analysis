#!/usr/bin/env Rscript
###############################################################################
# check_env.R
#
# Setup check. Run once after cloning, before the analysis:
#
#   Rscript R/check_env.R
#
# Every line should read PASS. See "Quick start" in README.md for fixes.
###############################################################################

ok <- TRUE
say <- function(label, pass, hint = "") {
  cat(sprintf("%-44s %s\n", label, if (pass) "PASS" else paste("FAIL", hint)))
  if (!pass) ok <<- FALSE
}

say("R version 4.1 or later", getRversion() >= "4.1")

pkgs <- c("tidycensus", "tidyverse", "R.utils", "scales", "sf", "tigris", "ragg")
for (p in pkgs) {
  say(sprintf("package %s installed", p), requireNamespace(p, quietly = TRUE),
      sprintf("-> install.packages(\"%s\")", p))
}

say("CENSUS_API_KEY set", nzchar(Sys.getenv("CENSUS_API_KEY")),
    "-> tidycensus::census_api_key(\"YOUR KEY\", install = TRUE), then restart R")

# A real write probe, not dir.exists(): on a synced drive an existing folder
# can still refuse writes.
dir.create("output", showWarnings = FALSE)
probe <- file.path("output", paste0(".writeprobe-", Sys.getpid()))
writable <- tryCatch({ writeLines("probe", probe); TRUE },
                     error = function(e) FALSE, warning = function(w) FALSE)
unlink(probe)
say("output/ writable", writable)

say("Tahoma font available (figures only)",
    requireNamespace("systemfonts", quietly = TRUE) &&
      "Tahoma" %in% systemfonts::system_fonts()$family,
    "-> figures fall back to a default font")

cat(if (ok) "\nALL PASS\n" else "\nFAILURES ABOVE\n")
quit(status = if (ok) 0 else 1)

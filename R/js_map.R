###############################################################################
# js_map.R
#
# Reference map: census tract 1001 (the study area) against the Johnston
# Square neighbourhood (NSA) boundary, with nearby tracts and streets.
#
#   Rscript R/js_map.R
#
# Writes output/figures/00_study_area_map.png. Not sourced by the analysis:
# the geography does not change between runs, and this needs TIGER downloads
# (cached by tigris after the first run).
#
# Same visual system as R/js_plots.R (JHU PII, Tahoma, Heritage Blue).
###############################################################################

suppressPackageStartupMessages({
  library(sf); library(tigris); library(dplyr); library(ggplot2)
})
options(tigris_use_cache = TRUE, tigris_class = "sf")

CRS_MD   <- 2248   # NAD83 / Maryland (ftUS)
HERITAGE <- "#002D72"
SPIRIT   <- "#68ACE5"
NSA_RED  <- "#CF4520"   # JHU Red: 4.6:1 on white, distinct from the blues
MUTED    <- "#5B6770"
GREY     <- "#A7A8AA"
RULE     <- "#D9D9D6"

# Streets that form the two boundaries (checked against TIGER: the tract runs
# E Preston St / E Eager St / I-83 / N Caroline St; the NSA's north edge is
# E Hoffman St and it steps at E Biddle St). Target = where along the street to
# put the label, as a fraction of the tract's bounding box (x, y).
STREET_LABELS <- tibble::tribble(
  ~street,           ~label,            ~fx,   ~fy,
  "E Preston St",    "E Preston St",    0.45,  1.00,
  "E Eager St",      "E Eager St",      0.62,  0.00,
  "E Hoffman St",    "E Hoffman St",    0.25,  1.35,
  "E Biddle St",     "E Biddle St",     0.80,  0.60,
  "Greenmount Ave",  "Greenmount Ave",  0.30,  0.35,
  "N Caroline St",   "N Caroline St",   1.00,  0.45,
  "Jones Falls Expy","I-83",            0.00,  0.45
)

nsa <- st_read("geo/johnston_square_nsa.geojson", quiet = TRUE) %>% st_transform(CRS_MD)
t20 <- tracts("MD", "510", year = 2020, progress_bar = FALSE) %>% st_transform(CRS_MD)
tract <- filter(t20, GEOID == "24510100100")
stopifnot(nrow(tract) == 1)

# Frame: both boundaries plus a margin, widened to the figure's aspect ratio.
core <- st_bbox(st_union(st_geometry(nsa), st_geometry(tract)))
pad  <- 1100
bb   <- core + c(-pad, -pad, pad, pad)
w <- bb[["xmax"]] - bb[["xmin"]]; h <- bb[["ymax"]] - bb[["ymin"]]
aspect <- 8 / 5.6                                       # plot area, roughly
if (w / h < aspect) {
  d <- (h * aspect - w) / 2; bb[["xmin"]] <- bb[["xmin"]] - d; bb[["xmax"]] <- bb[["xmax"]] + d
} else {
  d <- (w / aspect - h) / 2; bb[["ymin"]] <- bb[["ymin"]] - d; bb[["ymax"]] <- bb[["ymax"]] + d
}
frame <- st_as_sfc(bb)

near_tracts <- t20[st_intersects(t20, frame, sparse = FALSE)[, 1], ] %>%
  filter(GEOID != tract$GEOID)
roads_all <- suppressWarnings(
  roads("MD", "510", year = 2020, progress_bar = FALSE) %>% st_transform(CRS_MD) %>% st_crop(bb)
)

# One label per street, at the point nearest its target, rotated to run along
# the street there so it cannot be read as belonging to a neighbouring line.
tbb <- st_bbox(tract)
street_lab <- bind_rows(lapply(seq_len(nrow(STREET_LABELS)), function(i) {
  sl <- STREET_LABELS[i, ]
  target <- st_sfc(st_point(c(tbb[["xmin"]] + sl$fx * (tbb[["xmax"]] - tbb[["xmin"]]),
                              tbb[["ymin"]] + sl$fy * (tbb[["ymax"]] - tbb[["ymin"]]))), crs = CRS_MD)
  segs <- roads_all %>% filter(FULLNAME == sl$street) %>% st_cast("LINESTRING")
  stopifnot(nrow(segs) > 0)
  seg <- segs[which.min(st_distance(segs, target)), ]
  xy  <- st_coordinates(seg)[, 1:2]
  k   <- which.min((xy[, 1] - st_coordinates(target)[1])^2 + (xy[, 2] - st_coordinates(target)[2])^2)
  a   <- xy[max(k - 1, 1), ]; b <- xy[min(k + 1, nrow(xy)), ]
  ang <- atan2(b[2] - a[2], b[1] - a[1]) * 180 / pi
  ang <- ((ang + 90) %% 180) - 90                     # keep text upright
  pt  <- st_nearest_points(st_geometry(seg), target) %>% st_cast("POINT") %>% .[1]
  st_sf(label = sl$label, angle = ang, geometry = pt)
}))

tract_lab <- suppressWarnings(st_point_on_surface(near_tracts)) %>%
  mutate(lab = paste("Tract", NAME))
p <- ggplot() +
  geom_sf(data = roads_all, colour = RULE, linewidth = 0.25) +
  geom_sf(data = near_tracts, fill = NA, colour = GREY, linewidth = 0.35) +
  geom_sf(data = tract, aes(fill = "Census Tract 1001 (24510100100)"),
          colour = HERITAGE, linewidth = 0.9, alpha = 0.35) +
  geom_sf(data = nsa, aes(colour = "Johnston Square neighborhood (NSA boundary)"),
          fill = NA, linewidth = 1.1, linetype = "22") +
  geom_sf_text(data = tract_lab, aes(label = lab), size = 2.6, colour = MUTED,
               family = "Tahoma") +
  geom_sf_label(data = street_lab, aes(label = label, angle = angle), size = 2.6,
                colour = "#31261D", family = "Tahoma", fill = "white", label.size = 0,
                alpha = 0.9, label.padding = unit(1.2, "pt")) +
  scale_fill_manual(values = SPIRIT, name = NULL) +
  scale_colour_manual(values = NSA_RED, name = NULL) +
  guides(fill = guide_legend(order = 1, override.aes = list(colour = HERITAGE, alpha = 0.35)),
         colour = guide_legend(order = 2, override.aes = list(fill = NA, linetype = "22"))) +
  coord_sf(xlim = bb[c("xmin", "xmax")], ylim = bb[c("ymin", "ymax")], expand = FALSE,
           datum = NA) +
  labs(title = "Study area: Census Tract 1001 and the Johnston Square neighborhood",
       subtitle = "About 85% of the tract's population lives in Johnston Square; the rest is in Oliver",
       caption = paste(strwrap(paste(
         "The part of Johnston Square north of E Preston St lies in tract 909; the part of the",
         "tract east of the dashed line is Oliver. For 2005-2009 the study area also includes",
         "part of retired tract 1004 (population weight 0.271). Sources: tracts and streets,",
         "2020 TIGER/Line (U.S. Census Bureau); neighborhood, Baltimore City Neighborhood",
         "Statistical Area boundary (Open Baltimore)."), width = 150), collapse = "\n")) +
  theme_void(base_family = "Tahoma", base_size = 11) +
  theme(
    plot.title    = element_text(face = "bold", colour = HERITAGE, size = 14),
    plot.subtitle = element_text(colour = MUTED, size = 10, margin = margin(t = 2, b = 8)),
    plot.caption  = element_text(colour = MUTED, size = 8, hjust = 0, lineheight = 1.2,
                                 margin = margin(t = 8)),
    plot.title.position = "plot", plot.caption.position = "plot",
    legend.position = "top", legend.justification = "left",
    legend.text   = element_text(colour = "#31261D", size = 9),
    panel.border  = element_rect(colour = RULE, fill = NA, linewidth = 0.4),
    plot.background = element_rect(fill = "white", colour = NA),
    plot.margin   = margin(12, 16, 10, 12)
  )

dir.create("output/figures", showWarnings = FALSE, recursive = TRUE)
ggsave("output/figures/00_study_area_map.png", p, width = 8, height = 7.3, dpi = 300,
       device = ragg::agg_png, bg = "white")
cat("wrote output/figures/00_study_area_map.png\n")

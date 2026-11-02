# Synthetic offline fixtures, NOT live IMF data.
fixture_api <- function() {
  log <- new.env(parent = emptyenv())
  log$calls <- list(); log$fail_values <- FALSE; log$fail_data <- FALSE
  record <- function(kind, q = NULL, dimension = NULL) {
    log$calls[[length(log$calls) + 1L]] <- list(kind = kind, q = q, dimension = dimension)
  }
  list(log = log, api = list(
    datasets = function(agency) {
      record("datasets", list(agency = agency))
      normalize_datasets(data.frame(agency = agency, id = c("A", "B"), version = c("1", "2"),
        name = c("Synthetic regions", "Synthetic sectors"), description = "OFFLINE FIXTURE"))
    },
    dimensions = function(q) {
      record("dimensions", q)
      ids <- if (q$dataset == "A") c("REGION", "METRIC", "TIME_PERIOD") else c("SECTOR", "FREQ", "PERIOD")
      normalize_dimensions(data.frame(id = ids, name = ids, type = c("Dimension", "Dimension", "TimeDimension")))
    },
    values = function(q, dimension) {
      record("values", q, dimension)
      if (log$fail_values) stop("fixture network failure")
      codes <- switch(dimension, REGION = if ("empty" %in% q$filters$METRIC) character() else
          if ("limited" %in% q$filters$METRIC) "X" else c("X", "Y"),
        METRIC = c("index", "limited", "empty"), SECTOR = c("S1", "S2"), FREQ = c("A", "M"))
      normalize_values(data.frame(code = codes, name = if (length(codes)) paste0("Label ", codes) else character()))
    },
    data = function(q) {
      record("data", q)
      if (log$fail_data) stop("fixture data failure")
      data.frame(REGION = "X", METRIC = "index", TIME_PERIOD = c("2024-M01", "2024-M02"),
                 OBS_VALUE = c(100, 102), UNIT_MEASURE = "INDEX")
    }
  ))
}

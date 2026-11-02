# All upstream calls live here; constructing an adapter makes no requests.
imf_adapter <- function() {
  list(
    datasets = function(agency) normalize_datasets(imf.data::list_datasets(agency)),
    dimensions = function(q) normalize_dimensions(imf.data::list_dimensions(
      dataflow = q$dataset, agency_id = q$agency, version = q$version)),
    values = function(q, dimension) normalize_values(imf.data::list_dimension_values(
      dataflow = q$dataset, dimension = dimension,
      filters = q$filters[setdiff(names(q$filters), dimension)],
      agency_id = q$agency, version = q$version)),
    data = function(q) {
      out <- do.call(imf.data::get_data, data_arguments(q))
      if (!is.data.frame(out)) stop("IMF returned an unexpected observation response.")
      as.data.frame(out, stringsAsFactors = FALSE)
    }
  )
}

normalize_frame <- function(x, required, optional = character()) {
  if (!is.data.frame(x)) stop("Unexpected IMF metadata response: expected a data frame.")
  missing <- setdiff(required, names(x))
  if (length(missing)) stop("IMF metadata is missing: ", paste(missing, collapse = ", "))
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  for (n in optional) if (!n %in% names(x)) x[[n]] <- rep(NA_character_, nrow(x))
  for (n in c(required, optional)) x[[n]] <- as.character(x[[n]])
  x
}

normalize_datasets <- function(x) {
  x <- normalize_frame(x, c("agency", "id", "version"), c("name", "description"))
  if (anyNA(x[c("agency", "id", "version")]) ||
      any(!nzchar(as.matrix(x[c("agency", "id", "version")]))))
    stop("Dataset identity or version is missing in IMF metadata.")
  x
}

normalize_dimensions <- function(x) {
  x <- normalize_frame(x, c("id", "type"), "name")
  if (anyNA(x$id) || any(!nzchar(x$id)) || anyDuplicated(x$id))
    stop("IMF returned missing or duplicate dimension IDs.")
  # SDMX type is authoritative; TIME_PERIOD also covers missing type metadata.
  x$is_time <- (!is.na(x$type) & grepl("time", x$type, ignore.case = TRUE)) |
    x$id == "TIME_PERIOD"
  x
}

normalize_values <- function(x) {
  x <- normalize_frame(x, "code", c("name", "description"))
  if (anyNA(x$code) || any(!nzchar(x$code))) stop("IMF returned missing codes.")
  x[!duplicated(x$code), , drop = FALSE]
}

readable <- function(label, code) {
  if (!length(code)) return(character())
  label[is.na(label) | !nzchar(label)] <- code[is.na(label) | !nzchar(label)]
  paste0(label, " [", code, "]")
}

attempt <- function(expr) {
  tryCatch(list(ok = TRUE, value = force(expr), error = NULL),
           error = function(e) list(ok = FALSE, value = NULL, error = conditionMessage(e)))
}

canonical_filters <- function(filters) {
  filters <- filters[lengths(filters) > 0L]
  if (!length(filters)) return(list())
  filters <- filters[sort(names(filters))]
  lapply(filters, function(x) sort(unique(as.character(x))))
}

cache_key <- function(kind, q = list(), dimension = NULL) {
  if (!is.null(dimension)) q$filters <- q$filters[setdiff(names(q$filters), dimension)]
  # Removing the only filter can leave a named empty list; normalize afterwards
  # so the own-dimension filter never changes its availability cache key.
  q$filters <- canonical_filters(q$filters)
  # Serialize named fields, including NULLs: no ambiguous concatenation.
  jsonlite::toJSON(list(kind = kind, agency = q$agency, dataset = q$dataset,
                       version = q$version, dimension = dimension, filters = q$filters),
                   auto_unbox = TRUE, null = "null")
}

cached <- function(cache, key, fetch) {
  if (exists(key, envir = cache, inherits = FALSE)) return(get(key, envir = cache))
  value <- fetch()
  assign(key, value, envir = cache)
  value
}

selection_status <- function(selected, values, error = NULL) {
  if (!is.null(error)) return(list(invalid = character(), message = paste("API failure:", error,
    "Selections are retained. Retry retrieval or update available values.")))
  invalid <- setdiff(selected, values$code)
  message <- if (length(invalid)) paste("Unavailable selected codes:", paste(invalid, collapse = ", "),
    "\u2014 clear these codes or change other filters, then update availability.") else
    if (!nrow(values)) "No available values for the other current filters. This is a successful empty response." else
      paste(nrow(values), "available codes. Empty selection means unrestricted.")
  list(invalid = invalid, message = message)
}

# Keep unavailable selections visible in a server-side selectize source.
dimension_choices <- function(values, selected) {
  available <- if (is.null(values)) character() else values$code
  labels <- if (is.null(values)) character() else readable(values$name, values$code)
  extras <- setdiff(selected, available)
  stats::setNames(c(available, extras), c(labels,
    if (length(extras)) paste0(extras, " [unavailable / unverified]") else character()))
}

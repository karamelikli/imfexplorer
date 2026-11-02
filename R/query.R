#' Construct a canonical query configuration
#'
#' Create a schema-version-one query with canonical dimension filters. This
#' constructor does not validate the query; validation occurs before execution
#' or serialization.
#'
#' @param agency Character scalar identifying the IMF maintainer.
#' @param dataset Character scalar identifying the dataflow.
#' @param version Character scalar specifying the dataflow version.
#' @param filters Named list of dimension code selections. Empty selections
#'   mean the dimension is unrestricted.
#' @param start_period,end_period Optional character scalar period bounds.
#' @param last_n_obs Optional numeric scalar limiting observations per series.
#' @param attributes Character vector of exact upstream attribute IDs.
#' @return A named list containing `schema_version`, identity fields, filters,
#'   time options and attributes. Non-NULL `last_n_obs` is stored as a double.
#' @seealso [validate_query()], [query_json()], [data_arguments()]
#'
#' @keywords internal
new_query <- function(agency, dataset, version, filters = list(), start_period = NULL,
                      end_period = NULL, last_n_obs = NULL, attributes = character()) {
  list(
    schema_version = 1L, agency = agency, dataset = dataset, version = version,
    filters = canonical_filters(filters), start_period = start_period,
    end_period = end_period,
    last_n_obs = if (is.null(last_n_obs)) NULL else as.double(last_n_obs), attributes = attributes
  )
}

#' Check for one nonempty character value
#'
#' Test whether a value is a nonmissing character scalar with positive length.
#' Whitespace is not trimmed by this helper.
#'
#' @param x An R object to check.
#' @return A single logical value.
#'
#' @keywords internal
scalar_text <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)

#' Map supported periods to numeric plotting coordinates
#'
#' Recognize annual, quarterly, calendar-month, reporting-month and daily
#' periods, including IMF month strings such as `2024-M01`.
#'
#' @param x A nonmissing character scalar containing a period.
#' @return A numeric plotting and ordering coordinate, or `NA_real_` for an
#'   unsupported or invalid period. Daily fractions use a 366-day divisor;
#'   these coordinates are not exact elapsed-time measurements.
#'
#' @keywords internal
period_number <- function(x) {
  # IMF observations use reporting months (YYYY-Mmm), unlike calendar bounds.
  x <- sub("^([0-9]{4})-M([0-9]{2})$", "\\1-\\2", x)
  if (grepl("^[0-9]{4}$", x)) {
    return(as.numeric(x))
  }
  if (grepl("^[0-9]{4}-Q[1-4]$", x)) {
    return(as.numeric(substr(x, 1, 4)) + (as.numeric(substr(x, 7, 7)) - 1) / 4)
  }
  if (grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", x)) {
    return(as.numeric(substr(x, 1, 4)) + (as.numeric(substr(x, 6, 7)) - 1) / 12)
  }
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)) {
    d <- suppressWarnings(tryCatch(as.Date(x), error = function(e) NA))
    if (!is.na(d) && format(d, "%Y-%m-%d") == x) {
      return(as.numeric(format(d, "%Y")) + (as.numeric(format(d, "%j")) - 1) / 366)
    }
  }
  NA_real_
}

#' Validate a query configuration before use
#'
#' Check schema version, identity, named code vectors, supported period bounds,
#' mutually exclusive time options and requested attributes.
#'
#' @param q A query configuration list, normally created by [new_query()].
#' @param dimensions Optional normalized dimension metadata. When supplied,
#'   filter IDs must identify non-time dimensions in this metadata.
#' @return The unchanged query, invisibly, on success. Invalid configurations
#'   raise an error with a message suitable for display in the application.
#' @details Period bounds accept years, quarters, calendar or reporting months,
#'   and valid calendar dates. Latest-N queries cannot also specify a range.
#'   This function checks the configuration, not live code availability.
#'
#' @keywords internal
validate_query <- function(q, dimensions = NULL) {
  if (!is.list(q) || !identical(q$schema_version, 1L)) stop("Unsupported configuration schema_version; expected 1.")
  for (n in c("agency", "dataset", "version")) {
    if (!scalar_text(q[[n]])) stop(n, " must be a nonempty string.")
  }
  f <- q$filters
  filter_error <- "filters must be a uniquely named list of dimension codes."
  if (!is.list(f)) stop(filter_error)
  if (length(f)) {
    ids <- names(f)
    invalid_ids <- is.null(ids) || anyNA(ids) ||
      any(!grepl("^[A-Za-z][A-Za-z0-9_]*$", ids)) || anyDuplicated(ids)
    if (invalid_ids) stop(filter_error)
  }
  if (any(!vapply(f, function(x) {
    is.character(x) && length(x) > 0 &&
      !anyNA(x) && all(nzchar(x))
  }, logical(1)))) {
    stop("Filter codes must be nonempty strings.")
  }
  if (!is.null(dimensions)) {
    unknown <- setdiff(names(f), dimensions$id[!dimensions$is_time])
    if (length(unknown)) stop("Unavailable or time dimensions in filters: ", paste(unknown, collapse = ", "))
  }
  for (n in c("start_period", "end_period")) {
    if (!is.null(q[[n]]) && (!scalar_text(q[[n]]) || is.na(period_number(q[[n]])))) {
      stop(n, ": use YYYY, YYYY-Qn, YYYY-MM, or YYYY-MM-DD.")
    }
  }
  if (!is.null(q$start_period) && !is.null(q$end_period)) {
    if (period_number(q$start_period) > period_number(q$end_period)) {
      stop("Start period must precede end period.")
    }
  }
  if (!is.null(q$last_n_obs)) {
    n <- q$last_n_obs
    invalid_count <- !is.numeric(n) || length(n) != 1 || is.na(n) ||
      !is.finite(n) || n < 1 || n > .Machine$integer.max || n != floor(n)
    if (invalid_count) stop("Latest N must be a positive integer.")
  }
  if (!is.null(q$last_n_obs) && (!is.null(q$start_period) || !is.null(q$end_period))) {
    stop("Use a period range or latest N, not both. Switch the time mode.")
  }
  if (!is.character(q$attributes) || anyNA(q$attributes) || any(!nzchar(q$attributes))) {
    stop("attributes must be a character vector of exact attribute IDs.")
  }
  invisible(q)
}

#' Translate a query to supported get_data arguments
#'
#' Validate the query and map its internal identity fields to the exact
#' argument names used by imf.data.
#'
#' @param q A query configuration list.
#' @return A named argument list for [imf.data::get_data()], including filters,
#'   agency, version, period bounds, latest-N and attributes.
#' @seealso [validate_query()], [imf_adapter()]
#'
#' @keywords internal
data_arguments <- function(q) {
  validate_query(q)
  list(
    dataflow = q$dataset, filters = q$filters, agency_id = q$agency,
    version = q$version, start_period = q$start_period, end_period = q$end_period,
    last_n_obs = q$last_n_obs, attributes = q$attributes
  )
}

#' Generate runnable R code for a query
#'
#' Build an explicit named `filters` assignment and an `imf.data::get_data()`
#' call using R language objects and safe deparsing.
#'
#' @param q A valid query configuration list.
#' @return A character scalar containing a reproducible R script. User-supplied
#'   strings are serialized as R values; generated code is never evaluated here.
#' @seealso [data_arguments()], [query_json()]
#'
#' @keywords internal
query_code <- function(q) {
  args <- data_arguments(q)
  args$filters <- as.name("filters")
  call <- as.call(c(list(quote(imf.data::get_data)), args))
  paste(c(
    "# Generated by imfexplorer. Requires imf.data >= 0.2.0.",
    paste("filters <-", paste(deparse(q$filters, width.cutoff = 80L), collapse = "\n")),
    paste("data <-", paste(deparse(call, width.cutoff = 80L), collapse = "\n"))
  ), collapse = "\n")
}

#' Serialize a query as schema-versioned JSON
#'
#' Validate and serialize a query while keeping code vectors as arrays,
#' including single-code selections.
#'
#' @param q A valid query configuration list.
#' @return A pretty-printed JSON character value. Scalar fields also use arrays
#'   in this format, and absent time options are represented as JSON nulls.
#' @seealso [parse_config()]
#'
#' @keywords internal
query_json <- function(q) {
  validate_query(q)
  # Arrays remain arrays even for a single filter code.
  jsonlite::toJSON(q, auto_unbox = FALSE, pretty = TRUE, null = "null")
}

#' Parse and validate a saved JSON query
#'
#' Read a configuration without evaluating R code, reject unknown or duplicate
#' fields, and restore canonical filter and numeric representations.
#'
#' @param text JSON text accepted by [jsonlite::fromJSON()].
#' @return A validated schema-version-one query list. Both the arrays emitted
#'   by [query_json()] and natural JSON scalar fields are accepted. Invalid
#'   configurations raise an error; live metadata is checked separately by
#'   the application during import.
#'
#' @keywords internal
parse_config <- function(text) {
  x <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  allowed <- names(new_query("a", "b", "c"))
  if (!is.list(x) || any(!names(x) %in% allowed) || anyDuplicated(names(x))) {
    stop("Invalid configuration fields.")
  }
  # Our format uses arrays for scalar fields too; also accept natural JSON scalars.
  for (n in setdiff(allowed, "filters")) {
    if (is.list(x[[n]])) x[[n]] <- unlist(x[[n]], use.names = FALSE)
  }
  if (is.null(x$attributes)) x$attributes <- character()
  if (is.null(x$filters)) x$filters <- list()
  if (is.list(x$filters)) {
    x$filters <- lapply(x$filters, function(z) {
      if (is.list(z)) unlist(z, use.names = FALSE) else z
    })
  }
  validate_query(x)
  x$filters <- canonical_filters(x$filters)
  if (!is.null(x$last_n_obs)) x$last_n_obs <- as.double(x$last_n_obs)
  x
}

#' Compare complete query snapshots
#'
#' Use strict structural equality to distinguish current selections from the
#' query that produced an existing result.
#'
#' @param a,b Query configuration lists to compare.
#' @return A logical scalar from `identical(a, b)`. No normalization is done
#'   inside this function.
#'
#' @keywords internal
same_query <- function(a, b) identical(a, b)

# Reset is shared by dataset switching and the explicit reset action.
#' Create empty dataset-dependent application state
#'
#' Supply fresh values shared by dataset switching and explicit query reset.
#'
#' @return A list with NULL `dataset`, `dimensions`, `results` and
#'   `result_query` fields and empty `filters` and `values` lists.
#'
#' @keywords internal
empty_dataset_state <- function() {
  list(
    dataset = NULL, dimensions = NULL, filters = list(),
    values = list(), results = NULL, result_query = NULL
  )
}

#' Identify potentially broad observation requests
#'
#' Inspect unrestricted dimensions, time options and the size of explicit
#' code selections to decide whether user acknowledgement is needed.
#'
#' @param q A validated query configuration list.
#' @param dimensions Normalized metadata containing dimension IDs and `is_time`.
#' @return A logical scalar indicating potential breadth. The heuristic flags
#'   an unrestricted non-time dimension, unbounded start without latest-N,
#'   at least 100 codes in one dimension, or over 1,000 candidate combinations.
#' @details Candidate combinations are a request-risk heuristic only. They are
#'   never interpreted as an exact count of available series.
#'
#' @keywords internal
broad_query <- function(q, dimensions) {
  ids <- dimensions$id[!dimensions$is_time]
  sizes <- lengths(q$filters)
  # A risk heuristic only: these combinations are not an available-series count.
  many_codes <- any(sizes >= 100L) || sum(log(pmax(1, sizes))) > log(1000)
  any(!ids %in% names(q$filters)) || many_codes ||
    (is.null(q$last_n_obs) && is.null(q$start_period))
}

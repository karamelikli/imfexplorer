# All upstream calls live here; constructing an adapter makes no requests.
#' Create the IMF API adapter
#'
#' Construct the upstream API boundary without making network requests.
#'
#' @details The returned methods use imf.data 0.2.0 or later and normalize
#'   metadata through this package's internal helpers. Dataflow methods preserve
#'   the query's agency, dataset ID and version. Availability requests exclude
#'   the requested dimension's own filter.
#' @return A named list of functions: `datasets(agency)` returns normalized
#'   catalogue metadata; `dimensions(q)` returns normalized dimension metadata;
#'   `values(q, dimension)` returns normalized available codes; and `data(q)`
#'   returns an observation data frame for a validated query. `structure(q)`
#'   returns the full SDMX dataflow structure and its references.
#'   `metadata_catalogue()` lists metadata-report identities, independently of
#'   dataflow versions; `metadata(report)` retrieves one full metadata report.
#'   A report is a one-row frame with `agency`, `id` and `version` columns.
#' @seealso [normalize_datasets()], [normalize_dimensions()],
#'   [normalize_values()], [data_arguments()]
#'
#' @keywords internal
imf_adapter <- function() {
  list(
    datasets = function(agency) normalize_datasets(imf.data::list_datasets(agency)),
    dimensions = function(q) {
      normalize_dimensions(imf.data::list_dimensions(
        dataflow = q$dataset, agency_id = q$agency, version = q$version
      ))
    },
    values = function(q, dimension) {
      normalize_values(imf.data::list_dimension_values(
        dataflow = q$dataset, dimension = dimension,
        filters = q$filters[setdiff(names(q$filters), dimension)],
        agency_id = q$agency, version = q$version
      ))
    },
    structure = function(q) {
      imf.data::sdmx_structure(
        structure_type = "dataflow", agency_id = q$agency,
        resource_id = q$dataset, version = q$version, references = "all"
      )
    },
    metadata_catalogue = function() {
      out <- imf.data::sdmx_metadata(detail = "allstubs")
      reports <- out$data$metadataSets
      if (!length(reports)) {
        return(normalize_datasets(data.frame(agency = character(), id = character(), version = character())))
      }
      normalize_datasets(do.call(rbind, lapply(reports, function(report) {
        data.frame(
          agency = report$agencyID, id = report$id, version = report$version,
          name = if (is.null(report$name)) report$id else report$name, stringsAsFactors = FALSE
        )
      })))
    },
    metadata = function(report) {
      out <- imf.data::sdmx_metadata(
        provider_id = report$agency[[1]], metadataset_id = report$id[[1]],
        version = report$version[[1]], detail = "full"
      )
      if (!length(out$data$metadataSets)) {
        return(NULL)
      }
      out
    },
    data = function(q) {
      out <- do.call(imf.data::get_data, data_arguments(q))
      if (!is.data.frame(out)) stop("IMF returned an unexpected observation response.")
      as.data.frame(out, stringsAsFactors = FALSE)
    }
  )
}

#' Normalize the character columns of a metadata response
#'
#' Check the required schema, add absent optional columns, and convert the
#' specified columns to character without changing other columns.
#'
#' @param x A metadata data frame returned by an upstream API call.
#' @param required Character vector of column names that must be present.
#' @param optional Character vector of optional columns. Missing columns are
#'   filled with `NA_character_`.
#' @return A base data frame with normalized required and optional columns.
#'   An error is raised for a non-data-frame response or missing required columns.
#'
#' @keywords internal
normalize_frame <- function(x, required, optional = character()) {
  if (!is.data.frame(x)) stop("Unexpected IMF metadata response: expected a data frame.")
  missing <- setdiff(required, names(x))
  if (length(missing)) stop("IMF metadata is missing: ", paste(missing, collapse = ", "))
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  for (n in optional) if (!n %in% names(x)) x[[n]] <- rep(NA_character_, nrow(x))
  for (n in c(required, optional)) x[[n]] <- as.character(x[[n]])
  x
}

#' Normalize dataset catalogue metadata
#'
#' Require nonempty agency, dataset ID and version values while retaining any
#' additional upstream metadata columns.
#'
#' @param x A dataset data frame with `agency`, `id` and `version` columns.
#' @return A data frame with character identity columns and character `name`
#'   and `description` columns. Missing descriptive columns contain `NA`.
#'   Invalid dataset identities raise an error.
#' @seealso [normalize_frame()]
#'
#' @keywords internal
normalize_datasets <- function(x) {
  x <- normalize_frame(x, c("agency", "id", "version"), c("name", "description"))
  identity <- as.matrix(x[c("agency", "id", "version")])
  if (anyNA(identity) || any(!nzchar(identity))) {
    stop("Dataset identity or version is missing in IMF metadata.")
  }
  x
}

#' Normalize dataset dimension metadata
#'
#' Validate unique dimension IDs and identify time dimensions from their SDMX
#' component type or the exact ID `TIME_PERIOD`.
#'
#' @param x A dimension data frame with `id` and `type` columns and an optional
#'   readable `name` column.
#' @return A data frame with normalized character metadata and a logical
#'   `is_time` column. Missing, empty or duplicate IDs raise an error.
#' @seealso [normalize_frame()]
#'
#' @keywords internal
normalize_dimensions <- function(x) {
  x <- normalize_frame(x, c("id", "type"), "name")
  if (anyNA(x$id) || any(!nzchar(x$id)) || anyDuplicated(x$id)) {
    stop("IMF returned missing or duplicate dimension IDs.")
  }
  # SDMX type is authoritative; TIME_PERIOD also covers missing type metadata.
  x$is_time <- (!is.na(x$type) & grepl("time", x$type, ignore.case = TRUE)) |
    x$id == "TIME_PERIOD"
  x
}

#' Normalize an available dimension code list
#'
#' Validate codes, supply optional labels and descriptions, and keep the first
#' row for each distinct code.
#'
#' @param x An availability data frame with a `code` column and optional
#'   `name` and `description` columns.
#' @return A data frame with character `code`, `name` and `description` columns,
#'   retaining other upstream columns. Successful empty responses remain empty;
#'   missing or empty codes raise an error.
#'
#' @keywords internal
normalize_values <- function(x) {
  x <- normalize_frame(x, "code", c("name", "description"))
  if (anyNA(x$code) || any(!nzchar(x$code))) stop("IMF returned missing codes.")
  x[!duplicated(x$code), , drop = FALSE]
}

#' Format readable labels with exact codes
#'
#' Fall back to the code when its label is missing or empty.
#'
#' @param label Character vector of readable labels, corresponding to `code`.
#' @param code Character vector of exact dataset, dimension or value codes.
#' @return A character vector formatted as `label [code]`, or `character()`
#'   when no codes are supplied.
#'
#' @keywords internal
readable <- function(label, code) {
  if (!length(code)) {
    return(character())
  }
  label[is.na(label) | !nzchar(label)] <- code[is.na(label) | !nzchar(label)]
  paste0(label, " [", code, "]")
}

#' Capture an expression's value or error
#'
#' Evaluate a lazy expression once and convert errors to a structured result.
#' Warnings are not intercepted.
#'
#' @param expr An unevaluated expression to evaluate inside the error handler.
#' @return A list with logical `ok`, the successful `value`, and an `error`
#'   message. On failure `value` is `NULL`; on success `error` is `NULL`.
#'
#' @keywords internal
attempt <- function(expr) {
  tryCatch(list(ok = TRUE, value = force(expr), error = NULL),
    error = function(e) list(ok = FALSE, value = NULL, error = conditionMessage(e))
  )
}

#' Canonicalize named dimension filters
#'
#' Drop unrestricted dimensions, sort dimension names, and sort and deduplicate
#' character codes so equivalent filter sets share a stable representation.
#'
#' @param filters A named list of selected code vectors. `NULL` and a list
#'   with no selected codes are treated as unrestricted.
#' @return A named list of sorted character vectors, or an unnamed empty list
#'   when every dimension is unrestricted. This helper does not validate IDs.
#' @seealso [validate_query()], [cache_key()]
#'
#' @keywords internal
canonical_filters <- function(filters) {
  filters <- filters[lengths(filters) > 0L]
  if (!length(filters)) {
    return(list())
  }
  filters <- filters[sort(names(filters))]
  lapply(filters, function(x) sort(unique(as.character(x))))
}

#' Construct a deterministic metadata cache key
#'
#' Serialize metadata identity and canonical filters, excluding a dimension's
#' own filter for availability queries.
#'
#' @param kind Character scalar identifying the metadata request type.
#' @param q A query-like list with the applicable `agency`, `dataset`,
#'   `version` and `filters` fields. Catalogue requests need only `agency`.
#' @param dimension Optional character scalar naming the dimension whose
#'   availability is requested.
#' @return A JSON character scalar suitable for use as an environment key.
#'   Time bounds and observation attributes are omitted because this cache
#'   stores metadata rather than observations.
#' @seealso [canonical_filters()], [cached()]
#'
#' @keywords internal
cache_key <- function(kind, q = list(), dimension = NULL) {
  if (!is.null(dimension)) q$filters <- q$filters[setdiff(names(q$filters), dimension)]
  # Removing the only filter can leave a named empty list; normalize afterwards
  # so the own-dimension filter never changes its availability cache key.
  q$filters <- canonical_filters(q$filters)
  # Serialize named fields, including NULLs: no ambiguous concatenation.
  jsonlite::toJSON(
    list(
      kind = kind, agency = q$agency, dataset = q$dataset,
      version = q$version, dimension = dimension, filters = q$filters
    ),
    auto_unbox = TRUE, null = "null"
  )
}

#' Fetch and cache a successful metadata response
#'
#' Look up an exact key in a session's environment or call the supplied fetcher.
#' Successful empty responses are cached; errors propagate without being cached.
#'
#' @param cache An environment owned by the current Shiny session.
#' @param key Character scalar identifying a metadata request.
#' @param fetch A function with no required arguments that fetches the value.
#' @return The cached or newly fetched value, with its original type preserved.
#' @seealso [cache_key()]
#'
#' @keywords internal
cached <- function(cache, key, fetch) {
  if (exists(key, envir = cache, inherits = FALSE)) {
    return(get(key, envir = cache))
  }
  value <- fetch()
  assign(key, value, envir = cache)
  value
}

#' Describe dimension selection validity
#'
#' Distinguish unavailable selected codes, successful empty availability, valid
#' selections and API failures without changing the selected values.
#'
#' @param selected Character vector of currently selected codes, or `NULL`.
#' @param values An availability data frame containing a `code` column.
#' @param error Optional character scalar describing an availability failure.
#' @return A list with character `invalid` codes and a readable `message`.
#'   On API failure, `invalid` is empty because validity is undetermined.
#'
#' @keywords internal
selection_status <- function(selected, values, error = NULL) {
  if (!is.null(error)) {
    return(list(invalid = character(), message = paste(
      "API failure:", error,
      "Selections are retained. Retry retrieval or update available values."
    )))
  }
  invalid <- setdiff(selected, values$code)
  message <- if (length(invalid)) {
    paste(
      "Unavailable selected codes:", paste(invalid, collapse = ", "),
      "\u2014 clear these codes or change other filters, then update availability."
    )
  } else if (!nrow(values)) {
    "No available values for the other current filters. This is a successful empty response."
  } else {
    paste(nrow(values), "available codes. Empty selection means unrestricted.")
  }
  list(invalid = invalid, message = message)
}

# Keep unavailable selections visible in a server-side selectize source.
#' Build searchable choices while retaining selected codes
#'
#' Combine available labels and codes with selected codes absent from the
#' current availability response.
#'
#' @param values A normalized availability data frame with `code` and `name`
#'   columns, or `NULL` before values have loaded.
#' @param selected Character vector of selected codes, or `NULL`.
#' @return A named character vector for a selectize control. Names are readable
#'   labels and values are exact codes. Unavailable or unverified selections
#'   are appended with a visible label instead of being removed.
#' @seealso [normalize_values()], [selection_status()]
#'
#' @keywords internal
dimension_choices <- function(values, selected) {
  available <- if (is.null(values)) character() else values$code
  labels <- if (is.null(values)) character() else readable(values$name, values$code)
  extras <- setdiff(selected, available)
  stats::setNames(c(available, extras), c(
    labels,
    if (length(extras)) paste0(extras, " [unavailable / unverified]") else character()
  ))
}

#' Identify metadata reports independently of catalogue order
#'
#' @param reports Normalized metadata-report catalogue.
#' @return A character vector of JSON keys containing provider, ID and version.
#'   Empty catalogues return an empty character vector.
#' @keywords internal
metadata_report_keys <- function(reports) {
  vapply(seq_len(nrow(reports)), function(i) {
    cache_key("metadata_report", list(
      agency = reports$agency[i], dataset = reports$id[i], version = reports$version[i]
    ))
  }, character(1))
}

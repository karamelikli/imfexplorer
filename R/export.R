#' Capture metadata for one retrieved observation result
#'
#' Preserve dataset identity, query, dimension definitions, code labels and the
#' full SDMX structure together with a retrieval timestamp. Only code labels for
#' returned observations are included in the dimension-value snapshot.
#'
#' @param data Retrieved observation data frame.
#' @param q Exact query used to retrieve `data`.
#' @param dataset One-row normalized catalogue record.
#' @param dimensions Normalized dimension definitions.
#' @param values Named list of normalized available dimension values.
#' @param structure Optional raw SDMX structure response with references.
#' @param structure_error Optional explanation for missing structural metadata.
#' @param excluded Character vector describing excluded selections.
#' @param report Optional full response from [imf.data::sdmx_metadata()].
#' @param report_request Report identity and selection method, or NULL.
#' @param report_error Optional explanation for an unavailable metadata report.
#' @return A metadata list suitable for the `imf_metadata` data-frame attribute.
#' @keywords internal
result_metadata <- function(data, q, dataset, dimensions, values, structure = NULL,
                            structure_error = NULL, excluded = character(), report = NULL,
                            report_request = NULL, report_error = NULL) {
  codes <- lapply(intersect(dimensions$id[!dimensions$is_time], names(data)), function(dim) {
    observed <- unique(as.character(data[[dim]]))
    observed <- observed[!is.na(observed)]
    v <- values[[dim]]
    if (is.null(v)) v <- normalize_values(data.frame(code = character()))
    labels <- v[match(observed, v$code), , drop = FALSE]
    labels$code <- observed
    rownames(labels) <- NULL
    labels
  })
  names(codes) <- intersect(dimensions$id[!dimensions$is_time], names(data))
  list(
    schema_version = 1L,
    retrieved_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    source = "IMF SDMX API via imf.data",
    imfexplorer_version = as.character(utils::packageVersion("imfexplorer")),
    imf_data_version = as.character(utils::packageVersion("imf.data")),
    query = q, dataset = dataset, excluded_selections = excluded,
    dimensions = dimensions, dimension_values = codes,
    structure_status = if (is.null(structure)) "unavailable" else "available",
    structure_error = structure_error, structure = structure,
    report_status = if (is.null(report)) "unavailable" else "available",
    report_request = report_request, report_error = report_error, report = report
  )
}

#' Flatten nested metadata into an Excel worksheet
#'
#' Represent each metadata leaf as a path and value. Split long strings into
#' ordered parts below Excel's cell limit without truncating their contents.
#'
#' @param x A nested metadata list, data frame or atomic value.
#' @return A data frame with `path`, `part` and `value` columns. Empty and NULL
#'   objects have an explicit `(none)` entry. Nested lists are traversed by the
#'   private `visit(value, path)` helper.
#' @keywords internal
metadata_table <- function(x) {
  records <- new.env(hash = TRUE, parent = emptyenv())
  records$count <- 0L
  visit <- function(value, path) {
    if (!length(value)) {
      value <- "(none)"
    } else if (is.list(value) || length(value) > 1L) {
      for (i in seq_along(value)) {
        label <- names(value)[i]
        if (is.null(label) || is.na(label) || !nzchar(label)) label <- as.character(i)
        visit(value[[i]], paste0(path, if (nzchar(path)) "/" else "", label))
      }
      return(invisible(NULL))
    }
    text <- as.character(value)
    starts <- seq.int(1L, max(1L, nchar(text, allowNA = FALSE, keepNA = FALSE)), by = 15000L)
    records$count <- records$count + 1L
    records[[as.character(records$count)]] <- list(
      path = rep(path, length(starts)), part = seq_along(starts), value = substring(text, starts, starts + 14999L)
    )
    invisible(NULL)
  }
  visit(x, "")
  rows <- mget(as.character(seq_len(records$count)), envir = records, inherits = FALSE)
  data.frame(
    path = unlist(lapply(rows, `[[`, "path"), use.names = FALSE),
    part = unlist(lapply(rows, `[[`, "part"), use.names = FALSE),
    value = unlist(lapply(rows, `[[`, "value"), use.names = FALSE),
    stringsAsFactors = FALSE
  )
}

#' Prepare metadata columns for Excel
#'
#' Encode nested columns as JSON and factors as text, retaining ordinary
#' observation numbers, text, dates and logical values.
#'
#' @param data A data frame to prepare for an Excel worksheet.
#' @return A data frame with atomic columns supported by [writexl::write_xlsx()].
#' @keywords internal
excel_frame <- function(data) {
  for (name in names(data)) {
    if (is.list(data[[name]])) {
      data[[name]] <- vapply(data[[name]], function(x) {
        as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null"))
      }, character(1))
    } else if (is.factor(data[[name]])) {
      data[[name]] <- as.character(data[[name]])
    }
  }
  data
}

#' Write observations and their metadata to an Excel workbook
#'
#' Export the immutable result snapshot to Data, Metadata, Dimensions, Codes and
#' Structure sheets, plus a Metadata_Report sheet from `sdmx_metadata()`.
#' Report Excel size limits explicitly; the RDS export retains
#' data without those worksheet limits.
#'
#' @param data Retrieved observation data frame with an `imf_metadata` attribute.
#' @param file Destination workbook path.
#' @return The path returned by [writexl::write_xlsx()], invisibly.
#' @keywords internal
write_result_excel <- function(data, file) {
  meta <- attr(data, "imf_metadata", exact = TRUE)
  if (is.null(meta)) stop("This result has no metadata snapshot. Retrieve it again before exporting.")
  code_rows <- lapply(names(meta$dimension_values), function(dim) {
    v <- meta$dimension_values[[dim]]
    data.frame(dimension = rep(dim, nrow(v)), v[c("code", "name", "description")], stringsAsFactors = FALSE)
  })
  codes <- if (length(code_rows)) {
    do.call(rbind, code_rows)
  } else {
    data.frame(dimension = character(), code = character(), name = character(), description = character())
  }
  sheets <- list(
    Data = excel_frame(data),
    Metadata = metadata_table(meta[setdiff(names(meta), c("dimensions", "dimension_values", "structure", "report"))]),
    Dimensions = excel_frame(meta$dimensions), Codes = codes,
    Structure = metadata_table(meta$structure), Metadata_Report = metadata_table(meta$report)
  )
  for (name in names(sheets)) {
    sheet <- sheets[[name]]
    if (nrow(sheet) > 1048575L || ncol(sheet) > 16384L || any(nchar(names(sheet)) > 32767L)) {
      stop("Excel worksheet size exceeded in ", name, ". Download RDS instead.")
    }
    for (column in sheet) {
      if (is.character(column) && any(nchar(column) > 32767L, na.rm = TRUE)) {
        stop("Excel cell text limit exceeded in ", name, ". Download RDS instead.")
      }
    }
  }
  invisible(writexl::write_xlsx(sheets, path = file))
}

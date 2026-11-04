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
#' @return A metadata list suitable for the `imf_metadata` data-frame attribute.
#' @keywords internal
result_metadata <- function(data, q, dataset, dimensions, values, structure = NULL,
                            structure_error = NULL, excluded = character()) {
  info <- variable_metadata(data, q, dimensions, values, structure)
  list(
    schema_version = 2L,
    retrieved_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    source = "IMF SDMX API via imf.data",
    imfexplorer_version = as.character(utils::packageVersion("imfexplorer")),
    imf_data_version = as.character(utils::packageVersion("imf.data")),
    query = q, dataset = dataset, excluded_selections = excluded,
    dimensions = dimensions, variables = info$variables, column_values = info$codes,
    dimension_values = info$codes[intersect(names(info$codes), dimensions$id)],
    structure_status = if (is.null(structure)) "unavailable" else "available",
    structure_error = structure_error, structure = structure
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
#' Export the immutable result snapshot to Data, Metadata, Variables and Codes
#' sheets. Report Excel size limits explicitly; the RDS export retains
#' data without those worksheet limits.
#'
#' @param data Retrieved observation data frame with an `imf_metadata` attribute.
#' @param file Destination workbook path.
#' @return The path returned by [writexl::write_xlsx()], invisibly.
#' @keywords internal
write_result_excel <- function(data, file) {
  meta <- attr(data, "imf_metadata", exact = TRUE)
  if (is.null(meta)) stop("This result has no metadata snapshot. Retrieve it again before exporting.")
  code_rows <- lapply(names(meta$column_values), function(dim) {
    v <- meta$column_values[[dim]]
    label <- v$name
    label[is.na(label) | !nzchar(label)] <- "(description unavailable)"
    data.frame(
      variable = rep(dim, nrow(v)), v[c("code", "name", "description")],
      definition = if (nrow(v)) paste0(v$code, ": ", label) else character(), stringsAsFactors = FALSE
    )
  })
  codes <- if (length(code_rows)) {
    do.call(rbind, code_rows)
  } else {
    data.frame(
      variable = character(), code = character(), name = character(),
      description = character(), definition = character()
    )
  }
  sheets <- list(
    Data = excel_frame(data),
    Metadata = metadata_table(meta[setdiff(names(meta), c(
      "dimensions", "dimension_values", "column_values", "variables", "structure"
    ))]),
    Variables = excel_frame(meta$variables), Codes = codes
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

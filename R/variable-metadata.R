#' Choose the first available metadata text
#'
#' @param ... Candidate scalar labels or descriptions in order of preference.
#' @return A nonempty character scalar or `NA_character_` if none is available.
#' @keywords internal
metadata_text <- function(...) {
  for (value in list(...)) {
    if (is.character(value) && length(value) == 1L && !is.na(value) && nzchar(trimws(value))) {
      return(value)
    }
  }
  NA_character_
}

#' Resolve a referenced definition within a dataset structure
#'
#' Match SDMX references by agency, ID and exact version when supplied. A dynamic
#' version can resolve to a unique returned item; ambiguous matches remain absent.
#' Concept references also identify a member of the concept scheme.
#'
#' @param items List of structural items such as concept schemes or codelists.
#' @param reference An SDMX URN, or NULL when no definition is referenced.
#' @return The referenced item or concept, or NULL if it cannot be resolved.
#' @keywords internal
structure_definition <- function(items, reference) {
  if (!scalar_text(reference)) {
    return(NULL)
  }
  pattern <- "^[^=]+=([^:]+):([^()]+)\\(([^)]+)\\)(?:\\.(.+))?$"
  parts <- regmatches(reference, regexec(pattern, reference, perl = TRUE))[[1]]
  if (length(parts) != 5L) {
    return(NULL)
  }
  matches <- Filter(function(item) identical(item$agencyID, parts[2]) && identical(item$id, parts[3]), items)
  exact <- Filter(function(item) identical(item$version, parts[4]), matches)
  if (length(exact)) matches <- exact
  if (length(matches) != 1L || (!length(exact) && !grepl("+", parts[4], fixed = TRUE))) {
    return(NULL)
  }
  item <- matches[[1]]
  if (nzchar(parts[5])) {
    concepts <- Filter(function(concept) identical(concept$id, parts[5]), item$concepts)
    if (length(concepts) != 1L) {
      return(NULL)
    }
    item <- concepts[[1]]
  }
  item
}

#' Describe returned columns and their observed codes
#'
#' Combine available labels with concepts and codelists from the selected dataset
#' structure. Local representations take priority over a concept's default
#' representation. Preserve exact upstream wording and leave missing code labels
#' missing rather than infer their meaning from the code.
#'
#' @param data Retrieved observation data frame.
#' @param q Exact observation query identifying the dataflow.
#' @param dimensions Normalized dimension definitions.
#' @param values Named available-code tables already loaded by the session.
#' @param structure Optional full dataset structure response.
#' @return A list with a `variables` data frame and named `codes` data frames for
#'   coded columns. Covers dimensions, time, measures and requested attributes.
#' @keywords internal
variable_metadata <- function(data, q, dimensions, values, structure = NULL) {
  raw <- if (is.list(structure$data)) structure$data else list()
  flows <- Filter(function(flow) {
    identical(flow$id, q$dataset) && identical(flow$agencyID, q$agency) &&
      identical(flow$version, q$version)
  }, raw$dataflows)
  dsd <- if (length(flows) == 1L) structure_definition(raw$dataStructures, flows[[1]]$structure) else NULL
  if (is.null(dsd) && length(raw$dataStructures) == 1L) dsd <- raw$dataStructures[[1]]
  components <- dsd$dataStructureComponents
  nodes <- c(
    components$dimensionList$dimensions, components$dimensionList$timeDimensions,
    components$measureList$measures, components$attributeList$attributes
  )
  codes <- new.env(parent = emptyenv())
  codes$items <- list()
  variables <- lapply(names(data), function(id) {
    index <- match(id, dimensions$id)
    node <- Filter(function(item) identical(item$id, id), nodes)
    node <- if (length(node) == 1L) node[[1]] else list()
    concept <- structure_definition(raw$conceptSchemes, node$conceptIdentity)
    fallback <- switch(id,
      OBS_VALUE = "Observation value",
      TIME_PERIOD = "Time period",
      id
    )
    label <- metadata_text(
      concept$name, concept$names$en, node$name, dimensions$name[index],
      attr(data[[id]], "label", exact = TRUE), fallback
    )
    description <- metadata_text(
      concept$description, concept$descriptions$en, node$description,
      dimensions$description[index], attr(data[[id]], "description", exact = TRUE), label
    )
    type <- metadata_text(node$type, dimensions$type[index], if (id == "OBS_VALUE") "Measure" else "Attribute")
    reference <- metadata_text(node$localRepresentation$enumeration, concept$coreRepresentation$enumeration)
    codelist <- structure_definition(raw$codelists, reference)
    if (!is.null(values[[id]]) || length(codelist$codes)) {
      observed <- unique(as.character(data[[id]]))
      observed <- observed[!is.na(observed)]
      available <- values[[id]]
      if (is.null(available)) available <- normalize_values(data.frame(code = character()))
      labels <- available[match(observed, available$code), c("code", "name", "description"), drop = FALSE]
      labels$code <- observed
      for (i in seq_along(observed)) {
        entry <- Filter(function(code) identical(code$id, observed[i]), codelist$codes)
        entry <- if (length(entry) == 1L) entry[[1]] else list()
        labels$name[i] <- metadata_text(labels$name[i], entry$name, entry$names$en)
        labels$description[i] <- metadata_text(labels$description[i], entry$description, entry$descriptions$en)
      }
      rownames(labels) <- NULL
      codes$items[[id]] <- labels
    }
    data.frame(variable = id, label = label, description = description, type = type, stringsAsFactors = FALSE)
  })
  list(variables = do.call(rbind, variables), codes = codes$items)
}

#' Attach variable descriptions to retrieved columns
#'
#' Add human-readable variable labels and descriptions without changing column
#' values, storage types, classes or existing unrelated attributes.
#'
#' @param data Retrieved observation data frame.
#' @param metadata Metadata snapshot returned by [result_metadata()].
#' @return The data frame with `label` and `description` on each column, named
#'   `code_labels` and `code_descriptions` on coded columns, and the complete
#'   `imf_metadata` snapshot on the data frame.
#' @keywords internal
annotate_result <- function(data, metadata) {
  for (i in seq_len(nrow(metadata$variables))) {
    variable <- metadata$variables[i, ]
    id <- variable$variable
    attr(data[[id]], "label") <- variable$label
    attr(data[[id]], "description") <- variable$description
    codes <- metadata$column_values[[id]]
    if (!is.null(codes)) {
      attr(data[[id]], "code_labels") <- stats::setNames(codes$name, codes$code)
      attr(data[[id]], "code_descriptions") <- stats::setNames(codes$description, codes$code)
    }
  }
  attr(data, "imf_metadata") <- metadata
  data
}

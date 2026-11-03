#' Create the session-isolated explorer server
#'
#' Create a Shiny server function with an injectable API boundary and one
#' metadata cache, query state and observer registry for each browser session.
#'
#' @param agency_id Character scalar identifying the initial IMF maintainer.
#' @param api An adapter list supplying `datasets(agency)`, `dimensions(q)`,
#'   `values(q, dimension)` and `data(q)` functions. Metadata methods must return
#'   the normalized schemas documented by [imf_adapter()].
#' @return A function with Shiny's `input`, `output` and `session` arguments.
#'   The input object supplies controls, the output object receives renderers,
#'   and the session object manages UI updates and downloads.
#' @details The initial session requests only the catalogue. Dataset selection
#'   loads its dimensions and available values. Retrieval validates a single
#'   query snapshot, refreshes stale availability, and downloads observations
#'   only after the Retrieve data action and any required acknowledgement.
#'   Imports retain unavailable codes for correction. Optional exclusion removes
#'   flagged codes before retrieval and stops if a selected dimension would
#'   become unrestricted. Results retain their
#'   original query for stale-result warnings and exports.
#' @section Session-local helpers:
#' The returned server creates these private functions for each connection:
#' \describe{
#'   \item{\code{notify(text, type)}}{Displays a notification and returns its ID.}
#'   \item{\code{control_id(i)}}{Returns the generation-specific ID for the
#'     dimension at one-based position \code{i}.}
#'   \item{\code{text_or_null(x)}}{Trims an optional character control value,
#'     returning NULL when it is absent or blank.}
#'   \item{\code{reset_dataset()}}{Destroys old dimension observers and clears
#'     dataset-dependent selections, time options, attributes and results.}
#'   \item{\code{load_catalog(agency, refresh)}}{Loads the catalogue, optionally
#'     clears the metadata cache, updates error state and returns success.}
#'   \item{\code{push_values(q, dimensions)}}{Updates the named dimension
#'     controls from current availability while retaining selections.}
#'   \item{\code{update_values(q, only_stale, update_controls)}}{Refreshes all or only stale
#'     availability for one query snapshot and updates affected controls.}
#'   \item{\code{select_all_dimension(i)}}{Selects all available codes at the
#'     dimension's one-based position while retaining flagged codes.}
#'   \item{\code{choose_dataset(row, restore)}}{Loads a one-row catalogue
#'     selection, optionally restores a saved query, and returns success.}
#'   \item{\code{query_issue(q)}}{Validates availability for an explicit query snapshot.}
#'   \item{\code{prepare_retrieval(q)}}{Optionally excludes flagged selections,
#'     rechecks availability, and returns the query, removed codes and any error.}
#'   \item{\code{clear_current_query()}}{Resets the query, search and selected
#'     catalogue row, then returns to dataset navigation.}
#' }
#' @section Session-local reactives:
#' \describe{
#'   \item{\code{non_time()}}{Returns non-time dimension metadata.}
#'   \item{\code{filters()}}{Returns canonical current dimension selections.}
#'   \item{\code{query()}}{Returns a snapshot of identity, filters, active time
#'     options and attributes once a dataset is selected.}
#'   \item{\code{query_problem()}}{Returns the first configuration or
#'     availability issue, or NULL when validation succeeds.}
#'   \item{\code{plan()}}{Returns a plotting plan once results exist.}
#' }
#' @seealso [explorer_app()], [new_query()], [cached()]
#'
#' @keywords internal
explorer_server <- function(agency_id, api) {
  force(api)
  force(agency_id)
  function(input, output, session) {
    cache <- new.env(parent = emptyenv())
    rv <- shiny::reactiveValues(
      catalog = NULL, catalog_error = NULL, dataset = NULL,
      dimensions = NULL, values = list(), value_errors = list(),
      availability_keys = list(),
      seed = list(), generation = 0L, results = NULL, result_query = NULL,
      result_dimensions = NULL, result_error = NULL, result_exclusions = character()
    )
    clear_observers <- new.env(parent = emptyenv())
    clear_observers$items <- list()
    # Show a session notification
    #
    # @param text Character scalar message to display.
    # @param type Shiny notification type, such as `"error"` or `"warning"`.
    # @return The notification ID returned by [shiny::showNotification()].
    notify <- function(text, type = "error") shiny::showNotification(text, type = type, duration = 12)
    # Create a dataset-generation-specific dimension control ID
    #
    # @param i One-based row index in the non-time dimension metadata.
    # @return A character scalar that avoids reusing a previous dataset's inputs.
    control_id <- function(i) paste0("dim_", rv$generation, "_", i)
    # Read the selected dataset's non-time dimension metadata
    #
    # @return A reactive data frame excluding time dimensions, or an empty
    #   dimension frame before metadata has loaded.
    non_time <- shiny::reactive({
      d <- rv$dimensions
      if (is.null(d)) {
        return(data.frame(id = character(), name = character()))
      }
      d[!d$is_time, , drop = FALSE]
    })
    # Read and canonicalize the dimension controls
    #
    # @return A reactive named filter list. Pending controls use imported seed
    #   selections; bound controls provide their current selections.
    filters <- shiny::reactive({
      d <- non_time()
      out <- lapply(seq_len(nrow(d)), function(i) {
        id <- control_id(i)
        if (id %in% names(input)) input[[id]] else rv$seed[[d$id[i]]]
      })
      names(out) <- d$id
      canonical_filters(out)
    })
    # Snapshot the current query controls
    #
    # @return A reactive query list containing exact dataset identity, canonical
    #   filters, active time options and requested attributes. Suspends until a
    #   dataset has been selected.
    query <- shiny::reactive({
      shiny::req(rv$dataset)
      mode <- input$time_mode
      # Normalize an optional time-bound input
      #
      # @param x A NULL or scalar character control value.
      # @return A trimmed character scalar or NULL for an absent or blank value.
      text_or_null <- function(x) if (is.null(x) || !nzchar(trimws(x))) NULL else trimws(x)
      attrs <- if (is.null(input$attributes) || !nzchar(trimws(input$attributes))) {
        character()
      } else {
        trimws(strsplit(input$attributes, ",", fixed = TRUE)[[1]])
      }
      new_query(
        rv$dataset$agency[[1]], rv$dataset$id[[1]], rv$dataset$version[[1]], filters(),
        if (identical(mode, "range")) text_or_null(input$start) else NULL,
        if (identical(mode, "range")) text_or_null(input$end) else NULL,
        if (identical(mode, "latest")) input$latest else NULL, attrs
      )
    })
    # Reset dataset-dependent state and controls
    #
    # @return Invisibly NULL after destroying old dimension observers and clearing
    #   dataset metadata, filters, time options, attributes and retrieved results.
    #   The agency catalogue and session metadata cache are retained.
    reset_dataset <- function() {
      for (o in clear_observers$items) o$destroy()
      clear_observers$items <- list()
      fresh <- empty_dataset_state()
      rv$dataset <- fresh$dataset
      rv$dimensions <- fresh$dimensions
      rv$values <- fresh$values
      rv$seed <- fresh$filters
      rv$availability_keys <- list()
      rv$value_errors <- list()
      rv$results <- fresh$results
      rv$result_query <- fresh$result_query
      rv$result_dimensions <- NULL
      rv$result_error <- NULL
      rv$result_exclusions <- character()
      shiny::updateCheckboxInput(session, "exclude_unavailable", value = FALSE)
      rv$generation <- rv$generation + 1L
      shiny::updateRadioButtons(session, "time_mode", selected = "all")
      shiny::updateTextInput(session, "start", value = "")
      shiny::updateTextInput(session, "end", value = "")
      shiny::updateTextInput(session, "attributes", value = "")
      shiny::updateNumericInput(session, "latest", value = 12)
      shiny::updateCheckboxInput(session, "broad_ok", value = FALSE)
    }
    # Load an agency catalogue through the session cache
    #
    # @param agency Character scalar identifying the selected agency.
    # @param refresh Whether to clear the session metadata cache before loading.
    # @return A logical success flag. Catalogue state and failure messages are
    #   updated for the current session.
    load_catalog <- function(agency, refresh = FALSE) {
      if (!scalar_text(agency)) {
        notify("Enter an agency ID.")
        return(FALSE)
      }
      if (refresh) rm(list = ls(cache, all.names = TRUE), envir = cache)
      ans <- attempt(cached(cache, cache_key("datasets", list(agency = agency)), function() api$datasets(agency)))
      rv$catalog_error <- ans$error
      rv$catalog <- if (ans$ok) ans$value else NULL
      if (!ans$ok) notify(paste("Catalogue request failed:", ans$error))
      ans$ok
    }
    # Update bound dimension controls without changing selections
    #
    # @param q Query snapshot whose selections must be retained.
    # @param dimensions Character vector of dimension IDs to update.
    # @return Invisibly NULL after registering server-side choice sources for
    #   the requested controls, including retained unverified codes.
    push_values <- function(q, dimensions = non_time()$id) {
      d <- non_time()
      for (i in seq_len(nrow(d))) {
        if (!d$id[i] %in% dimensions) next
        choices <- dimension_choices(rv$values[[d$id[i]]], q$filters[[d$id[i]]])
        shiny::updateSelectizeInput(session, control_id(i),
          choices = choices,
          selected = q$filters[[d$id[i]]], server = TRUE
        )
      }
    }
    # Refresh conditional dimension availability
    #
    # @param q Query snapshot used consistently for all availability requests.
    # @param only_stale Whether to skip already successful, current code lists.
    # @param update_controls Whether to send the snapshot selections to the browser.
    # @return Invisibly NULL after updating availability, error and cache-key state
    #   and refreshing affected controls. Each request excludes its own filter.
    update_values <- function(q = shiny::isolate(query()), only_stale = FALSE, update_controls = TRUE) {
      d <- shiny::isolate(non_time())
      vals <- shiny::isolate(rv$values)
      errs <- shiny::isolate(rv$value_errors)
      keys <- shiny::isolate(rv$availability_keys)
      refreshed <- character()
      if (only_stale && all(vapply(d$id, function(dim) {
        identical(keys[[dim]], cache_key("values", q, dim)) &&
          is.null(errs[[dim]]) && !is.null(vals[[dim]])
      }, logical(1)))) {
        return(invisible(NULL))
      }
      shiny::withProgress(message = "Updating available dimension values", value = 0, {
        for (i in seq_len(nrow(d))) {
          dimension <- d$id[i]
          k <- cache_key("values", q, dimension)
          fresh <- identical(keys[[dimension]], k) &&
            is.null(errs[[dimension]]) && !is.null(vals[[dimension]])
          if (only_stale && fresh) {
            next
          }
          refreshed <- c(refreshed, dimension)
          ans <- attempt(cached(cache, k, function() api$values(q, dimension)))
          keys[[dimension]] <- if (ans$ok) k else NULL
          errs[[dimension]] <- ans$error
          if (ans$ok) vals[[dimension]] <- ans$value
          shiny::incProgress(1 / max(1, nrow(d)))
        }
      })
      rv$values <- vals
      rv$value_errors <- errs
      rv$availability_keys <- keys
      if (update_controls) push_values(q, refreshed)
    }
    # Select every currently available code for one dimension
    #
    # @param i One-based row index in the non-time dimension metadata.
    # @return The selectize update result, or NULL after an availability failure.
    #   Existing unavailable selections are retained; stale availability is checked
    #   using the other current dimension filters before selecting all.
    select_all_dimension <- function(i) {
      q <- query()
      dim <- non_time()$id[i]
      key <- cache_key("values", q, dim)
      # A stale list must be checked under the current other-dimension filters.
      if (!identical(rv$availability_keys[[dim]], key)) {
        ans <- shiny::withProgress(
          message = paste("Loading available codes for", dim), value = 0.5,
          attempt(cached(cache, key, function() api$values(q, dim)))
        )
        rv$value_errors[[dim]] <- ans$error
        rv$availability_keys[[dim]] <- if (ans$ok) key else NULL
        if (!ans$ok) {
          notify(paste("Cannot select all for", dim, ":", ans$error))
          return()
        }
        rv$values[[dim]] <- ans$value
      }
      values <- rv$values[[dim]]
      selected <- union(q$filters[[dim]], values$code)
      if (!nrow(values)) notify(paste("No available codes for", dim, "under the current filters."), "warning")
      shiny::updateSelectizeInput(session, control_id(i),
        choices = dimension_choices(values, selected), selected = selected, server = TRUE
      )
    }
    # Activate a dataset and optionally restore a saved query
    #
    # @param row A one-row normalized catalogue data frame.
    # @param restore Optional validated query configuration to restore.
    # @return A logical success flag after resetting dependent state and loading
    #   dimensions and code lists for the exact selected version.
    choose_dataset <- function(row, restore = NULL) {
      reset_dataset()
      rv$dataset <- row
      q <- new_query(row$agency[[1]], row$id[[1]], row$version[[1]])
      ans <- attempt(cached(cache, cache_key("dimensions", q), function() api$dimensions(q)))
      if (!ans$ok) {
        notify(paste("Dimensions request failed:", ans$error))
        return(FALSE)
      }
      rv$dimensions <- ans$value
      if (!is.null(restore)) {
        valid <- attempt(validate_query(restore, rv$dimensions))
        if (!valid$ok) {
          notify(valid$error)
          return(FALSE)
        }
        rv$seed <- restore$filters
        mode <- if (!is.null(restore$last_n_obs)) {
          "latest"
        } else if (!is.null(restore$start_period) || !is.null(restore$end_period)) {
          "range"
        } else {
          "all"
        }
        shiny::updateRadioButtons(session, "time_mode", selected = mode)
        shiny::updateTextInput(session, "start",
          value = if (is.null(restore$start_period)) "" else restore$start_period
        )
        shiny::updateTextInput(session, "end", value = if (is.null(restore$end_period)) "" else restore$end_period)
        if (!is.null(restore$last_n_obs)) shiny::updateNumericInput(session, "latest", value = restore$last_n_obs)
        shiny::updateTextInput(session, "attributes", value = paste(restore$attributes, collapse = ", "))
        q <- restore
      }
      d <- non_time()
      for (i in seq_len(nrow(d))) {
        local({
          j <- i
          id <- control_id(j)
          dim <- d$id[j]
          clear_observers$items[[length(clear_observers$items) + 1L]] <- shiny::observeEvent(
            input[[paste0(id, "_clear")]],
            {
              shiny::updateSelectizeInput(session, id, selected = character())
            },
            ignoreInit = TRUE
          )
          clear_observers$items[[length(clear_observers$items) + 1L]] <- shiny::observeEvent(
            input[[paste0(id, "_all")]],
            {
              select_all_dimension(j)
            },
            ignoreInit = TRUE
          )
          output[[paste0(id, "_selection")]] <- shiny::renderUI({
            n <- length(filters()[[dim]])
            shiny::tags$span(
              class = paste("imf-selection-badge", if (n) "imf-has-selection"),
              if (n) paste(n, "selected") else "Unrestricted"
            )
          })
          output[[paste0(id, "_status")]] <- shiny::renderUI({
            current <- query()
            v <- rv$values[[dim]]
            err <- rv$value_errors[[dim]]
            if (is.null(v)) v <- data.frame(code = character())
            stale <- !identical(rv$availability_keys[[dim]], cache_key("values", current, dim))
            status <- selection_status(current$filters[[dim]], v, err)
            tone <- if (!is.null(err) || (!stale && length(status$invalid))) {
              "error"
            } else if (stale) {
              "pending"
            } else {
              "ready"
            }
            status_icon <- switch(tone,
              error = "circle-exclamation",
              pending = "clock",
              ready = "circle-check"
            )
            message <- if (stale && is.null(err)) {
              "Availability is checked automatically on retrieval. Refresh choices to browse matching codes."
            } else {
              status$message
            }
            shiny::tags$div(
              class = paste("imf-dimension-status", paste0("imf-status-", tone)),
              role = "status", shiny::icon(status_icon), shiny::tags$span(message)
            )
          })
        })
      }
      update_values(q)
      bslib::nav_select("stage", "dimensions", session = session)
      TRUE
    }
    shiny::observeEvent(TRUE, load_catalog(agency_id), once = TRUE)
    shiny::observeEvent(input$load, {
      reset_dataset()
      load_catalog(trimws(input$agency), refresh = TRUE)
    })
    # Clear the query and return to the catalogue
    #
    # @return The navigation update result after resetting dependent state,
    #   deselecting catalogue rows and clearing dataset search. Loaded catalogue
    #   metadata and the session cache are retained.
    clear_current_query <- function() {
      reset_dataset()
      shiny::updateTextInput(session, "dataset_search", value = "")
      proxy <- DT::dataTableProxy("datasets", session = session)
      DT::selectRows(proxy, NULL)
      DT::updateSearch(proxy, keywords = list(global = ""))
      bslib::nav_select("stage", "dataset", session = session)
    }
    shiny::observeEvent(input$reset, clear_current_query())
    shiny::observeEvent(input$clear_query, clear_current_query())
    shiny::observeEvent(input$dataset_search,
      {
        DT::updateSearch(DT::dataTableProxy("datasets", session = session),
          keywords = list(global = input$dataset_search)
        )
      },
      ignoreInit = TRUE
    )
    shiny::observeEvent(input$refresh, {
      row <- rv$dataset
      saved <- if (!is.null(row) && !is.null(rv$dimensions)) query() else NULL
      agency <- if (!is.null(row)) row$agency[[1]] else input$agency
      if (load_catalog(agency, refresh = TRUE) && !is.null(row)) {
        matches <- which(
          rv$catalog$agency == row$agency[[1]] & rv$catalog$id == row$id[[1]] &
            rv$catalog$version == row$version[[1]]
        )
        if (!length(matches)) {
          reset_dataset()
          notify("Selected dataset/version is no longer in the catalogue.")
        } else {
          choose_dataset(rv$catalog[matches[1], , drop = FALSE], saved)
        }
      }
    })
    shiny::observeEvent(input$datasets_rows_selected, {
      i <- input$datasets_rows_selected
      if (length(i) == 1L && !is.null(rv$catalog) && i <= nrow(rv$catalog)) {
        choose_dataset(rv$catalog[i, , drop = FALSE])
      }
    })
    shiny::observeEvent(input$update, {
      shiny::req(rv$dimensions)
      update_values()
    })
    shiny::observeEvent(input$next_time, bslib::nav_select("stage", "time", session = session))
    # renderUI inputs bind in the browser after the server's output flush.
    # Register remote selectize sources only after that browser acknowledges them.
    shiny::observeEvent(input$dimensions_ready, {
      if (!identical(as.integer(input$dimensions_ready), rv$generation)) {
        return()
      }
      push_values(query())
    })
    shiny::observeEvent(input$import, {
      result <- attempt({
        if (input$import$size > 1024^2) stop("Configuration is larger than 1 MB.")
        cfg <- parse_config(paste(readLines(input$import$datapath, warn = FALSE), collapse = "\n"))
        cat <- cached(cache, cache_key("datasets", list(agency = cfg$agency)), function() api$datasets(cfg$agency))
        matches <- which(cat$agency == cfg$agency & cat$id == cfg$dataset & cat$version == cfg$version)
        if (!length(matches)) stop("Unavailable dataset or version: ", cfg$agency, "/", cfg$dataset, "/", cfg$version)
        row <- cat[matches[1], , drop = FALSE]
        dims <- cached(cache, cache_key("dimensions", cfg), function() api$dimensions(cfg))
        validate_query(cfg, dims)
        rv$catalog <- cat
        rv$catalog_error <- NULL
        shiny::updateTextInput(session, "agency", value = cfg$agency)
        choose_dataset(row, cfg)
      })
      if (!result$ok) {
        notify(paste("Import failed:", result$error))
      } else {
        notify("Configuration restored. Review your selections; availability will be checked on retrieval.", "message")
      }
    })
    output$catalog_status <- shiny::renderUI({
      if (!is.null(rv$catalog_error)) {
        shiny::tags$p(role = "alert", paste("Catalogue API failure:", rv$catalog_error))
      } else if (!is.null(rv$catalog) && !nrow(rv$catalog)) {
        shiny::tags$p("No datasets were returned for this agency.")
      }
    })
    output$datasets <- DT::renderDT(
      {
        shiny::req(rv$catalog)
        columns <- c("id", "name", "description", "version")
        fields <- input$dataset_search_fields
        # Before the checkbox group binds, use its three default fields.
        if (!"dataset_search_fields" %in% names(input)) fields <- c("id", "name", "description")
        searchable <- columns %in% intersect(fields, c("id", "name", "description"))
        DT::datatable(rv$catalog[columns],
          rownames = FALSE, selection = "single", escape = TRUE,
          options = list(
            pageLength = 10, scrollX = TRUE, searching = TRUE,
            columnDefs = list(list(targets = which(!searchable) - 1L, searchable = FALSE)),
            dom = "<'imf-hidden-filter'f>lrtip", search = list(search = shiny::isolate(
              if (is.null(input$dataset_search)) "" else input$dataset_search
            ))
          )
        )
      },
      server = TRUE
    )
    output$metadata <- shiny::renderUI({
      shiny::req(rv$dataset)
      r <- rv$dataset
      shiny::tagList(
        shiny::h4(readable(r$name, r$id)), shiny::p(r$description),
        shiny::p(paste("Agency:", r$agency, "Version:", r$version)),
        if (is.null(rv$dimensions)) shiny::p("Dimensions unavailable. Use refresh to retry.")
      )
    })
    output$dimension_overview <- shiny::renderUI({
      if (is.null(rv$dataset)) {
        return(shiny::tags$p("Choose a dataset to see its dimensions."))
      }
      d <- non_time()
      f <- filters()
      shiny::tagList(
        shiny::tags$div(
          class = "imf-dataset-context", readable(rv$dataset$name, rv$dataset$id),
          shiny::tags$span(paste(rv$dataset$agency, " / ", rv$dataset$version))
        ),
        shiny::tags$div(
          class = "imf-selection-metrics",
          shiny::tags$span(class = "imf-metric", paste(length(f), "of", nrow(d), "dimensions filtered")),
          shiny::tags$span(class = "imf-metric", paste(sum(lengths(f)), "selected codes"))
        )
      )
    })
    output$dimension_controls <- shiny::renderUI({
      d <- non_time()
      if (is.null(rv$dataset)) {
        return(shiny::tags$div(
          class = "imf-empty-state",
          shiny::icon("sliders"), shiny::h4("Start with a dataset"),
          shiny::p("Select a dataset in the first tab to explore its dimensions.")
        ))
      }
      if (is.null(rv$dimensions)) {
        return(shiny::p("Dimensions could not be loaded. Refresh to retry."))
      }
      if (!nrow(d)) {
        return(shiny::p("No non-time dimensions in this dataset."))
      }
      shiny::tagList(shiny::tags$script(shiny::HTML(sprintf(
        "setTimeout(function(){Shiny.setInputValue('dimensions_ready', %d, {priority:'event'});}, 0);",
        rv$generation
      ))), shiny::tags$div(class = "imf-dimension-grid", lapply(seq_len(nrow(d)), function(i) {
        id <- control_id(i)
        title <- if (is.na(d$name[i]) || !nzchar(d$name[i])) d$id[i] else d$name[i]
        shiny::tags$section(
          class = "imf-dimension-card", `aria-label` = paste(title, "dimension"),
          shiny::tags$div(
            class = "imf-dimension-heading",
            shiny::tags$div(shiny::tags$h4(title), shiny::tags$code(d$id[i])),
            shiny::uiOutput(paste0(id, "_selection"))
          ),
          shiny::tags$label(class = "imf-control-label", `for` = id, "Search and select values"),
          shiny::selectizeInput(id, NULL,
            choices = shiny::isolate(rv$seed[[d$id[i]]]), selected = shiny::isolate(rv$seed[[d$id[i]]]),
            multiple = TRUE, width = "100%",
            options = list(
              placeholder = "Type a code or label...", maxOptions = 200,
              plugins = list("remove_button")
            )
          ),
          shiny::tags$div(
            class = "imf-dimension-actions",
            shiny::actionButton(paste0(id, "_all"), "Select all available",
              icon = shiny::icon("check-double"), class = "btn-sm btn-outline-primary"
            ),
            shiny::actionButton(paste0(id, "_clear"), "Clear",
              icon = shiny::icon("xmark"), class = "btn-sm btn-outline-secondary"
            )
          ),
          shiny::uiOutput(paste0(id, "_status"))
        )
      })))
    })
    output$summary <- shiny::renderUI({
      if (is.null(rv$dataset)) {
        return(shiny::p("Choose a dataset to begin."))
      }
      q <- query()
      d <- non_time()
      shiny::tagList(
        shiny::strong(readable(rv$dataset$name, q$dataset)),
        shiny::p(paste("Agency:", q$agency, " \u00b7 Version:", q$version)),
        lapply(seq_len(nrow(d)), function(i) {
          id <- d$id[i]
          selected <- q$filters[[id]]
          v <- rv$values[[id]]
          labels <- if (!length(selected)) {
            "Unrestricted"
          } else if (is.null(v)) {
            paste(selected, collapse = ", ")
          } else {
            paste(readable(v$name[match(selected, v$code)], selected), collapse = ", ")
          }
          shiny::p(shiny::strong(readable(d$name[i], id)), shiny::br(), labels)
        }), shiny::p(if (!is.null(q$last_n_obs)) {
          paste("Latest", q$last_n_obs, "per series")
        } else {
          paste(
            "Time:", if (is.null(q$start_period)) "unbounded" else q$start_period, "to",
            if (is.null(q$end_period)) "unbounded" else q$end_period
          )
        }),
        if (length(q$attributes)) shiny::p(paste("Attributes:", paste(q$attributes, collapse = ", ")))
      )
    })
    # Describe the first query validation or availability issue
    #
    # @param q Explicit query snapshot to validate.
    # @return A character scalar describing an input, availability,
    #   invalid-code or empty-response issue, or NULL when no problem is found.
    #   Stale availability is reported as pending automatic retrieval checks.
    query_issue <- function(q) {
      if (is.null(rv$dataset) || is.null(rv$dimensions)) {
        return("Choose a dataset with successfully loaded dimensions.")
      }
      valid <- attempt(validate_query(q, rv$dimensions))
      if (!valid$ok) {
        return(valid$error)
      }
      for (dim in non_time()$id) {
        if (!is.null(rv$value_errors[[dim]])) {
          return(paste("Availability API failure for", dim, "\u2014 retry retrieval or update available values."))
        }
        if (!identical(rv$availability_keys[[dim]], cache_key("values", q, dim))) {
          return("Availability will be checked automatically when you retrieve data.")
        }
        v <- rv$values[[dim]]
        if (is.null(v)) {
          return(paste("Load available values for", dim))
        }
        invalid <- setdiff(q$filters[[dim]], v$code)
        if (length(invalid)) {
          return(paste("Unavailable codes for", dim, ":", paste(invalid, collapse = ", ")))
        }
        if (!nrow(v)) {
          return(paste("No available values for", dim, "under the current filters."))
        }
      }
      NULL
    }
    query_problem <- shiny::reactive({
      if (is.null(rv$dataset)) query_issue(NULL) else query_issue(query())
    })
    # Prepare one retrieval snapshot, rechecking after each removal.
    #
    # @param q Current query snapshot.
    # @return A list with query, excluded code descriptions and an optional error.
    #   Never clears a whole selected dimension or trusts a failed metadata call.
    prepare_retrieval <- function(q) {
      excluded <- character()
      repeat {
        update_values(q, only_stale = TRUE, update_controls = !isTRUE(input$exclude_unavailable))
        changed <- FALSE
        if (isTRUE(input$exclude_unavailable)) {
          for (dim in names(q$filters)) {
            selected <- q$filters[[dim]]
            verified <- is.null(rv$value_errors[[dim]]) &&
              identical(rv$availability_keys[[dim]], cache_key("values", q, dim)) &&
              !is.null(rv$values[[dim]])
            keep <- if (verified) intersect(selected, rv$values[[dim]]$code) else character()
            removed <- setdiff(selected, keep)
            if (!length(removed)) next
            if (!length(keep)) {
              return(list(query = q, excluded = excluded, error = paste(
                "No verified selected codes remain for", dim,
                "\u2014 choose an available value or explicitly clear this dimension before retrieval."
              )))
            }
            excluded <- c(excluded, paste0(dim, ": ", paste(removed, collapse = ", ")))
            q$filters[[dim]] <- keep
            changed <- TRUE
            # Refresh before assessing another dimension under the changed query.
            break
          }
        }
        if (!changed) break
      }
      list(query = q, excluded = excluded, error = query_issue(q))
    }
    output$validation <- shiny::renderUI({
      p <- query_problem()
      shiny::p(if (is.null(p)) "Query is valid. Review the code and proceed to Retrieve & export." else p)
    })
    output$code <- shiny::renderText({
      shiny::req(rv$dataset)
      a <- attempt(query_code(query()))
      if (a$ok) a$value else paste("Correct query inputs:", a$error)
    })
    output$breadth <- shiny::renderUI({
      shiny::req(rv$dimensions)
      if (broad_query(query(), rv$dimensions)) {
        shiny::tags$p(
          role = "alert",
          paste(
            "Potentially broad request: dimensions/time may be unrestricted or many codes are selected.",
            "Latest N limits observations per series only.",
            "Code combinations are not a count of available series."
          )
        )
      }
    })
    # Any query change revokes previous broad-request acknowledgement.
    shiny::observeEvent(query(), shiny::updateCheckboxInput(session, "broad_ok", value = FALSE), ignoreInit = TRUE)
    shiny::observeEvent(input$retrieve, {
      if (is.null(rv$dataset) || is.null(rv$dimensions)) {
        notify("Choose a dataset with successfully loaded dimensions.")
        return()
      }
      rv$result_exclusions <- character()
      q <- query()
      basic <- attempt(validate_query(q, rv$dimensions))
      if (!basic$ok) {
        rv$result_error <- basic$error
        notify(basic$error)
        return()
      }
      if (broad_query(q, rv$dimensions) && !isTRUE(input$broad_ok)) {
        notify("Confirm the broad-request warning before retrieving.")
        return()
      }
      prepared <- prepare_retrieval(q)
      if (!is.null(prepared$error)) {
        if (isTRUE(input$exclude_unavailable)) push_values(q)
        rv$result_error <- prepared$error
        notify(prepared$error)
        return()
      }
      q <- prepared$query
      rv$result_exclusions <- prepared$excluded
      if (isTRUE(input$exclude_unavailable)) push_values(q)
      if (length(prepared$excluded)) {
        rv$seed <- q$filters
        notify(paste("Excluded selections:", paste(prepared$excluded, collapse = "; ")), "warning")
      }
      ans <- shiny::withProgress(message = "Retrieving IMF observations", value = 0.5, attempt(api$data(q)))
      rv$result_error <- ans$error
      if (!ans$ok) {
        notify(paste("Retrieval failed:", ans$error))
        return()
      }
      rv$results <- ans$value
      rv$result_query <- q
      rv$result_dimensions <- rv$dimensions
    })
    output$result_status <- shiny::renderUI({
      shiny::tagList(
        if (length(rv$result_exclusions)) {
          shiny::p(role = "status", paste("Excluded selections:", paste(rv$result_exclusions, collapse = "; ")))
        },
        if (!is.null(rv$result_error)) shiny::p(role = "alert", paste("Latest retrieval failed:", rv$result_error)),
        if (!is.null(rv$results)) {
          count <- series_info(rv$results, rv$result_dimensions)$count
          shiny::tagList(
            shiny::p(paste(
              nrow(rv$results), "returned observations;",
              if (is.na(count)) "series count unavailable" else paste(count, "returned series")
            )),
            shiny::p(paste("Result:", rv$result_query$agency, rv$result_query$dataset, rv$result_query$version)),
            if (!same_query(query(), rv$result_query)) {
              shiny::tags$strong(role = "alert", paste(
                "EARLIER QUERY: these results and CSV/RDS downloads belong to an earlier selection.",
                "Retrieve again to update."
              ))
            },
            shiny::tags$details(
              shiny::tags$summary("Query used for these results"),
              shiny::tags$pre(query_code(rv$result_query))
            )
          )
        } else {
          shiny::p("No data retrieved in this dataset selection.")
        }
      )
    })
    output$results <- DT::renderDT(
      {
        shiny::req(rv$results)
        DT::datatable(rv$results,
          rownames = FALSE, escape = TRUE,
          options = list(pageLength = 25, scrollX = TRUE)
        )
      },
      server = TRUE
    )
    # Prepare the retrieved result for plotting
    #
    # @return A reactive plotting-plan list from [plot_plan()]. Suspends until
    #   an observation response is available.
    plan <- shiny::reactive({
      shiny::req(rv$results)
      plot_plan(rv$results, rv$result_dimensions)
    })
    output$plot_status <- shiny::renderUI({
      shiny::req(rv$results)
      shiny::p(plan()$message)
    })
    output$plot_container <- shiny::renderUI({
      shiny::req(rv$results)
      p <- plan()
      if (p$ok) shiny::plotOutput("series_plot", height = paste0(max(300, length(p$groups) * 230), "px"))
    })
    output$series_plot <- shiny::renderPlot({
      shiny::req(plan()$ok)
      draw_series(rv$results, plan())
    })
    output$csv <- shiny::downloadHandler(filename = function() "imf-data.csv", content = function(file) {
      shiny::req(rv$results)
      utils::write.csv(rv$results, file, row.names = FALSE, na = "")
    })
    output$rds <- shiny::downloadHandler(filename = function() "imf-data.rds", content = function(file) {
      shiny::req(rv$results)
      saveRDS(rv$results, file)
    })
    output$script <- shiny::downloadHandler(filename = function() "imf-query.R", content = function(file) {
      writeLines(query_code(query()), file, useBytes = TRUE)
    })
    output$config <- shiny::downloadHandler(filename = function() "imf-query.json", content = function(file) {
      writeLines(query_json(query()), file, useBytes = TRUE)
    })
  }
}

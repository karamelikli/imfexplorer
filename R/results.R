series_info <- function(data, dimensions) {
  ids <- dimensions$id[!dimensions$is_time]
  if (!all(ids %in% names(data))) return(list(count = NA_integer_, ids = ids))
  list(count = if (!nrow(data)) 0L else if (!length(ids)) 1L else nrow(unique(data[ids])), ids = ids)
}

plot_plan <- function(data, dimensions) {
  bad <- function(message) list(ok = FALSE, message = message)
  info <- series_info(data, dimensions)
  if (!nrow(data)) return(bad("No observations to plot."))
  if (is.na(info$count)) return(bad("Series dimensions are missing; unrelated series cannot be safely identified."))
  if (!all(c("TIME_PERIOD", "OBS_VALUE") %in% names(data)) || !is.numeric(data$OBS_VALUE))
    return(bad("Plot needs TIME_PERIOD and numeric OBS_VALUE columns. The original table remains available."))
  time <- vapply(as.character(data$TIME_PERIOD), period_number, numeric(1))
  if (anyNA(time)) return(bad("Plot supports annual, quarterly, monthly and daily periods only."))
  units <- grep("UNIT|SCALE|MULT", names(data), value = TRUE, ignore.case = TRUE)
  ids <- unique(c(info$ids, units))
  # JSON row serialization avoids collisions from separators in codes.
  keys <- if (length(ids)) vapply(seq_len(nrow(data)), function(i)
    jsonlite::toJSON(as.list(data[i, ids, drop = FALSE]), auto_unbox = TRUE, na = "null"), character(1)) else
      rep("Series", nrow(data))
  groups <- split(seq_len(nrow(data)), factor(keys, levels = unique(keys)))
  if (length(groups) > 12L) return(bad("More than 12 series/unit combinations. Narrow the query to plot; all data remain in the table."))
  if (any(vapply(groups, function(i) anyDuplicated(time[i]) > 0, logical(1))))
    return(bad("Duplicate periods within a series/unit combination; plotting could connect unrelated observations."))
  list(ok = TRUE, time = time, groups = groups, ids = ids, units = units,
       message = if (!length(units))
         "Separate panels per dimension combination. Units were not supplied by get_data(); values are plotted unchanged. Request exact unit attribute IDs to include them." else
         "Separate panels per dimension and unit combination; original values and unit codes are unchanged.")
}

draw_series <- function(data, plan) {
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old))
  graphics::par(mfrow = c(length(plan$groups), 1), mar = c(3, 4, 3, 1))
  for (rows in plan$groups) {
    rows <- rows[order(plan$time[rows])]
    labels <- if (length(plan$ids)) paste(paste(plan$ids,
      as.character(data[rows[1], plan$ids, drop = TRUE]), sep = "="), collapse = "; ") else "Series"
    y <- data$OBS_VALUE[rows]
    if (!any(is.finite(y))) {
      graphics::plot.new(); graphics::title(main = paste(labels, "(no finite values)"))
    } else {
      graphics::plot(plan$time[rows], y, type = "o", xlab = "Period", ylab = "OBS_VALUE",
                     main = paste(strwrap(labels, width = 100), collapse = "\n"), cex.main = 0.75, xaxt = "n")
      ticks <- unique(round(seq(1, length(rows), length.out = min(8, length(rows)))))
      graphics::axis(1, at = plan$time[rows[ticks]], labels = data$TIME_PERIOD[rows[ticks]])
    }
  }
}

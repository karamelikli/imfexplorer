# Run from the package/project directory. These checks never edit source files.
styler::style_pkg(dry = "fail")
styler::style_file("run-app.R", dry = "fail")
styler::style_dir("tools", dry = "fail")
lints <- lintr::lint_dir(show_progress = FALSE)
if (length(lints)) {
  print(lints)
  stop(length(lints), " lint findings remain.", call. = FALSE)
}
message("Formatting is stable; no lint findings.")

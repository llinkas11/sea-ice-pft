rf_project_root <- function() {
  root <- Sys.getenv("RF_PROJECT_ROOT", unset = "")
  if (!nzchar(root)) root <- getwd()
  root
}

rf_data_root <- function() {
  d <- Sys.getenv("RF_DATA_ROOT", unset = "")
  if (!nzchar(d)) d <- file.path(rf_project_root(), "data")
  d
}

rf_out_root <- function() {
  o <- Sys.getenv("RF_OUT_ROOT", unset = "")
  if (!nzchar(o)) o <- file.path(rf_data_root(), "out")
  o
}

rf_seed <- function() as.integer(Sys.getenv("RF_SEED", unset = "42"))

rf_n_threads <- function() {
  n <- Sys.getenv("SLURM_CPUS_ON_NODE", unset = "")
  if (!nzchar(n)) n <- Sys.getenv("RF_N_THREADS", unset = "")
  if (!nzchar(n)) return(max(1L, parallel::detectCores() - 1L))
  as.integer(n)
}

setup_rlibs <- function() {
  libdir <- Sys.getenv("R_LIBS_USER", unset = "")
  if (nzchar(libdir)) .libPaths(c(libdir, .libPaths()))
  invisible(.libPaths())
}

# R/tests/helper-db.R
# testthat automatically loads helper-*.R before running any tests, so
# the data functions are sourced here. When test_dir() runs, the working
# directory changes to the tests directory, hence the relative path
# ../fns/db.R.
source("../fns/db.R")

# R/tests/helper-db.R
# testthat 自动加载 helper-*.R，在所有测试前 source 数据函数
# test_dir() 执行时工作目录会切到测试文件所在目录，故用相对路径 ../fns/db.R
source("../fns/db.R")

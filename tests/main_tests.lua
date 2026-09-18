local timetableTests = require "tests.timetable_tests"
local timetableHelperTests = require "tests.timetable_helper_tests"
local opsTests = require "tests.ops_tests"
local lintTests = require "tests.lint_tests"


print("running timetable tests")
timetableTests.test()

print("running timetable helper tests")
timetableHelperTests.test()

print("running ops tests")
opsTests.test()

print("running lint tests")
lintTests.test()

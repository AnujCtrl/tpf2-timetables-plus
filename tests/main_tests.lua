local timetableTests = require "tests.timetable_tests"
local timetableHelperTests = require "tests.timetable_helper_tests"
local lintTests = require "tests.lint_tests"
local probeTests = require "tests.probe_tests"
local driverTests = require "tests.driver_tests"


print("running timetable tests")
timetableTests.test()

print("running timetable helper tests")
timetableHelperTests.test()


print("running lint tests")
lintTests.test()

print("running probe tests")
probeTests.test()

print("running driver tests")
driverTests.test()

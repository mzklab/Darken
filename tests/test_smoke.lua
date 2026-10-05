T.suite("the harness")

T.eq(1 + 1, 2, "arithmetic works")
T.ok(true, "a truth is true")
T.err(function() error("as expected") end, "err catches an error")

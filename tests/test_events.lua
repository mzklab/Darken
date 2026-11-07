local helpers = require("helpers")


T.suite("events: the door no longer times what it carries")

-- The subsystems were timed here for an evening, two readings of the clock
-- per handler, and the answer was the same every time: not one of them
-- spends a hundredth of a millisecond in a second of play. An answer that
-- settled does not need taking again on every event for the rest of the
-- addon's life.
--
-- What is checked is that the door still answers the question, with an
-- empty tally: a reading that loses a line it used to print looks like a
-- defect to whoever is reading it.
do
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Events.lua", ns)

    T.eq(type(ns.Events.Spent), "function", "the door still answers")
    T.eq(type(ns.Events.Spent()), "table", "with a tally")
    T.eq(next(ns.Events.Spent()), nil, "and the tally is empty")
end

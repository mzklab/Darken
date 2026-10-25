-- Runs every test: luajit tests/run.lua
-- Returns code 1 if at least one check failed.

package.path = "./?.lua;./tests/?.lua;" .. package.path

local passed, failed = 0, 0
local suite = "?"

T = {}

function T.suite(name)
    suite = name
end

local function fail(msg, detail)
    failed = failed + 1
    io.write(string.format("FAIL [%s] %s\n", suite, msg or ""))
    if detail then io.write(detail) end
end

function T.eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
    else
        fail(msg, string.format("  expected: %s\n  got:      %s\n",
            tostring(expected), tostring(actual)))
    end
end

function T.ok(value, msg)
    if value then
        passed = passed + 1
    else
        fail(msg, "  a true value was expected\n")
    end
end

-- A check that a call fails. Needed where the contract forbids an argument.
function T.err(fn, msg)
    local okCall = pcall(fn)
    if okCall then
        fail(msg, "  an error was expected but the call went through\n")
    else
        passed = passed + 1
    end
end

local files = {
    "tests/test_smoke.lua",
    "tests/test_compat.lua",
    "tests/test_realnames.lua",
    "tests/test_media.lua",
    "tests/test_registry.lua",
    "tests/test_api.lua",
    "tests/test_moduleapi.lua",
    "tests/test_apiversion.lua",
    "tests/test_frames.lua",
    "tests/test_defaults.lua",
    "tests/test_presets.lua",
    "tests/test_texture_rename.lua",
    "tests/test_scan.lua",
    "tests/test_command.lua",
    "tests/test_widgets.lua",
    "tests/test_schema.lua",
    "tests/test_window.lua",
    "tests/test_list.lua",
    "tests/test_profilepage.lua",
    "tests/test_skin.lua",
    "tests/test_locale.lua",
    "tests/test_locale_tables.lua",
    "tests/test_darkness.lua",
    "tests/test_darkcases.lua",
    "tests/test_icons.lua",
    "tests/test_launcher.lua",
    "tests/test_darksecret.lua",
    "tests/test_fonts.lua",
    "tests/test_combattext.lua",
    "tests/test_unitframes.lua",
    "tests/test_groupframes.lua",
    "tests/test_barcolor.lua",
    "tests/test_nameplates.lua",
    "tests/test_texts.lua",
    "tests/test_bags.lua",
    "tests/test_nameplatesmodule.lua",
    "tests/test_visibility.lua",
    "tests/test_itemlevel.lua",
    "tests/test_moduletoc.lua",
    "tests/test_auras.lua",
    "tests/test_infopanel.lua",
    "tests/test_infopanelcells.lua",
    "tests/test_darkcost.lua",
    "tests/test_dimexceptions.lua",
    "tests/test_darkwatch.lua",
    "tests/test_darkbefore.lua",
    "tests/test_frameknowledge.lua",
    "tests/test_settingsloss.lua",
    "tests/test_nameplates2.lua",
    "tests/test_nameplatesrules.lua",
    "tests/test_nameplateseditor.lua",
    "tests/test_aurasfilter.lua",
    "tests/test_aurasmouse.lua",
    "tests/test_aurascombat.lua",
    "tests/test_aurasrules.lua",
    "tests/test_aurafilter.lua",
    "tests/test_fontscope.lua",
    "tests/test_casefold.lua",
    "tests/test_darkdefault.lua",
    "tests/test_modulefamily.lua",
    "tests/test_moduleclose.lua",
    "tests/test_windowfont.lua",
    "tests/test_moduleadopt.lua",
    "tests/test_worldfamily.lua",
    "tests/test_contractformat.lua",
    "tests/test_formatadopt.lua",
    "tests/test_worldfixes.lua",
    "tests/test_formattail.lua",
    "tests/test_scaletail.lua",
    "tests/test_aurasunits.lua",
    "tests/test_compatauras.lua",
    "tests/test_bartint.lua",
    "tests/test_docs.lua",
    "tests/test_locale_rule.lua",
    "tests/test_coldboot.lua",
    "tests/test_buildall.lua",
    "tests/test_wholecost.lua",
    "tests/test_aurascost.lua",
    "tests/test_away.lua",
    "tests/test_durability.lua",
    "tests/test_contracttrap.lua",
    "tests/test_optionwords.lua",
    "tests/test_report.lua",
    "tests/test_reportstamp.lua",
    "tests/test_tally.lua",
    "tests/test_eventscore.lua",
    "tests/test_eventsrefused.lua",
    "tests/test_darkscale.lua",
    "tests/test_darklevel.lua",
    "tests/test_darkareas.lua",
    "tests/test_bagborders.lua",
    "tests/test_compatpaths.lua",
    "tests/test_containerpaths.lua",
    "tests/test_layernames.lua",

    -- Last and only last: it judges by what the whole set read
    -- (helpers.loaded). Placed earlier, it would go red on the files the
    -- checks below honestly read.
    "tests/test_moduleload.lua",
}

for _, f in ipairs(files) do
    local chunk, err = loadfile(f)
    if not chunk then
        fail("the test file did not load: " .. f, "  " .. tostring(err) .. "\n")
    else
        local okRun, runErr = pcall(chunk)
        if not okRun then
            fail("error while running " .. f, "  " .. tostring(runErr) .. "\n")
        end
    end
end

io.write(string.format("\npassed: %d, failed: %d\n", passed, failed))
os.exit(failed == 0 and 0 or 1)

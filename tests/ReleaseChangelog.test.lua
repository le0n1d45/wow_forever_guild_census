-- tools/release_changelog.py (used by the release workflows): runs the real script on temp files.
return function()
    local function python()
        local ok = os.execute("python3 --version > /dev/null 2>&1")
        return ok == 0 or ok == true
    end

    local function write(path, text)
        local f = assert(io.open(path, "w"))
        f:write(text)
        f:close()
    end

    local function read(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local text = f:read("*a")
        f:close()
        return text
    end

    local function run(changelog, version)
        local dir = os.tmpname()
        os.remove(dir)
        assert(os.execute("mkdir -p " .. dir))
        local log, notes = dir .. "/CHANGELOG.md", dir .. "/notes.md"
        write(log, changelog)
        local ok = os.execute(string.format("python3 tools/release_changelog.py %s %s %s 2026-11-11 > /dev/null 2>&1",
            log, version, notes))
        local result = { ok = ok == 0 or ok == true, notes = read(notes), changelog = read(log) }
        os.execute("rm -rf " .. dir)
        return result
    end

    local HEAD = "# Changelog\n\nIntro.\n\n"
    local OLD = "## [0.1.0] - 2026-01-01\n\n### Added\n- Old thing.\n"

    describe("release_changelog.py", function()
        if not python() then
            it("is skipped: python3 is not installed", function() end)
            return
        end

        it("uses the Unreleased entries as the notes and moves them under the new version", function()
            local r = run(HEAD .. "## [Unreleased]\n\n### Added\n- New thing.\n\n### Fixed\n- Bug.\n\n" .. OLD, "0.2.0")
            assertEqual(r.ok, true)
            assertEqual(r.notes, "### Added\n- New thing.\n\n### Fixed\n- Bug.\n")
            assertEqual(r.changelog, HEAD .. "## [Unreleased]\n\n## [0.2.0] - 2026-11-11\n\n### Added\n- New thing.\n\n### Fixed\n- Bug.\n\n" .. OLD)
        end)

        it("keeps multi-line entries together", function()
            local r = run(HEAD .. "## [Unreleased]\n\n### Added\n- One\n  continued.\n\n" .. OLD, "0.2.0")
            assertEqual(r.notes, "### Added\n- One\n  continued.\n")
        end)

        it("falls back to a version heading written ahead of time, leaving the file alone", function()
            local text = HEAD .. "## [Unreleased]\n\n## [0.2.0] - 2026-11-10\n\n### Added\n- Early.\n\n" .. OLD
            local r = run(text, "0.2.0")
            assertEqual(r.ok, true)
            assertEqual(r.notes, "### Added\n- Early.\n")
            assertEqual(r.changelog, text)
        end)

        it("fails, writing no notes, when there is nothing to release", function()
            local r = run(HEAD .. "## [Unreleased]\n\n" .. OLD, "0.2.0")
            assertEqual(r.ok, false)
            assertEqual(r.notes, nil)
        end)
    end)
end

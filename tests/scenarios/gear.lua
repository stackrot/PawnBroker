-- Equipped items Pawn reads late, or never.
UNREADABLE[11] = 3
pb("") run()
assert(not NS.ui.notes.text:find("couldn't read"))
UNREADABLE[11] = 1000
pb("") run()
assert(NS.ui.notes.text:find("Ancient Heirloom"), NS.ui.notes.text)

-- A loaded item without stats scores 0 straight away.
UNREADABLE[11] = 0
STATLESS[11] = true
local start = clock()
pb("") run()
assert(clock() - start < 1, "plan waited " .. (clock() - start) .. "s")
assert(not NS.ui.notes.text:find("couldn't read"), NS.ui.notes.text)

-- Item data loads while the gear is still being read, so the plan waits
-- for whichever is slower, not both one after the other.
STATLESS[11] = nil
UNREADABLE[11] = 10
local at = clock() + 1
for id in pairs(MOCK) do LOADING[id] = at end
start = clock()
pb("") run()
assert(clock() - start < 1.5, "plan took " .. (clock() - start) .. "s")
assert(not NS.ui.notes.text:find("didn't load"), NS.ui.notes.text)
assert(not NS.ui.notes.text:find("couldn't read"), NS.ui.notes.text)
LOADING = {}

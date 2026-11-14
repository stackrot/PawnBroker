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

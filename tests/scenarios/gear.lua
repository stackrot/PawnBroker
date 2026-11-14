-- Equipped items Pawn reads late, or never.
UNREADABLE[11] = 3
pb("") run()
assert(not NS.ui.notes.text:find("couldn't read"))
UNREADABLE[11] = 1000
pb("") run()
assert(NS.ui.notes.text:find("Ancient Heirloom"), NS.ui.notes.text)

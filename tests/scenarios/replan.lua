-- A new budget or the Net cost box re-plans from the last run's scores at
-- once; the Plan button, new gear or Levels above score everything again.
NS.ui.budget:SetText("") NS.ui.ahead:SetText("")
pb("") run()
local full = TOOLTIPS
assert(full > 0)
local header = NS.ui.header.text

NS.ui.budget:SetText("all")
NS.ui.budget.scripts.OnEnterPressed(NS.ui.budget)
assert(TOOLTIPS == full, "the budget scored everything again")
assert(NS.ui.header.text ~= header, NS.ui.header.text)
assert(NS.ui.status.text == "Plan ready.", NS.ui.status.text)

NS.ui.net:SetChecked(true)
NS.ui.net.scripts.OnClick(NS.ui.net)
assert(TOOLTIPS == full, "net cost scored everything again")
assert(NS.ui.header.text:find("net budget") or NS.ui.header.text:find("net"),
	NS.ui.header.text)

-- The Plan button always scores again.
NS.ui.planButton.scripts.OnClick(NS.ui.planButton)
run()
assert(TOOLTIPS > full, "the Plan button reused the last run")

-- So does a change in Levels above, even from the budget box.
local before = TOOLTIPS
NS.ui.ahead:SetText("2")
NS.ui.budget.scripts.OnEnterPressed(NS.ui.budget)
run()
assert(TOOLTIPS > before, "Levels above reused the last run")

-- And a stale run.
before = TOOLTIPS
advanceClock(300)
NS.ui.budget.scripts.OnEnterPressed(NS.ui.budget)
run()
assert(TOOLTIPS > before, "a five-minute-old run was reused")

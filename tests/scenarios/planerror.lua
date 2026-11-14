-- If loading item data throws, the planner doesn't stay busy: the error
-- goes to the error handler and the next /pb plans as normal.
local errors = {}
geterrorhandler = function()
	return function(e) errors[#errors + 1] = tostring(e) end
end
local cached = C_Item.IsItemDataCachedByID
C_Item.IsItemDataCachedByID = function() return false end
Item = { CreateFromItemID = function() error("no item mixin") end }
pb("") run()
assert(#errors > 0 and errors[1]:find("no item mixin"), "error not reported")
C_Item.IsItemDataCachedByID = cached
pb("") run()
assert(NS.ui.status.text == "Plan ready.", NS.ui.status.text)

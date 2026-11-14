local _, ns = ...

SLASH_PAWNBROKER1 = "/pb"
SLASH_PAWNBROKER2 = "/pawnbroker"
SlashCmdList.PAWNBROKER = function(msg)
	msg = strtrim(msg or "")
	local word = msg:lower()
	if word ~= "scan" and word ~= "stop" then
		return ns.ui:PlanFrom(msg)
	end
	ns.ui:Show()
	ns.ui:Refresh()
	if word == "scan" then
		ns.scan()
	else
		ns.stopScan()
	end
end

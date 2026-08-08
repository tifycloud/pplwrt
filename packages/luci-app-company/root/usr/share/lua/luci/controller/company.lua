module("luci.controller.company", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/company") then return end
	entry({"admin", "company"}, template("company/dashboard"), _("CompanyWrt"), 5).dependent = false
end

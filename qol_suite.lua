-- Resolve bundled features through the suite's explicit compatibility API.
-- Standalone discovery remains the host's responsibility.
local M={}
function M.install(mod)
  local original=mod.find
  mod.find=function(first,second)
    local id=second or first
    local found=original(id)
    if found then return found end
    local suite=original('frlg-qol-suite')
    return suite and suite.exports and suite.exports.find and suite.exports.find(id) or nil
  end
end
return M

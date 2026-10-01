-- Visibility is independent of placement: toggling a tile preserves its position.
local M={}
function M.new(display,mod)
 local function defaults()
  local result={}
  for id,hidden in pairs(display.homeDefaults and display.homeDefaults.hidden or {})do result[id]=hidden end
  return result
 end
 local self={hidden=mod.save:get('home_hidden_tiles') or defaults()}
 function self:load(saved)
  self.hidden=type(saved)=='table' and saved or mod.save:get('home_hidden_tiles') or defaults()
 end
 function self:reset()
  self.hidden=defaults()
  mod.save:set('home_hidden_tiles',self.hidden)
 end
 for old,ids in pairs({portable_rods={'portable_old_rod','portable_good_rod','portable_super_rod'},portable_bike={'portable_bike_use','portable_bike_swap'}})do
  if self.hidden[old] then for _,id in ipairs(ids)do self.hidden[id]=true end;self.hidden[old]=nil end
 end
 function self:ensure(id)
  local H,home,catalog=display.Home,display.home,display.homeCatalog
  if H.find(home.layout,id) then return true end
  for page=1,H.pageCount(home.layout)+1 do
   for row=1,H.rows do for col=1,12 do
    if H.place(home.layout,catalog,id,page,col,row) then display.saveHome();return true end
   end end
  end
  return false
 end
 function self:visible(id)return id=='settings_app' or self.hidden[id]~=true end
 function self:set(id,enabled)
  if id=='settings_app' then return false end
  if not display.homeCatalog.surfaces[id] then return false end
  if enabled and not self:ensure(id) then return false end
  self.hidden[id]=not enabled or nil
  mod.save:set('home_hidden_tiles',self.hidden)
  display.saveHome()
  return true
 end
 function self:rows()
  local rows={}
  local hasPanel={}
  for _,surface in pairs(display.homeCatalog.surfaces)do
   if surface.kind=='widget' then hasPanel[surface.package]=true end
  end
  for id,surface in pairs(display.homeCatalog.surfaces)do
   local package=display.homeCatalog.packages[surface.package]
   if package and package.installed~=false then
    local placed=display.Home.find(display.home.layout,id)~=nil
    local label=surface.label or id
    if surface.kind=='widget' then
     label=label..((surface.columns or 3)>3 and ' PANEL' or ' TILE')
    elseif hasPanel[surface.package] then label=label..' SHORTCUT' end
    rows[#rows+1]={tileId=id,label=label,
     value=id=='settings_app' and 'ALWAYS ON' or (placed and self:visible(id) and 'ON' or 'OFF'),
     enabled=id~='settings_app'}
   end
  end
  table.sort(rows,function(a,b)
   if a.label==b.label then return a.tileId<b.tileId end
   return a.label<b.label
  end)
  return rows
 end
 return self
end
return M

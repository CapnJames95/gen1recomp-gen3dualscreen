-- Home shortcuts use the same app tile renderer and the native Start actions.
local HomeMods={};HomeMods.__index=HomeMods
local definitions={
 {id='frlg_qol_hoenn_tools',label='HOENN TOOLS',icon='map',accent='green',export=true},
 {id='fly-teleport',label='TELEPORT',icon='map',accent='blue'},
 {id='quick-heal-party',label='QUICK HEAL',icon='party',accent='green'},
 {id='capture-assistant',label='CAPTURE HELP',icon='pokedex',accent='amber'},
 {id='pokemon-services',label='SERVICES',icon='store',accent='blue'},
 {id='legalmon',label='LEGALMON',icon='pokedex',accent='blue'},
 {id='event-distributor',label='EVENT DIST.',icon='store',accent='red'},
 {id='shiny_hunter',label='SHINY HUNTER',icon='achievements',accent='amber'},
 {id='autobreeder',label='AUTO BREEDER',icon='party',accent='green'},
 {id='encounter_tour',label='ENCOUNTER TOUR',icon='map',accent='blue'},
 {id='daycare-viewer',label='DAY CARE',icon='party',accent='green'},
 {id='encounter_reset',label='ENCOUNTER RESET',icon='explorer',accent='red'},
}
function HomeMods.new(display,mod)
 local self=setmetatable({display=display,mod=mod,definitions=definitions,byId={}},HomeMods)
 for _,def in ipairs(definitions)do
  local id='mod_'..def.id;self.byId[id]=def
  display.homeCatalog.packages[id]={installed=false,available=false,fixed=true}
  display.homeCatalog.surfaces[id..'_app']={package=id,kind='app',columns=3,
   icon=def.icon,accent=def.accent,label=def.label}
  local app={id=id,label=def.label,icon=def.icon,category='MOD TOOLS',fixed=true,
   hidden=true,available=false,description={'OPEN '..def.label..'.','USES THE INSTALLED MOD.','NATIVE CONFIRMATIONS ARE KEPT.'}}
  display.storeCatalog[#display.storeCatalog+1]=app;display.storeById[id]=app
 end
 -- Run outside the tool hooks so filtering happens after they add their rows.
 mod.hooks:wrap('ui.start_menu.items',function(next,game,items)
  local result=next(game,items)
  if self.launching or not mod.find('frlg_dual_screen') or not game
    or game.generation~=3 or type(result)~='table' then return result end
  local visible={}
  for _,row in ipairs(result)do
   if not self.byId['mod_'..tostring(row.id)] then visible[#visible+1]=row end
  end
  return visible
 end,10000)
 return self
end
function HomeMods:refresh(layout,ensure)
 local d=self.display;local changed=false
 for _,def in ipairs(definitions)do
  local id='mod_'..def.id;local package=d.homeCatalog.packages[id]
  local present=self.mod.find(def.id)~=nil;local was=package.installed
  package.available,package.installed=present,present
  d.storeById[id].available=present;d.storeById[id].hidden=not present
  changed=changed or was~=present
  if present and layout and (ensure or not was) and not d.Home.find(layout,id..'_app') then
   local placed=false
   -- Fill free Home slots without moving existing user tiles.
   for page=1,d.Home.pageCount(layout)+1 do
    for row=1,d.Home.rows do for column=1,10 do
     if not placed then placed=d.Home.place(layout,d.homeCatalog,id..'_app',page,column,row) end
    end end
    if placed then break end
   end
  end
 end
 if changed and d.home then d.home.widgetCache=nil end
 return changed
end
function HomeMods:open(id)
 local def=self.byId[id];if not def or not self.mod.find(def.id) then return false end
 local d=self.display;local game=d.sourceGame;local bridge=d.modPanels
 local Stack=require('src.ui.game3.stack');local Player=require('src.core.game3.player')
 if not game or not game.session or not bridge:fieldIdle() or Player.moving or Stack.busy()
   or (game.speedLocked and game:speedLocked()) then return false end
 if def.export then
  local tool=self.mod.find(def.id)
  return tool and tool.exports and tool.exports.show and tool.exports.show(game)==true or false
 end
 local Start=require('src.ui.game3.start_menu');local cursor=Start.cursor
 -- Resolve a fresh native action for this tile without exposing it in Start.
 self.launching=true
 local ok,err=pcall(Start.show,{game=game,session=game.session})
 self.launching=false
 if not ok then
  Start.close(true);Start.cursor=cursor
  self.mod.log:error('Home shortcut failed: %s',tostring(err));return false
 end
 local opened=false
 for index,row in ipairs(Start.ENTRIES)do
  if row.id==def.id and type(row.onSelect)=='function' then
   Start.cursor=index;Start.confirm();opened=Stack.top() and Stack.top().id==def.id;break
  end
 end
 Start.close(true);Start.cursor=cursor
 return opened==true
end
return HomeMods

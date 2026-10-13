-- Targeted local encounters. Listing is read-only; activation revalidates the
-- current session/map/method, then delegates generation and capture to the active game.
local Route={};Route.__index=Route
local pools={
 {key='land',label='WALK',weights={20,20,10,10,10,10,5,5,4,4,1,1}},
 {key='water',label='SURF',weights={60,30,5,4,1}},
 {key='fishing',label='OLD ROD',first=1,rod=262,weights={70,30}},
 {key='fishing',label='GOOD ROD',first=3,rod=263,weights={60,20,20}},
 {key='fishing',label='SUPER ROD',first=6,rod=264,weights={40,40,15,4,1}},
 {key='rocks',label='ROCK SMASH',weights={60,30,5,4,1}},
}
function Route.new(env)
 return setmetatable({env=env,scope='here',filter='uncaught',page=1,message='',revision=0},Route)
end
function Route:rows(scope)
 local e=self.env;local s,map=e.session(),e.map()
 if not s or not map then return {} end
 local tables=e.tables(map) or {};local rows={}
 for _,pool in ipairs(pools) do
  local area=tables[pool.key] or (pool.key=='land' and tables.grass)
  local slots=area and (area.slots or area.mons or area)
  if slots and (pool.rod or (tonumber(area.rate) or 0)>0) then
   local available,why=e.method(pool,scope or self.scope)
   local groups={}
   for i,weight in ipairs(pool.weights) do
    local slot=slots[(pool.first or 1)+i-1]
    local species=slot and tonumber(slot.species or slot[1])
    if species and species>0 and e.name(species) then
     local lo=tonumber(slot.minLevel or slot.level or slot[2])
     local hi=tonumber(slot.maxLevel or slot.level or slot[2]) or lo
     if lo and hi and lo>=1 and hi<=100 then
      if hi<lo then lo,hi=hi,lo end
      local row=groups[species]
      if not row then
       local caught,seen=e.caught(s,species),e.seen(s,species)
       row={species=species,name=e.name(species),method=pool.label,key=pool.label..':'..species,
        caught=caught,seen=seen,status=caught and 'CAUGHT' or seen and 'SEEN' or 'NEW',
        available=available==true,reason=why,chance=0,lo=lo,hi=hi,slots={},map=map,session=s}
       groups[species]=row;rows[#rows+1]=row
      end
      row.lo,row.hi=math.min(row.lo,lo),math.max(row.hi,hi)
      row.chance=row.chance+weight
      row.slots[#row.slots+1]={lo=lo,hi=hi,item=slot.item,weight=weight}
     end
    end
   end
  end
 end
 table.sort(rows,function(a,b)
  if a.available~=b.available then return a.available end
  if a.caught~=b.caught then return not a.caught end
  if a.species~=b.species then return a.species<b.species end
  return a.method<b.method
 end)
 return rows
end
function Route:visibleRows()
 local rows={}
 for _,row in ipairs(self:rows())do
  if self.filter=='all' or (self.filter=='caught' and row.caught) or (self.filter~='caught' and self.filter~='all' and not row.caught)then
   rows[#rows+1]=row
  end
 end
 return rows
end
function Route:cycleFilter()
 self.filter=({uncaught='all',all='caught',caught='uncaught'})[self.filter] or 'uncaught'
 self.page=1;self.message='';self.drawnRows=nil
end
function Route:start(row,scope)
 local e=self.env
 if not row then self.message='No uncaught Pokemon available.';return false end
 local ready,why=e.ready()
 if not ready then self.message=why or 'Finish the current action first.';return false end
 if row.session~=e.session() or row.map~=e.map() then self.message='Area changed. Choose again.';return false end
 local live
 for _,r in ipairs(self:rows(scope)) do if r.key==row.key then live=r;break end end
 if not live or not live.available then self.message=live and live.reason or 'Encounter no longer available.';return false end
 -- Preserve slot-weighted level bands, including disjoint levels for one species.
 local roll=e.random(live.chance);local slot=live.slots[#live.slots]
 for _,candidate in ipairs(live.slots) do roll=roll-candidate.weight;if roll<0 then slot=candidate;break end end
 local level=slot.lo+e.random(slot.hi-slot.lo+1)
 local ok,err=e.start({species=live.species,level=level,item=slot.item})
 self.message=ok and ('Encountering '..live.name..'!') or tostring(err or 'Battle could not start.')
 return not not ok
end
function Route:uncaught(scope)
 local ready,why=self.env.ready()
 if not ready then self.message=why;return false end
 local any=false
 for _,row in ipairs(self:rows(scope)) do
  if row.available then any=true;if not row.caught then return self:start(row,scope) end end
 end
 self.message=any and 'All accessible Pokemon are caught.' or 'No accessible encounters. Try ROUTE.';return false
end
function Route.native(mod,getGame)
 local E=require('src.core.game3.encounters');local P=require('src.core.game3.pokemon')
 local Player=require('src.core.game3.player');local Map=require('src.core.game3.map')
 local Runtime=require('src.core.game3.runtime');local Dex=require('src.core.game3.dex')
 local Field=require('src.core.game3.field');local Space=require('src.core.game3.scripting.space')
 local Moves=require('src.core.game3.field_moves');local Bag=require('src.core.game3.bag')
 local function session() local g=getGame();return g and g.session end
 local function method(pool,scope)
  local s=session();if not s then return false,'Load a game first.' end
  if pool.rod then
   if not Bag.has(s.bag,pool.rod,1) then return false,'Need '..pool.label..'.' end
   if scope=='route' or require('src.core.game3.item_use').canFish() then return true end
   return false,'Face fishable water.'
  end
  if pool.key=='water' or pool.key=='rocks' then
   local move=pool.key=='water' and 'SURF' or 'ROCK_SMASH'
   if not Moves.partyMoveUser(s.party or {},move) or not Moves.hasBadge(Space.store or s,move) then
    return false,'Need '..pool.label..' and its badge.'
   end
   if scope=='route' then return true end
   if pool.key=='rocks' then return false,'Use ROUTE view for Rock Smash.' end
   return Player.surfing and E.terrainAt(Player.cellX,Player.cellY)=='water','Surf on encounter water.'
  end
  return scope=='route' or (not Player.surfing and E.terrainAt(Player.cellX,Player.cellY)=='land'), 'Stand in grass or a cave encounter tile.'
 end
 return Route.new({safariLabel=function() local tool=mod.find('frlg_qol_safari_tools');return tool and tool.exports and tool.exports.counterLabel and tool.exports.counterLabel() end,shinyShortcut=function()local m=mod.find('shiny_hunter');return m and m.exports and type(m.exports.prepareDualScreenEncounter)=='function' end,session=session,map=function()return Map.current or (session() or {}).map end,
  tables=E.tableFor,method=method,name=P.name,
  caught=function(s,id)return Dex.isCaught(s.dex or {},id)end,
  seen=function(s,id)return Dex.isSeen(s.dex or {},id)end,
  random=function(n)return require('src.core.game3.rng').Random()%n end,
  ready=function()
   local g,s=getGame(),session()
   if not g or g.generation~=3 or g.phase~='field' or not s or Runtime.getSession()~=s then return false,'Load a Gen 3 field.' end
   if g.speedLocked and g:speedLocked() then return false,'Unavailable in linked play.' end
   local Link=package.loaded['src.core.game3.link']
   if Link and Link.inLinkRoom and Link.inLinkRoom() then return false,'Leave the link room first.' end
   if require('src.core.game3.safari').isActive(s) then
    local safari=s.safari or {}
    if (tonumber(safari.balls) or 0)<=0 then return false,'No Safari Balls remain.' end
    if (tonumber(safari.steps) or 0)<=0 then return false,'The Safari game has ended.' end
   end
   if require('src.core.game3.battle').isActive() or require('src.core.game3.battle_transition').isActive()
    or require('src.ui.game3.stack').busy() or require('src.ui.game3.message').isOpen()
    or require('src.ui.game3.choice').active or require('src.ui.game3.fade').isActive()
    or require('src.core.game3.warp').isBusy() or Field.locked or Player.moving or Field.isFishing()
    or E._pendingWild or (Space.vm and Space.vm:isRunning()) or (Space._immediateVm and Space._immediateVm:isRunning()) then
    return false,'Finish movement, dialogue or the current action.'
   end
   for _,id in ipairs({'shiny_hunter','encounter_tour'}) do
    local other=mod.find(id);local busy=other and other.exports and other.exports.dualScreenBusy
    if other and not busy then return false,'Update '..id:gsub('_',' ')..' for encounter controls.' end
    if busy and busy() then return false,'Pause '..id:gsub('_',' ')..' first.' end
   end
   for _,mon in ipairs(s.party or {}) do if not P.isEgg(mon) and (mon.hp or 0)>0 then return true end end
   return false,'A healthy party Pokemon is required.'
  end,
  start=function(enc)
   local hunter=mod.find('shiny_hunter')
   local prepare=hunter and hunter.exports and hunter.exports.prepareDualScreenEncounter
   if type(prepare)=='function' then
    local game=getGame();local input=game and game.input
    local held=input and input.isDown and input:isDown('l') or false
    enc=prepare(enc,held)
   end
   -- Explicitly retain Safari rules, including native Ball/bait/flee controls
   -- and counter writeback; never turn a Safari encounter into a normal battle.
   local safari=require('src.core.game3.safari').isActive(session())
   return require('src.core.game3.battle_bridge').startWild(Runtime._mod,getGame(),enc,{safari=safari or nil})
  end,
 })
end
function Route:draw(H)
 local G=love.graphics;local rows=self:visibleRows();self.drawnRows=rows
 local pageCount=math.max(1,math.ceil(#rows/6));self.page=math.min(self.page,pageCount)
 H:label('< HOME',5,4,H.colors.blue,48);local title='WILD POKEMON'
 local session=self.env.session()
 if session and require('src.core.game3.safari').isActive(session) then
  local sf=session.safari or {};title=(self.env.safariLabel and self.env.safariLabel()) or ('SAFARI B:'..tostring(sf.balls or 0)..' S:'..tostring(sf.steps or 0))
 end
 H:label(title,64,4,H.colors.ink,172)
 H:button(4,23,112,24,'HERE',self.scope=='here');H:button(124,23,112,24,'ROUTE',self.scope=='route')
 local P=require('src.core.game3.pokemon')
 for slot=1,6 do
  local row=rows[(self.page-1)*6+slot]
  if row then
   local x=4+((slot-1)%3)*79;local y=51+math.floor((slot-1)/3)* 60
   H:panel(x,y,75,60,false,nil,nil,row.caught and H.colors.green or H.colors.blue)
   local pic=P.frontPic(row.species,0,false)
   if pic and pic.image then
    G.setColor(row.available and 1 or 0.5,row.available and 1 or 0.5,row.available and 1 or 0.5,1)
    G.draw(pic.image,x+3,y+1,0,0.48,0.48)
   end
   H:label(row.status,x+35,y+3,row.caught and H.colors.green or H.colors.ink,39)
   H:label('L'..row.lo..'-'..row.hi,x+35,y+16,H.colors.mutedInk,39)
   H:label(row.name,x+3,y+34,H.colors.ink,69)
   H:label(row.method,x+3,y+46,row.available and H.colors.blue or H.colors.mutedInk,69)
  end
 end
 if #rows==0 then H:label('No '..self.filter..' encounters in this area.',8,80,H.colors.mutedInk,224) end
 H:label(self.message~='' and self.message or (self.env.shinyShortcut and self.env.shinyShortcut() and 'Tap to encounter; hold L for shiny.' or 'Tap a sprite to start a battle.'),5,174,H.colors.ink,230)
 H:button(4,190,40,22,'<',false)
 H:button(48,190,144,22,'ENCOUNTERS: '..self.filter:upper(),false)
 H:button(196,190,40,22,'>',false)
end
function Route:tap(x,y)
 if y<20 and x<55 then self.open=false;return end
 if y>=23 and y<47 then self.scope=x<120 and 'here' or 'route';self.page=1;self.message='';self.drawnRows=nil;return end
 local rows=self.drawnRows or self:visibleRows()
 if y>=190 then
  if x>=48 and x<192 then self:cycleFilter()
  else self.page=((self.page-1+(x<48 and -1 or 1))%math.max(1,math.ceil(#rows/6)))+1 end
 elseif y>=51 and y<171 and x>=4 and x<237 then
  local slot=math.floor((y-51)/60)*3+math.floor((x-4)/79)+1
  self:start(rows[(self.page-1)*6+slot],self.scope)
 end
end
return Route

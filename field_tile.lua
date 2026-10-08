-- Contextual shortcuts into native Party/Bag menus; never grant field access.
local FieldTile={};FieldTile.__index=FieldTile
local order={'WATERFALL','CUT','SURF','FISH','ROCK_SMASH','STRENGTH','FLASH','DIG','TELEPORT','SWEET_SCENT'}
local labels={ROCK_SMASH='SMASH',SWEET_SCENT='SCENT'}
function FieldTile.new(mod,bridge)
 local self=setmetatable({mod=mod,bridge=bridge,cursor=1},FieldTile)
 self.actions=assert(load(mod:read("field_actions.lua"),"@frlg_dual_screen/field_actions.lua"))()
 self.actions.installFishingText()
 self.FM=require('src.core.game3.field_moves');self.Stack=require('src.ui.game3.stack')
 self.screen={draw=function()self:draw(bridge.theme)end,handleInput=function(input)
  if input:wasPressed('b') then self:close()
  elseif input:wasPressed('up') then self.cursor=math.max(1,self.cursor-1)
  elseif input:wasPressed('down') then self.cursor=math.min(#self:menuRows(),self.cursor+1)
  elseif input:wasPressed('a') then local row=self:menuRows()[self.cursor];if row then self:activate(row.id) end end
 end}
 mod.events:on('game.ready',function()self:close()end)
 return self
end
function FieldTile:visible()return self.Stack.top() and self.Stack.top().id=='frlg_field_tile'end
function FieldTile:close()self.Stack.pop('frlg_field_tile');self.mode=nil;self.notice=nil end
function FieldTile:idle()
 local g=self.bridge.getGame()
 return g and g.generation==3 and g.phase=='field' and g.session==require('src.core.game3.runtime').getSession()
  and not require('src.mods.Gen3Compat').worldBusy()
end
function FieldTile:context()
 local g=self.bridge.getGame()
 return self.actions.context(g and g.session)
end
function FieldTile:rods(ctx)
 local Bag=require('src.core.game3.bag');local Items=require('src.core.game3.items_data');local rows={}
 for _,name in ipairs({'OLD_ROD','GOOD_ROD','SUPER_ROD'})do
  local id=Items.toNumericId(name)
  if id and Bag.get(ctx.session.bag,id)>0 then rows[#rows+1]={id='rod:'..id,item=id,label=name:gsub('_',' '),enabled=true} end
 end
 return rows
end
function FieldTile:query(id,ctx)
 local row={id=id,label=labels[id] or id:gsub('_',' '),enabled=false}
 if not ctx then row.reason='No active game.';return row end
 if id=='FISH' or id:match('^rod:') then
  local rods=self:rods(ctx);local owned=id=='FISH' and #rods>0
  for _,rod in ipairs(rods)do if rod.id==id then owned=true;row.item=rod.item;row.label=rod.label end end
  row.enabled=owned and require('src.core.game3.item_use').canFish()
  row.reason=not owned and 'Obtain a fishing rod first.' or 'Face fishable water.'
  return row
 end
 local mon,slot=self.FM.partyMoveUser(ctx.party,id)
 if not mon then row.reason='A party Pokemon must know '..id:gsub('_',' ')..'.';return row end
 ctx.mon=mon
 local res=self.FM.fromMenu(id,ctx)
 row.enabled=res and res.ok==true and self.actions.allowed(id,ctx);row.slot=slot+1
 row.reason=res and res.badge and 'Earn the required badge first.' or 'This move cannot be used here.'
 return row
end
function FieldTile:model()
 local ctx=self:context();local rows={self:query('FLY',ctx)}
 if not ctx then return rows end
 local gfx=ctx.facingObject and (ctx.facingObject.gfx or ctx.facingObject.graphicsId)
 local candidates={CUT=gfx==self.FM.GFX_IDS.CUT_TREE or (ctx.hasCuttableGrass and not ctx.isFacingWater),
  SURF=ctx.isFacingWater and not ctx.isSurfing,FISH=ctx.isFacingWater and not ctx.isFacingWaterfall,
  ROCK_SMASH=gfx==self.FM.GFX_IDS.ROCK_SMASH_ROCK,STRENGTH=gfx==self.FM.GFX_IDS.PUSHABLE_BOULDER,
  WATERFALL=ctx.isFacingWaterfall,FLASH=ctx.isCave,DIG=ctx.canEscapeRope,
  TELEPORT=self.FM.isOutdoors(ctx.mapType),SWEET_SCENT=ctx.hasCuttableGrass or ctx.isSurfing}
 for _,id in ipairs(order)do
  if candidates[id] then
   local row=self:query(id,ctx)
   -- Always explain an obstacle; optional travel/encounter shortcuts require the move.
   if id~='TELEPORT' and id~='SWEET_SCENT' or row.enabled then rows[#rows+1]=row end
  end
 end
 local idle=self:idle() or self:visible()
 for _,row in ipairs(rows)do row.enabled=row.enabled and idle end
 return rows
end
-- Feed the legacy Tools page/widgets from the same live native eligibility.
function FieldTile:tools(existing)
 local rows,handled={},{}
 local ctx=self:context()
 for _,id in ipairs(order)do
  handled[id:lower()]=true
  local row=self:query(id,ctx)
  if row.enabled then
   local action={id=id:lower(),label=id:gsub('_',' ')}
   if id=='FISH' then
    action.rods={}
    for _,rod in ipairs(self:rods(ctx))do
     action.rods[#action.rods+1]={id=rod.label:gsub(' ','_'),label=rod.label}
    end
   end
   rows[#rows+1]=action
  end
 end
 for _,row in ipairs(existing or {})do if not handled[row.id] then rows[#rows+1]=row end end
 return rows
end
function FieldTile:sections()
 local rows=self:model()
 return {rows[1],rows[2] or {id='MORE',label='ACTIONS',enabled=true},
  #rows>3 and {id='MORE',label='MORE',enabled=true} or rows[3] or {id='NONE',label='--',enabled=false}}
end
function FieldTile:menuRows()
 if self.mode=='rods' then
  local ctx=self:context();local rows=ctx and self:rods(ctx) or {}
  for i,row in ipairs(rows)do rows[i]=self:query(row.id,ctx) end
  return rows
 end
 return self:model()
end
function FieldTile:show(mode,notice)
 if not self:visible() and not self:idle() then return false end
 self.mode,self.notice,self.cursor=mode,notice,1
 if not self:visible() then self.Stack.push('frlg_field_tile',self.screen,{fullscreen=true}) end
 if mode=='rods' then
  local last=self.mod.save:get('field_rod')
  for i,row in ipairs(self:menuRows())do if row.item==last then self.cursor=i end end
 end
 return true
end
function FieldTile:activate(id)
 if id=='NONE' then return false end
 if id=='MORE' then return self:show('actions') end
 local row=self:query(id,self:context())
 if not row.enabled then return self:show('actions',row.reason) end
 if id=='FISH' then return self:show('rods') end
 self:close()
 if not self:idle() then return false end
 row=self:query(id,self:context());if not row.enabled then return false end
 local session=self.bridge.getGame().session
 local ok=self.actions.execute(session,id,row)
 if ok and row.item then self.mod.save:set('field_rod',row.item) end
 return ok
end

function FieldTile:tap(x,y)
 if y<28 and x<55 then self:close();return end
 local rows=self:menuRows();local first=math.floor((self.cursor-1)/4)*4+1
 if y>=38 and y<178 then local n=first+math.floor((y-38)/35)
  if rows[n] then self.cursor=n;self:activate(rows[n].id) end
 elseif y>=186 then self.cursor=math.max(1,math.min(#rows,self.cursor+(x<120 and -4 or 4))) end
end
function FieldTile:draw(H)
 H:panel(5,3,230,25,false);H:label('< BACK',10,10,H.colors.blue,45)
 H:label(self.mode=='rods' and 'CHOOSE A ROD' or 'FIELD ACTIONS',65,10,H.colors.ink,165)
 local rows=self:menuRows();self.cursor=math.max(1,math.min(#rows,self.cursor))
 local first=math.floor((self.cursor-1)/4)*4+1
 for i=first,math.min(#rows,first+3)do local row=rows[i];local y=38+(i-first)*35
  H:panel(6,y,228,31,i==self.cursor,H.colors.blue)
  H:label(row.label,14,y+5,row.enabled and H.colors.ink or H.colors.mutedInk,210)
  H:partyInfo(row.enabled and 'OPEN NATIVE ACTION' or H:fitPartyInfo(row.reason or 'Unavailable',208),14,y+19,H.colors.mutedInk,208)
 end
 H:partyInfo(H:fitPartyInfo(self.notice or 'SELECT AN ACTION.  < / > MORE',224),8,200,H.colors.ink,224,'center')
end
return FieldTile

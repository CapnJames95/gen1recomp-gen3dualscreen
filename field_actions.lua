-- Native field-menu bridge for companion shortcuts.
local Actions={}
local function press(menu,key)
 menu.handleInput({wasPressed=function(_,k)return k==key end,isDown=function()return false end})
end
function Actions.context(session)
 local FM=require("src.core.game3.field_moves")
 local P=require('src.core.game3.player');local C=require('src.core.game3.collision')
 local Map=require('src.core.game3.map');local S=require('src.core.game3.scripting.space')
 if not session or type(P.cellX)~='number' or type(P.cellY)~='number' then return nil end
 local d=({up={0,-1},down={0,1},left={-1,0},right={1,0}})[P.facing or 'down']
 local x,y=P.cellX+d[1],P.cellY+d[2];local map=Map.currentDef() or {}
 local grass=false
 for gy=P.cellY-1,P.cellY+1 do for gx=P.cellX-1,P.cellX+1 do
  local elev=C.elevationAt and C.elevationAt(gx,gy)
  if (P.elevation==nil or elev==P.elevation) and C.isGrass and C.isGrass(gx,gy) then grass=true end
 end end
 return {party=session.party,session=session,store=S.store,facingObject=require('src.core.game3.objects').at(x,y),
  isFacingWater=C.isWater(x,y),isFacingWaterfall=FM.isWaterfallBehavior(C.behavior(x,y)),
  facing=P.facing,isSurfing=P.surfing==true,hasCuttableGrass=grass,mapType=map.mapType,
  flashLevel=require("src.core.game3.field_view").getFlashLevel(),
  isCave=(tonumber(map.cave) or 0)~=0,canEscapeRope=(tonumber(map.allowEscaping) or 0)~=0,
  escapeWarp=session.escapeWarp}
end
-- Shortcut eligibility is narrower than the native party Strength menu.
function Actions.allowed(id,ctx)
 if id=='FLASH' then return (tonumber(ctx and ctx.flashLevel) or 0)>0 end
 if id~='STRENGTH' then return true end
 local FM=require('src.core.game3.field_moves')
 local object=ctx and ctx.facingObject
 if not object or (object.gfx or object.graphicsId)~=FM.GFX_IDS.PUSHABLE_BOULDER then return false end
 local result=FM.tryStrengthOW(ctx)
 return result and result.ok==true and result.action=='strength'
end
function Actions.execute(session,id,row)
 if row.item then
  local Bag=require('src.ui.game3.bag_menu')
  Bag.show(session.bag,{session=session,pocket='KEY_ITEMS'});Bag.settle()
  for i,item in ipairs(Bag.list())do if item.id==row.item then
   Bag.cursor=i;press(Bag,'a')
   for j,action in ipairs(Bag.ACTIONS)do if action=='USE' then Bag.actionCursor=j;press(Bag,'a');return true end end
  end end
  Bag.close();return false
 end
 local Party=require('src.ui.game3.party_menu')
 Party.show(session.party,{session=session});Party.cursor=row.slot;press(Party,'a')
 -- Field Kit may supply an owned HM through a compatible party member.
 -- Expose only the freshly validated action to the native handler; never teach it.
 local label=id:gsub('_',' ')
 if not Party._fieldMoveNames[label] then
  table.insert(Party.ACTIONS,#Party.ACTIONS,label)
  Party._fieldMoveNames[label]=true
 end
 for i,action in ipairs(Party.ACTIONS)do if action==id:gsub('_',' ') then
  Party.actionCursor=i;press(Party,'a')
  -- Native Fly remembers the temporary Party menu used by this shortcut.
  -- Clearing only this launch's return record makes Cancel return to field.
  if id=='FLY' then Party._flyReturn=nil end
  return true
 end end
 Party.close();return false
end
return Actions

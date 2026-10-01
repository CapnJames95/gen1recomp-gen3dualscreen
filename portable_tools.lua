-- Native item shortcuts. Model reads use the adapter inventory snapshot, not Bag sanitation.
local Tools={}
local function req(n)return require('src.core.game3.'..n)end
function Tools.rows(kind,view)
 if kind~='rods' and kind~='bike' then return {} end
 local inv=view and view.save and view.save.inventory or {};local P=req('player')
 if kind=='rods' then
  local rows={}
  for _,id in ipairs({'OLD_ROD','GOOD_ROD','SUPER_ROD'})do rows[#rows+1]={label=id:gsub('_',' '),id=id,short=({'OLD','GOOD','SUPER'})[#rows+1],owned=(inv[id]or 0)>0}end
  return rows
 end
 local emerald=view and view.session and view.session.version=='emerald'
 local id=emerald and ((inv.MACH_BIKE or 0)>0 and 'MACH_BIKE' or 'ACRO_BIKE') or 'BICYCLE'
 if emerald and (inv.MACH_BIKE or 0)>0 and (inv.ACRO_BIKE or 0)>0 then
  id=(P.bikeType=='acro' or (view.session.modData and view.session.modData.hoenn_tools and view.session.modData.hoenn_tools.bikeChoice=='Acro')) and 'ACRO_BIKE' or 'MACH_BIKE'
 end
 return {{label=P.biking and 'GET OFF BIKE' or 'USE '..id:gsub('_',' '),id=id,short=P.biking and 'GET OFF' or 'USE',owned=(inv[id]or 0)>0},
  {label=emerald and ('SWAP TO '..(id=='MACH_BIKE' and 'ACRO' or 'MACH')) or 'SWAP: EMERALD ONLY',id='swap',short='SWAP',owned=emerald and (inv[id]or 0)>0}}
end
function Tools.swapLabel(view)
 local bike=Tools.rows('bike',view)[1]
 return bike and bike.owned and bike.id:gsub('_',' ') or 'NO BIKE'
end
-- Pure availability check: use the inventory snapshot, never sanitize Bag or
-- execute an item action while drawing Home.
function Tools.ready(field,kind,index,view)
 local row=Tools.rows(kind,view)[index]
 if not row or not row.owned or not field or not field:idle() or field.Stack.busy() then return false end
 local g=field.bridge.getGame();local s=g and g.session
 if not s or (g.speedLocked and g:speedLocked()) or (s.frontier and (s.frontier.challengeStatus or 0)~=0)
   or req('safari').isActive(s)then return false end
 if kind=='rods' then return req('item_use').canFish()==true end
 local P=req('player');local emerald=s.version=='emerald'
 local R=emerald and req('bike.rse');local F=req('scripting.flags')
 if emerald then
  local c=req('constants').of('emerald')
  if R.onRail() or F.getFlag({flags=s.flags,vars=s.vars},nil,c:require('flags','FLAG_SYS_CYCLING_ROAD')) then return false end
 elseif P.biking and P.isOnCyclingRoad and P.isOnCyclingRoad(s)then return false end
 if index==2 then
  if not emerald or P.surfing or P.underwater or not R.notUsingAcroOnBumpySlope()then return false end
  if not P.biking then return true end
 end
 local def=g.data and g.data.maps and g.data.maps[s.map] or req('map').currentDef()
 local allowed=def and def.bikingAllowed
 if allowed~=nil then allowed=(tonumber(allowed)or 0)~=0
 elseif not emerald then
  local id=s.map or '';local pair=def and (def.pair or def.midLayout and def.midLayout.pair)
  allowed=type(pair)=='string' and pair:find('outdoor',1,true)~=nil
  if not allowed then
   local indoors=false
   for _,name in ipairs({'HOUSE','CENTER','GYM','MART','LAB','CAVE','TUNNEL','TOWER','MANSION'})do if id:find(name,1,true)then indoors=true end end
   allowed=not indoors and (id:find('ROUTE',1,true) or id:find('TOWN',1,true) or id:find('CITY',1,true) or id:find('ISLAND',1,true))~=nil
  end
 end
 return allowed==true and (not emerald or not R.bikingDisallowedByPlayer())
end
function Tools.activate(field,kind,index)
 if not field:idle() or field.Stack.busy()then return false end
 local g=field.bridge.getGame();local s=g.session
 if (g.speedLocked and g:speedLocked()) or (s.frontier and (s.frontier.challengeStatus or 0)~=0) or req('safari').isActive(s)then return false end
 local B=req('bag');local I=req('items_data');local P=req('player')
 if kind=='rods' then
  local id=({'OLD_ROD','GOOD_ROD','SUPER_ROD'})[index];local n=id and I.toNumericId(id)
  if not n or not B.has(s.bag,n,1)then return false end
  local row=field:query('rod:'..n,field:context());if not row.enabled then return false end
  return field:activate('rod:'..n)
 end
 local c=req('constants').of(s.version)
 local mach=s.version=='emerald' and c:require('items','ITEM_MACH_BIKE');local acro=s.version=='emerald' and c:require('items','ITEM_ACRO_BIKE')
 local id=s.version=='emerald' and (B.has(s.bag,mach,1) and mach or acro) or I.toNumericId('BICYCLE')
 if mach and B.has(s.bag,mach,1) and B.has(s.bag,acro,1)then
  id=P.bikeType=='acro' and acro or (s.modData and s.modData.hoenn_tools and s.modData.hoenn_tools.bikeChoice=='Acro' and acro or mach)
 end
 if not id or not B.has(s.bag,id,1)then return false end
 if index==1 then return req('item_use').useBike(s,id)end
 if index~=2 or s.version~='emerald' then return false end
 if s.frontier and (s.frontier.challengeStatus or 0)~=0 or req('safari').isActive(s)then return false end
 local R=req('bike.rse');local F=req('scripting.flags')
 if P.surfing or P.underwater or R.onRail() or not R.notUsingAcroOnBumpySlope()
  or F.getFlag({flags=s.flags,vars=s.vars},nil,c:require('flags','FLAG_SYS_CYCLING_ROAD'))then return false end
 local to=id==mach and acro or mach;local riding=P.biking;local U=req('item_use')
 if riding and not U.useBike(s,id)then return false end
 if not B.has(s.bag,to,1)then
  if not B.remove(s.bag,id,1)then return false end
  if not B.add(s.bag,to,1)then B.add(s.bag,id,1);if riding then U.useBike(s,id)end;return false end
 end
 if s.registeredItem==id then s.registeredItem=to end
 s.modData=s.modData or {};s.modData.hoenn_tools=s.modData.hoenn_tools or {};s.modData.hoenn_tools.bikeChoice=to==mach and 'Mach' or 'Acro'
 if riding then U.useBike(s,to)end
 return true
end
return Tools

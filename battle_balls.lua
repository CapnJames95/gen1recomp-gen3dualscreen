-- Companion-owned ball selection; the engine alone resolves the command.
local Balls={};Balls.__index=Balls
function Balls.new(mod,bridge)
 local self=setmetatable({mod=mod,bridge=bridge,held={}},Balls)
 local Ui=require('src.core.game3.battle.ui')
 local Runtime=require('src.mods.Runtime')
 local owner=Runtime.events
 self.Ui=Ui;self.Bag=require('src.core.game3.bag');self.Items=require('src.core.game3.items_data')
 local function alive() return Runtime.events==owner and mod.find('frlg_dual_screen') and bridge.enabled() end
 self.alive=alive
 local previous=Ui.handleInput
 Ui.handleInput=function(input,...)
  if self:valid() then
   for _,key in ipairs({'b','up','down','left','right','a'})do
    if input:wasPressed(key) then self:input(key);break end
   end
   return true
  end
  return previous(input,...)
 end
 for _,spec in ipairs({{'input.gamepad','ball_pad','button'},{'input.key','ball_key','key'}})do
  mod.hooks:wrap(spec[1],function(next,game,event)
   local key=event[spec[3]];local token=spec[1]..tostring(event.joystick)..tostring(key)
   if event.phase=='released' then
    local held=self.held[token];self.held[token]=nil
    if held then return true end
   elseif event.phase=='pressed' and alive() and spec[1]=='input.gamepad'
    and (key=='y' or key=='x') and game==bridge.getGame() and self:safariReady() then
    if self.held[token] then return true end
    self.held[token]=true
    -- Let the native handler enforce storage capacity and resolve the action.
    Ui._menuIndex=key=='y' and 1 or 2
    Ui.handleInput({wasPressed=function(_,button)return button=='a' end})
    return true
   elseif event.phase=='pressed' and alive() and key==mod.options:get(spec[2]) and key~='off' then
    if self.held[token] then return true end
    if game==bridge.getGame() and (self:valid() or self:open()) then self.held[token]=true;return true end
   end
   return next(game,event)
  end,20000)
 end
 local Game=require('src.core.Game3');local focus=Game.focus
 Game.focus=function(game,focused,...)
  if Runtime.events==owner and not focused then self:close();self.held={} end
  return focus(game,focused,...)
 end
 for _,event in ipairs({'game.ready','battle.started','battle.ended'})do
  mod.events:on(event,function()self:close();self.held={} end)
 end
 return self
end
function Balls:safariReady()
 local g=self.bridge.getGame();local U=self.Ui;local st=U._st
 return self.alive() and g and g.session==require('src.core.game3.runtime').getSession()
  and U._mode=='menu' and not U._headless and not U.isShowing() and not U._pendingCommand
  and st and st.safari and not(st.link or st.spectate)
  and not require('src.ui.game3.stack').busy() and not require('src.ui.game3.help_system').isOpen()
end
function Balls:ready()
 local g=self.bridge.getGame();local U=self.Ui;local st=U._st
 return self.alive() and g and g.session==require('src.core.game3.runtime').getSession()
  and U._mode=='menu' and not U._headless and not U.isShowing() and not U._pendingCommand
  and st and st.wild and not(st.double or st.safari or st.link or st.spectate
   or st.oldManTutorial or st.pokedude or st.ghostBattle)
  and not require('src.ui.game3.stack').busy() and not require('src.ui.game3.help_system').isOpen()
  and not (U._frlgQolBallModal and U._frlgQolBallModal())
end
function Balls:valid()
 if self.screen and (not self:ready() or self.state~=self.Ui._st
   or self.session~=self.bridge.getGame().session) then self:close() end
 return self.screen~=nil
end
function Balls:close() self.screen=nil;self.confirm=nil;self.pointer=nil end
function Balls:hint()
 if not self:ready() or self:valid() then return nil end
 local pad=self.mod.options:get('ball_pad');local key=self.mod.options:get('ball_key')
 return ({y='Y',x='X',leftstick='L3',rightstick='R3',leftshoulder='LB',rightshoulder='RB',back='BACK'})[pad]
  or (key and key~='off' and key:upper()) or 'TAP'
end
function Balls:rows()
 local out={}
 for _,id in ipairs({4,3,2,6,7,8,9,10,11,12})do
  local count=self.Bag.get(self.session.bag,id)
  if count>0 then out[#out+1]={id=id,name=self.Items.displayName(id),count=count} end
 end
 return out
end
function Balls:open()
 if not self:ready() then return false end
 self.state=self.Ui._st;self.session=self.bridge.getGame().session;self.cursor=1
 self.screen={id='dual_screen_balls',battleModal=true,companionBalls=true}
 self.screen.mod={handleInput=function(input)
  for _,key in ipairs({'b','up','down','left','right','a'})do if input:wasPressed(key) then self:input(key);break end end
 end}
 return true
end
function Balls:input(key)
 if not self:valid() then return end
 local rows=self:rows()
 if key=='b' then if self.confirm then self.confirm=nil else self:close() end;return end
 if self.confirm then
  if key=='a' and self.Bag.get(self.session.bag,self.confirm.id)>0 then
   self.Ui._pendingCommand={kind='bag',user='player',itemId=self.confirm.id}
   self.Ui._mode='none';self:close()
  end
  return
 end
 if #rows==0 then return end
 self.cursor=math.min(self.cursor,#rows)
 if key=='up' then self.cursor=(self.cursor-2)%#rows+1
 elseif key=='down' then self.cursor=self.cursor%#rows+1
 elseif key=='left' then self.cursor=math.max(1,self.cursor-4)
 elseif key=='right' then self.cursor=math.min(#rows,self.cursor+4)
 elseif key=='a' then self.confirm=rows[self.cursor] end
end
function Balls:tap(x,y)
 if not self:valid() then return end
 if y<27 and x<54 then self:input('b');return end
 if self.confirm then
  if y>=158 and y<193 then if x<119 then self:input('b') else self:input('a') end end
 elseif y>=34 and y<178 then
  local index=math.floor((self.cursor-1)/4)*4+math.floor((y-34)/36)+1
  if self:rows()[index] then self.cursor=index;self:input('a') end
 elseif y>=185 then self:input(x<120 and 'left' or 'right') end
end
function Balls:draw(H)
 local function ball(id,x,y,scale)
  -- Use the imported native item artwork, keyed by the actual Bag item ID.
  if not require('src.ui.game3.bag_chrome').drawItemIcon(id,x-12*scale,y-12*scale,scale) then
   H:label('?',x-8,y-5,H.colors.mutedInk,16,'center')
  end
 end
 H:panel(5,3,230,25,false);H:label('< BACK',10,10,H.colors.blue,47)
 H:label(self.confirm and 'READY TO THROW' or 'CHOOSE A BALL',61,10,H.colors.ink,168)
 if self.confirm then
  H:panel(12,40,216,102,true,H.colors.amber)
  ball(self.confirm.id,120,68,1.5)
  H:label(self.confirm.name,22,91,H.colors.ink,196,'center')
  H:partyInfo('IN BAG: '..self.Bag.get(self.session.bag,self.confirm.id),22,117,H.colors.mutedInk,196,'center')
  H:button(6,158,111,35,'CANCEL',false);H:button(123,158,111,35,'THROW',true)
  H:partyInfo('A: THROW   B: BACK',10,201,H.colors.mutedInk,220,'center')
 else
  local rows=self:rows();local first=math.floor((self.cursor-1)/4)*4+1
  if #rows==0 then H:label('NO BALLS IN YOUR BAG',12,88,H.colors.mutedInk,216,'center') end
  for i=first,math.min(first+3,#rows)do
   local row=rows[i];local y=34+(i-first)*36
   H:panel(6,y,228,32,i==self.cursor,H.colors.blue)
   ball(row.id,23,y+16,1)
   H:label(row.name,39,y+11,H.colors.ink,150)
   H:partyInfo('x'..row.count,187,y+11,H.colors.blue,37,'right')
  end
  H:button(6,185,57,26,'<',false);H:button(177,185,57,26,'>',false)
  H:partyInfo('SELECT A BALL',65,186,H.colors.ink,110,'center')
  H:partyInfo(math.ceil(self.cursor/4)..' / '..math.max(1,math.ceil(#rows/4)),65,201,H.colors.mutedInk,110,'center')
 end
end
return Balls

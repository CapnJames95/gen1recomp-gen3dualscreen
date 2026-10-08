-- Companion ownership for collection editors. Native actions keep their own validation.
local Bridge = {}
Bridge.__index = Bridge
local supported = { ['fly-teleport']=true, legalmon=true, ['event-distributor']=true, autobreeder=true,
  shiny_hunter=true, encounter_tour=true, encounter_reset=true,
  ['daycare-viewer']=true, ['pokemon-services']=true, ['quick-heal-party']=true,
  frlg_dual_touch_actions=true, ['fly-teleport']=true }
-- Existing semantic touch adapters keep ownership of these native menus.
local liveSupported={legalmon=true,['event-distributor']=true,autobreeder=true,shiny_hunter=true,encounter_tour=true}
local adapted={start=true,save=true,party=true,bag=true,tm_case=true,berry_pouch=true,
 summary=true,pokedex=true,option=true,trainer=true,naming=true,box_storage=true,
 pc_menu=true,item_pc=true,shop=true,move_relearner=true,mod_manager=true}
function Bridge.new(mod, theme, enabled, getGame)
  local self=setmetatable({mod=mod,theme=theme,enabled=enabled,getGame=getGame},Bridge)
  local Runtime=require('src.mods.Runtime')
  local owner=Runtime.events
  require('src.ui.game3.start_menu')._frlgStartEditorOnCompanion=function()
    if Runtime.events~=owner or not self.enabled() then return false end
    local layer=self:layer()
    return layer and layer.mod.startAppearanceEditor or false
  end
  local BattleUi=require('src.core.game3.battle.ui')
  BattleUi._frlgQolBallPresented=function()
    return Runtime.events==owner and self.enabled() and self:ballLayer()~=nil
  end
  BattleUi._frlgCapturePresented=function(screen)
    if Runtime.events~=owner or not self.enabled() then return false end
    local layer=self:layer()
    return layer and layer.id=='capture-assistant' and layer.mod==screen or false
  end
  self.Touch=assert(load(assert(mod:read('menu_touch.lua')), '@frlg_dual_screen/menu_touch.lua'))()
  self.Stack=require('src.ui.game3.stack')
  local function wrap(target,key,handler)
    target.__frlgDual=target.__frlgDual or {}
    local record=target.__frlgDual[key]
    if not record then
      record={previous=target[key]};target.__frlgDual[key]=record
      target[key]=function(...)
        if Runtime.events==record.owner then return record.handler(record.previous,...) end
        return record.previous(...)
      end
    end
    record.owner,record.handler=owner,handler
  end
  wrap(require('src.ui.game3.ui_pass'),'drawUi',function(previous,...)
    self.nativeDraw=previous
    if not self:layer() then return previous(...) end
    if self:nativeNavigation() then love.graphics.clear(0,0,0,1) end
  end)
  wrap(require('src.core.Game3'),'_drawHud',function(previous,...)
    -- Shiny Hunter and Encounter Tour also draw the same panel through HUD.
    if not self:layer() then return previous(...) end
  end)
  wrap(self.Stack,'fullscreen',function(previous,...)
    local layer=self:layer()
    -- Fly owns a fullscreen native GPU scene. Keeping the world alive here
    -- makes its render state compete with the companion's native map pass.
    if self:nativeNavigation(layer) or (layer and layer.id=='region_map' and layer.mod.mode=='fly') then return true end
    if layer then return false end -- retain field rendering, not field updates
    return previous(...)
  end)
  local Oam=require('src.core.game3.oam')
  wrap(Oam,'buildOamBuffer',function(previous,...)
    local buffer=previous(...);local Party=require('src.ui.game3.party_menu');local top=self.Stack.top()
    if not self.enabled() or not Party.open or (top and top.id=='party')then return buffer end
    local ids={}
    for _,slot in pairs(Party._oam or {})do for _,key in ipairs({'mon','ball','status','item'})do
      if slot[key]~=nil then ids[slot[key]]=true end
    end end
    if Party._summaryIcon~=nil then ids[Party._summaryIcon]=true end
    local out={};for _,sprite in ipairs(buffer)do if not ids[sprite._id]then out[#out+1]=sprite end end
    Oam._buffer=out;return out
  end)
  wrap(Oam,'flush',function(previous,layer,...)
    if layer=='ui' and self:fallback() and not self.drawingNative then return end
    return previous(layer,...)
  end)
  wrap(self.Stack,'pop',function(previous,id)
    if self.live and id==self.live.id then self.live.mod._frlgDetached=nil;self.live=nil;return true end
    return previous(id)
  end)
  local Game3=require('src.core.Game3')
  wrap(Game3,'focus',function(previous,game,focused,...)
    self:release();self.hotkeyDown={}
    return previous(game,focused,...)
  end)
  return self
end
-- Emerald navigation draws native 240x160 scenes; keep its GPU state isolated
-- from both the upper world pass and the companion's tool chrome.
function Bridge:nativeNavigation(layer)
  layer=layer or self:layer()
  return layer and (layer.id=='rse_region_map' or layer.id=='rse_pokenav' or layer.id=='rs_pokenav')
end
function Bridge:drawNavigation(layer)
  local G=love.graphics
  self.navigationCanvas=self.navigationCanvas or G.newCanvas(240,160)
  self.navigationCanvas:setFilter('nearest','nearest')
  G.push('all')
  G.setCanvas(self.navigationCanvas);G.origin();G.setScissor();G.setShader();G.clear(0,0,0,1)
  self.drawingNative=true
  local Oam=require('src.core.game3.oam');local previous=Oam.setLayer('ui')
  local ok,err=pcall(layer.mod.draw)
  Oam.setLayer(previous);self.drawingNative=false;G.pop()
  if not ok then error(err,0) end
  G.setColor(1,1,1,1);G.draw(self.navigationCanvas,0,20)
end
function Bridge:ballLayer()
  local Ui=require('src.core.game3.battle.ui')
  local screen=Ui._frlgQolBallModal and Ui._frlgQolBallModal()
  if screen then
    if not self.ball or self.ball.mod~=screen then
      self.ball={id='frlg_qol_ball_shortcut:menu',mod=screen,battleModal=true}
    end
    return self.ball
  end
  self.ball=nil
end
function Bridge:captureLayer()
  local top=self.Stack.top()
  if top and top.id=='capture-assistant' and top.mod and top.mod.captureCompanion==1
      and not top.mod.closed and type(top.mod.draw)=='function' then
    -- The battle update wrapper owns physical input; touch must go directly to
    -- that same modal instead of queuing a battle command underneath it.
    top.battleModal=top.mod.battle~=nil
    return top
  end
end
function Bridge:layer()
  if not self.enabled() then return nil end
  local capture=self:captureLayer()
  if capture then return capture end
  if self.balls and self.balls:valid() then return self.balls.screen end
  local ball=self:ballLayer()
  if ball then return ball end
  if self.live and not self.Stack.busy() and self:fieldIdle() then return self.live end
  local top=self.Stack.top()
  if top and (supported[top.id] or tostring(top.id):match('^frlg_qol_.+:menu$') or self:fallback(top))
      and top.mod and type(top.mod.draw)=='function' then return top end
end
function Bridge:fallback(top)
  if not self.enabled() then return nil end
  top=top or self.Stack.top()
  if not top or not top.mod or type(top.mod.draw)~='function' or supported[top.id]
    or tostring(top.id):match('^frlg_qol_') then return nil end
  if top.id=='summary' and top.mod._summaryIvs
      and type(top.mod._summaryIvs.nativePanel)=='function'
      and top.mod._summaryIvs.nativePanel() then return top end
  if require('src.core.game3.battle').isActive() then return nil end
  if top.id=='summary' and (top.mod._page==top.mod.PAGE_EGG
      or (top.mod._page==top.mod.PAGE_MOVES_INFO and top.mod._mode~='select_move')) then return top end
  if not adapted[top.id] then return top end
  -- The original Bag adapter omits native reorder mode.
  if top.id=='bag' and (top.mod.mode=='swap' or top.mod.mode=='move') then return top end
end
function Bridge:visible()
  return self.enabled() and (self:layer()~=nil or ((self.qol==true or (self.route and self.route.open)) and not self.Stack.busy() and self:fieldIdle()))
end
function Bridge:release(id,keepContext)
  if id==nil then
    self.contact=nil;self:stopFastForward()
    if not keepContext or not self.enabled() then self.contextContact=nil end
  end
  self.pointers=self.pointers or {}
  for key,p in pairs(self.pointers) do
    if id==nil or key==id then
      if p.token then self.mod.input:release(p.token) end
      self.pointers[key]=nil
    end
  end
  self.held=nil
end
function Bridge:fieldIdle()
  local g=self.getGame()
  if not g or g.phase~='field' then return false end
  local Field=require('src.core.game3.field')
  local Space=require('src.core.game3.scripting.space')
  return not require('src.core.game3.battle').isActive()
    and not require('src.core.game3.battle_transition').isActive()
    and not require('src.ui.game3.message').isOpen()
    and not require('src.ui.game3.choice').active
    and not require('src.ui.game3.fade').isActive()
    and not require('src.core.game3.warp').isBusy()
    and not Field.locked and not Field.isFishing()
    and not (Space.vm and Space.vm:isRunning())
    and not (Space._immediateVm and Space._immediateVm:isRunning())
end
function Bridge:closeLive()
  if self.live then
    local old=self.live;self.live=nil;old.mod._frlgDetached=nil
    -- Close through the editor so its active reference is also cleared.
    self.Stack.push(old.id,old.mod,{fullscreen=true})
    for _=1,32 do
      if not self.Stack.has(old.id) then break end
      old.mod.handleInput({wasPressed=function(_,k)return k=='b'end})
    end
    self.Stack.pop(old.id)
  end
end
function Bridge:canLive(top)
  if not top or not liveSupported[top.id] or not top.mod.pages then return false end
  if top.id=='shiny_hunter' or top.id=='encounter_tour' then
    local other=self.mod.find(top.id)
    return other and other.exports.dualScreenProtocol==1
  end
  return true
end
function Bridge:toggleLive()
  if self.live then
    local old=self.live;self.live=nil;old.mod._frlgDetached=nil
    self.Stack.push(old.id,old.mod,{fullscreen=true});return
  end
  local top=self:layer()
  if not self:canLive(top) or not self:fieldIdle() then return end
  -- Automation owns field timing while running; do not detach its controller.
  local c=top.mod.controller or top.mod.C
  if c and ((c.running and c.running()) or c.tour or c.pendingReset) then return end
  self.Stack.pop(top.id)
  require('src.ui.game3.start_menu').close(true)
  if self.Stack.busy() then self.Stack.push(top.id,top.mod,{fullscreen=true});return end
  self.live=top;top.mod._frlgDetached=true;self.liveSession=self.getGame().session
  self:release()
end
function Bridge:update(dt)
  if self.fastContact and (not self:fastEnabled() or not self.enabled() or not self.qol or self:layer() or not self:fieldIdle()) then self:stopFastForward() end
  local multi=false -- No virtual control deck: retain the host's normal pointer protocol.
  if multi~=self.multiEnabled then
    local Second=require('src.render.SecondScreen')
    if Second.setMultiTouch then Second.setMultiTouch(multi) end
    self:release();self.multiEnabled=multi
  end
  if self.live then
    if self.getGame().session~=self.liveSession or not self.enabled() then self:closeLive();return end
    local screen=self.live.mod
    -- Text entry/search jobs regain modal ownership; field and editor must not share keyboard input.
    local c=screen.controller or screen.C
    if screen.editor or screen.job or screen.candidateSearch or (c and ((c.running and c.running()) or c.tour or c.pendingReset)) then
      self:toggleLive();return
    end
    if self:fieldIdle() and not self.Stack.busy() and screen.update then screen.update(dt) end
  end
end
function Bridge:send(key)
  local layer=self:layer()
  if layer and not self.live and (layer.battleModal or layer==self:captureLayer() or supported[layer.id] or tostring(layer.id):match('^frlg_qol_.+:menu$')) then
    layer.mod.handleInput({wasPressed=function(_,action)return action==key end,isDown=function()return false end})
    return true
  end
  if self.live then
    if not layer or require('src.core.game3.player').moving then return false end
    layer.mod.handleInput({wasPressed=function(_,k)return k==key end,isDown=function()return false end})
    self:update(0)
    return true
  end
  local g=self.getGame()
  if key=='l' or key=='r' then
    g.input:sourcePress(key,'frlg-dual:shoulder');g.input:sourceRelease(key,'frlg-dual:shoulder')
  else self.mod.input:tap(g,key) end
  return true
end
function Bridge:rowTouch(x,y)
  local layer=self:layer();if not layer then return false end
  if not supported[layer.id] and layer~=self:captureLayer()
      and not tostring(layer.id):match('^frlg_qol_.+:menu$') then return false end
  local kind,index=self.Touch.row(layer,x,y-20)
  if not kind then return false end
  if self.live and (not self:fieldIdle() or require('src.core.game3.player').moving) then return true end
  if kind=='key' then layer.mod.editor.cursor=index else self.Touch.page(layer.mod).cursor=index end
  self:send('a');return true
end

function Bridge:installHotkeys()
  self.hotkeyDown={}
  local function hook(kind,option,field)
    self.mod.hooks:wrap(kind,function(next,game,event)
      local down=self.hotkeyDown
      local key=event[field];local token=kind..':'..tostring(event.joystick)..':'..tostring(key)
      if event.phase=='released' and down[token] then down[token]=nil;return end
      local binding=self.mod.options:get(option)
      if key and binding~='off' and key==binding and self.enabled()
          and self:fieldIdle() and not self.Stack.busy() then
        if event.phase=='pressed' and not down[token] then
          down[token]=true;self.route:uncaught(self.mod.options:get('encounter_scope') or 'here')
        end
        return
      end
      return next(game,event)
    end)
  end
  hook('input.key','encounter_key','key');hook('input.gamepad','encounter_pad','button')
end
function Bridge:fastForward()
  local m=self.mod.find('frlg_qol_hold_fast_forward')
  return m and m.exports and m.exports.setTouchHeld
end
function Bridge:fastEnabled()
  local g=self.getGame();local opts=g and g.mods and g.mods.modOptions.frlg_qol_hold_fast_forward
  return self:fastForward()~=nil and (not opts or opts.enabled~=false)
end
function Bridge:stopFastForward()
  if self.fastRelease then self.fastRelease(false);self.fastRelease=nil end
  self.fastContact=nil
end
function Bridge:qolCapacity()
  -- A disabled bundled component disappears from find(), but its settings
  -- remain available. Keep rows stationary while its switch is toggled.
  local game=self.getGame();local schemas=game and game.mods and game.mods.optionSchemas
  return (self:fastForward() or (schemas and schemas.frlg_qol_hold_fast_forward)) and 4 or 5
end
function Bridge:qolRows()
  local game=self.getGame();local loader=game and game.mods
  local rows={}
  local suite=self.mod.find('frlg-qol-suite')
  if suite and suite.exports and suite.exports.rows then
    for _,row in ipairs(suite.exports.rows()) do
      if row.ready then rows[#rows+1]=row end
    end
  end
  for id,schema in pairs(loader and loader.optionSchemas or {}) do
    local loaded=loader.mods[id]
    if id:match('^frlg_qol_')
        and loaded and loaded.state=='loaded' then
      for _,row in ipairs(schema) do
        if row.key=='enabled' and row.type=='toggle' then
          local stored=(loader.modOptions[id] or {})[row.key]
          local value=stored; if value==nil then value=row.default end
          rows[#rows+1]={id=id,key=row.key,value=value==true,
            label=loaded.manifest.name or id}
        end
      end
    end
  end
  table.sort(rows,function(a,b) return a.label<b.label end)
  return rows
end
function Bridge:qolTouch(x,y)
  if y<20 and x<48 then self.qol=false;return end
  local rows=self:qolRows();local capacity=self:qolCapacity();local pages=math.max(1,math.ceil(#rows/capacity))
  self.qolPage=math.min(self.qolPage or 1,pages)
  if y>=184 then
    self.qolPage=((self.qolPage-1+(x<120 and -1 or 1))%pages)+1
  elseif y>=30 and y<30+capacity*30 then
    local index=(self.qolPage-1)*capacity+math.floor((y-30)/30)+1
    local row=rows[index]
    if row then
      -- Use the same persistence + event path as the host's mod manager.
      local manager=require('src.mods.ManagerState').new(self.getGame())
      manager:setOption(row.id,row.key,not row.value)
    end
  end
end
function Bridge:pointer(action,x,y,id)
  if self.fieldTile and self.fieldTile:visible() then
    if action=='down' then self.fieldTile.pointer={x=x,y=y}
    elseif action=='cancel' then self.fieldTile.pointer=nil
    elseif action=='move' and self.fieldTile.pointer and (math.abs(x-self.fieldTile.pointer.x)>10 or math.abs(y-self.fieldTile.pointer.y)>10) then self.fieldTile.pointer=nil
    elseif action=='up' then local p=self.fieldTile.pointer;self.fieldTile.pointer=nil;if p then self.fieldTile:tap(x,y) end
    elseif action=='tap' then self.fieldTile:tap(x,y) end
    return true
  end
  id=tostring(id or '0');if id=='' then id='0' end
  local fast=self.fastContact
  if fast then
    if action=='cancel' or not self.enabled() or not self.qol or self:layer()
      or (id==fast and (action=='up' or (action=='move' and (not x or not y or x<4 or x>=236 or y<154 or y>=182)))) then self:stopFastForward() end
    return true
  end
  if action=='down' and self.enabled() and self.qol and not self:layer()
      and x and y and x>=4 and x<236 and y>=154 and y<182 then
    local hold=self:fastForward()
    if hold and self:fastEnabled() then self.fastContact=id;self.fastRelease=hold;hold(true);return true end
  end
  if self.balls and self.balls:valid() then
    if action=='down'  then self.balls.pointer={x=x,y=y}
    elseif action=='cancel' then self.balls.pointer=nil
    elseif action=='move' and self.balls.pointer and (math.abs(x-self.balls.pointer.x)>10 or math.abs(y-self.balls.pointer.y)>10) then self.balls.pointer=nil
    elseif action=='up' then local p=self.balls.pointer;self.balls.pointer=nil;if p then self.balls:tap(x,y) end
    elseif action=='tap' then self.balls:tap(x,y) end
    return true
  end
  id=tostring(id or '0');if id=='' then id='0' end
  if not self:visible() then self:release();self.contact=nil;self.actions=nil;return false end
  local layer=self:layer()
  if layer and layer.mod.startAppearanceEditor and type(layer.mod.pointer)=='function'
      and (action=='cancel' or action=='move' or action=='up' or (x and y and y>=20 and y<180)) then
    self.contact=nil;self.actions=nil
    return layer.mod.pointer(action,x,y and y-20,id)
  end
  local page=layer and self.Touch.page(layer.mod)
  local editor=layer and layer.mod.editor
  local function activate()
    if not x or not y or x<0 or x>=240 or y<0 or y>=216 then return end
    if self.actions and self.actions~=layer then self.actions=nil;return end
    if self.actions then
      if y<20 and x<48 then self.actions=nil;return end
      local row=self.Touch.hitActions(x,y)
      if row then self.actions=nil;if row[2]~='dismiss' then self:send(row[2]) end end
      return
    end
    if self.route and self.route.open and not layer then self.route:tap(x,y);return end
    if self.qol and not layer then self:qolTouch(x,y);return end
    if y<20 and x>=164 and layer then self:toggleLive();return end
    if y<20 and x<48 then if layer then self:send('b') end;return end
    if layer and y>=184 and y<212 then
      local index=math.floor((x-4)/78)+1
      if index>=1 and index<=3 and x<4+(index-1)*78+74 then
        local row=self.Touch.footer(layer)[index]
        if row[2]=='actions' then self.actions=layer else self:send(row[2]) end
      end
      return
    end
    self:rowTouch(x,y)
  end
  if action=='cancel' then self:release();self.contact=nil;return true end
  if action=='tap' then if not self.contact then activate() end;return true end
  if action=='down' then
    if not self.contact and x and y then
      self.contact={id=id,x=x,y=y,layer=layer,page=page,editor=editor,actions=self.actions,
        token=self.Touch.token(layer),target=self.Touch.target(layer,x,y,self.actions),
        qol=self.qol,route=self.route and self.route.open}
    end
  elseif action=='move' then
    local c=self.contact
    if c and c.id==id and x and y and (math.abs(x-c.x)>10 or math.abs(y-c.y)>10) then c.dragged=true end
  elseif action=='up' then
    local c=self.contact
    if c and c.id==id then
      self.contact=nil
      if c.layer==layer and c.page==page and c.editor==editor and c.actions==self.actions and c.token==self.Touch.token(layer)
        and c.qol==self.qol and c.route==(self.route and self.route.open) and x and y then
        local dx,dy=x-c.x,y-c.y
        if not c.dragged and math.abs(dx)<=10 and math.abs(dy)<=10
          and c.target==self.Touch.target(layer,x,y,self.actions) then activate()
        elseif layer and not editor and not self.actions and math.abs(dy)>24 and math.abs(dy)>math.abs(dx) then
          self:send(dy<0 and 'right' or 'left')
        end
      end
    end
  end
  return true
end

function Bridge:draw()
  local G=love.graphics;local H=self.theme;local layer=self:layer()
  G.push('all');G.setShader();G.setColor(H.colors.bg);G.rectangle('fill',0,0,240,216)
  if self.fieldTile and self.fieldTile:visible() then self.fieldTile:draw(H);G.pop();return end
  if layer and layer.companionBalls then self.balls:draw(H);G.pop();return end
  if self.route and self.route.open and not layer then self.route:draw(H);G.pop();return end
  if self.qol and not layer then
    H:label('< BACK',5,4,H.colors.blue,46)
    H:label('LIVE QOL SETTINGS',62,4,H.colors.ink,172)
    local rows=self:qolRows();local capacity=self:qolCapacity();local pages=math.max(1,math.ceil(#rows/capacity))
    self.qolPage=math.min(self.qolPage or 1,pages)
    for slot=1,capacity do
      local row=rows[(self.qolPage-1)*capacity+slot]
      if row then
        H:panel(4,30+(slot-1)*30,232,27,false)
        H:label(row.label,10,37+(slot-1)*30,H.colors.ink,180)
        H:label(row.value and 'ON' or 'OFF',199,37+(slot-1)*30,
          row.value and H.colors.green or H.colors.mutedInk,32)
      end
    end
    if capacity==4 then H:button(4,154,232,28,self:fastEnabled() and 'HOLD TO FAST FORWARD' or 'FAST FORWARD DISABLED',self.fastContact~=nil) end
    if #rows==0 then H:label('Install FRLG QoL mods to use this page.',8, 60,H.colors.mutedInk,224) end
    H:button(4,184,112,28,'< PREV',false)
    H:button(124,184,112,28,'NEXT >',false)
    G.pop();return
  end
  H:label('< BACK',5,4,H.colors.blue,46)
  H:label(self:nativeNavigation(layer) and ((layer.id=='rse_pokenav' or layer.id=='rs_pokenav') and 'POKENAV' or 'TOWN MAP') or 'MOD TOOLS',62,4,H.colors.ink,100)
  if layer and self:canLive(layer) then H:label(self.live and 'LIVE / PAUSE' or 'PAUSED / LIVE',164,4,H.colors.blue,74) end
  if layer then
    if self:nativeNavigation(layer) then self:drawNavigation(layer) else
    G.push('all');G.translate(0,20)
    self.drawingNative=true
    local Oam=require('src.core.game3.oam');local previous=Oam.setLayer('ui')
    local ok,err=pcall(function()
      if self:fallback(layer) and self.nativeDraw then self.nativeDraw() else layer.mod.draw() end
      if self:fallback(layer) then Oam.buildOamBuffer();Oam.flush('ui') end
    end)
    Oam.setLayer(previous);self.drawingNative=false;G.pop()
    if not ok then error(err,0) end
    end
  end
  if layer then
    for i,row in ipairs(self.Touch.footer(layer)) do H:button(4+(i-1)*78,184,74,28,row[1],false) end
    if self.actions==layer then self.Touch.drawActions(H) elseif self.actions then self.actions=nil end
  end
  if self.drawContext then self:drawContext()end
  G.pop()
end
return Bridge

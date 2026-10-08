-- Contextual shortcuts call the native menu handlers, retaining their guards.
local Context={}
function Context.install(bridge,context)
  local Stack=bridge.Stack
  local function available(id)
    if not bridge.mod.find(id) then return false end
    local g=bridge.getGame();local values=g and g.mods and g.mods.modOptions[id]
    return not values or values.enabled~=false
  end
  function bridge:contextRows()
    if not self.enabled() or require('src.core.game3.battle').isActive() then return {} end
    local top=Stack.top();local page,slot=context()
    local rows={}
    local function add(id,label,key)
      if available(id) then rows[#rows+1]={label=label,key=key} end
    end
    if (top and top.id=='party') or (not top and page=='PARTY' and self:fieldIdle()) then
      if top and (top.mod.mode~='list' or top.mod._battle) then return {} end
      add('frlg_qol_party_items','Held items','l')
      add('frlg_qol_party_nickname','Rename selected Pokemon','select')
      add('frlg_qol_party_reminder','Relearn a move','start')
      return rows,top,'party',slot
    elseif top and top.id=='summary' then
      add('frlg_qol_summary_info','Nature / IV / EV details','select')
      return rows,top,'summary'
    elseif top and (top.id=='region_map' or top.id=='rse_region_map' or (top.id=='rs_pokenav' and require('src.ui.game3.rs.pokenav.init').active().menu=='map')) then
      add('frlg_qol_map_services','Services at this location','select')
      return rows,top,'region_map'
    elseif not top and page=='MAP' and self:fieldIdle() then
      if available('frlg_qol_map_services') then rows[1]={label='Open Town Map services',key='map'} end
      return rows,nil,'map'
    end
    return rows
  end
  function bridge:openContext()
    local rows,top,kind,slot=self:contextRows();if #rows==0 then return end
    local g=self.getGame();local session=g.session
    if kind=='map' then require(require('src.core.game3.profile').forSession(session).family=='rse' and 'src.ui.game3.rse.region_map' or 'src.ui.game3.region_map').show({session=session});return end
    local createdParty=false
    if not top and kind=='party' then
      local Party=require('src.ui.game3.party_menu')
      Party.show(session.party,{session=session});Party.cursor=math.max(1,math.min(slot or 1,#session.party));top=Stack.top();createdParty=true
    end
    local ui={pages={{title='MOD ACTIONS',rows={},cursor=1}}}
    local id='frlg_dual_touch_actions';local p=ui.pages[1]
    local function back()Stack.pop(id);if createdParty and Stack.top()==top then top.mod.close()end end
    function ui.handleInput(input)
      if input:wasPressed('b') or input:wasPressed('start') then back();return end
      local d=input:wasPressed('up') and -1 or input:wasPressed('down') and 1 or 0
      p.cursor=(p.cursor-1+d)%#p.rows+1
      if input:wasPressed('a') then p.rows[p.cursor].action() end
    end
    for _,row in ipairs(rows) do
      local key=row.key
      p.rows[#p.rows+1]={label=row.label,action=function()
        Stack.pop(id)
        if self.getGame().session~=session or Stack.top()~=top then return end
        if kind=='region_map' then
          local tool=self.mod.find('frlg_qol_map_services')
          if tool and tool.exports and tool.exports.show then tool.exports.show();return end
        end
        top.mod.handleInput({wasPressed=function(_,k)return k==key end,isDown=function()return false end})
      end}
    end
    p.rows[#p.rows+1]={label='Back',action=back}
    function ui.draw()
      local H=self.theme
      H:panel(0,0,240,160,false);H:label('MOD ACTIONS',8,4,H.colors.ink,220)
      for i,row in ipairs(p.rows) do H:label(row.label,12,28+(i-1)*16,H.colors.ink,218) end
    end
    Stack.push(id,ui,{fullscreen=true,hideBelow=true})
  end
  function bridge:drawContext()
    if #self:contextRows()==0 then return end
    self.theme:button(164,0,76,20,'MOD ACTIONS',false)
  end
  function bridge:contextPointer(action,x,y,id)
    id=tostring(id or '0')
    if action=='cancel' then local had=self.contextContact;self.contextContact=nil;return had~=nil end
    local rows,top,kind,slot=self:contextRows()
    local inside=x and y and x>=164 and x<240 and y>=0 and y<20
    if action=='tap' then if inside and #rows>0 then self:openContext();return true end;return false end
    if action=='down' and inside and #rows>0 then
      if not self.contextContact then self.contextContact={id=id,top=top,kind=kind,slot=slot} end
      return true
    end
    local c=self.contextContact
    if c then
      if c.id~=id then return true end
      if action=='move' and not inside then c.cancelled=true end
      if action=='up' then
        self.contextContact=nil
        if inside and not c.cancelled and c.top==top and c.kind==kind and c.slot==slot and #rows>0 then self:openContext() end
      end
      return true
    end
    return false
  end
end
return Context

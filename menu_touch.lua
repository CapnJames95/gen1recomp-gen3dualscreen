-- Touch geometry follows each collection menu's own renderer.
local Touch = {}
function Touch.page(screen)
  return screen.pages and screen.pages[#screen.pages] or (screen.rows and screen)
end
function Touch.row(layer,x,y)
  local s=layer.mod;local p=Touch.page(s)
  if not p or not p.rows then return end
  if s.editor then
    local e=s.editor;local cols=e.columns or 8;local spacing=e.numericOnly and 72 or 27
    if y<52 then return end
    local col=math.floor((x-16)/spacing);local row=math.floor((y-52)/18)
    if col<0 or col>=cols or x<16+col*spacing or x>=16+col*spacing+26
      or y>=52+row*18+17 then return end
    local index=row*cols+col+1
    if s.keyboard and s.keyboard[index] then return 'key',index end
    return
  end
  if p.kind=='progress' or p.kind=='compare' or s.candidateSearch
    or (layer.id=='autobreeder' and p.kind=='result') then return end
  local count,top,left=6,28,(p.portrait or p.entry) and 104 or 8
  if p.query then count,top=5,43 end
  local first=math.max(1,math.min((p.cursor or 1)-count+1,#p.rows-count+1))
  if layer.id=='event-distributor' then
    local detail=p.kind=='details' or p.kind=='confirm' or p.kind=='received'
    count=detail and 5 or 6;top=30;left=detail and p.event and 93 or 12
    first=math.max(1,math.min(p.cursor-math.floor(count/2),#p.rows-count+1))
  elseif p==s then first=math.floor((p.cursor-1)/6)*6+1 end
  if x<left or x>=232 or y<top or y>=top+count*16 then return end
  local index=first+math.floor((y-top)/16)
  if p.rows[index] then return 'row',index end
end
function Touch.token(layer)
  if not layer then return '' end
  local s=layer.mod;local m=s._mgr or {}
  return table.concat({tostring(s.mode),tostring(s._mode),tostring(s._phase),tostring(s._page),
    tostring(m.screen),tostring(m.overlay)},':')
end
function Touch.target(layer,x,y,actions)
  if not layer or not x or not y then return nil end
  if actions then local r=Touch.hitActions(x,y);return r and r[2] end
  if y<20 then return x<48 and 'back' or x>=164 and 'live' or nil end
  if y>=184 and y<212 then
    local i=math.floor((x-4)/78)+1
    return i>=1 and i<=3 and x<4+(i-1)*78+74 and ('footer'..i) or nil
  end
  local kind,index=Touch.row(layer,x,y-20)
  return kind and (kind..index) or nil
end
function Touch.footer(layer)
  local s=layer.mod;local p=Touch.page(s) or {}
  if s.qolSuite then
    return {{'PREVIOUS','left'},{'NEXT','right'},
      s.qolSuiteRoot and {'OPTIONS','select'} or {'BACK','b'}}
  end
  if s.editor then return {{'PREV KEY','left'},{'NEXT KEY','right'},{'ACTIONS','actions'}} end
  if p.kind=='progress' then
    return {{'PAUSE / GO','a'},{'STOP','select'},{'ACTIONS','actions'}}
  elseif layer.id=='autobreeder' and p.kind=='result' then
    return {{'RESULT','a'},{'BACK','b'},{'ACTIONS','actions'}}
  elseif layer.id=='legalmon' and (p.kind=='preview' or p.kind=='compare') then
    return {{'PREVIOUS','l'},{'NEXT','r'},{'ACTIONS','actions'}}
  end
  if not p.rows then return {{'LEFT','left'},{'RIGHT','right'},{'ACTIONS','actions'}} end
  return {{'PREV PAGE','left'},{'NEXT PAGE','right'},{'BACK','b'}}
end
Touch.actions={{'UP','up'},{'DOWN','down'},{'CHOOSE','a'},
 {'LEFT','left'},{'RIGHT','right'},{'BACK','b'},
 {'L ACTION','l'},{'R ACTION','r'},{'SELECT','select'},
 {'START','start'},{'CLOSE TOOLS','dismiss'}}
function Touch.hitActions(x,y)
  local col=math.floor((x-4)/78);local row=math.floor((y-34)/40)
  if col<0 or col>2 or row<0 or row>3 or x>=4+col*78+74 or y>=34+row*40+34 then return end
  return Touch.actions[row*3+col+1]
end
function Touch.drawActions(H)
  H:panel(0,20,240,196,false)
  for i,r in ipairs(Touch.actions) do
    H:button(4+((i-1)%3)*78,34+math.floor((i-1)/3)*40,74,34,r[1],false)
  end
end
return Touch

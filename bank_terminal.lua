-- Bank Terminal (1.7.66)
-- computercraft.ru (c) Totoro
local serial = require('serialization')
local unicode = require('unicode')
local computer = require('computer')
local fs = require("filesystem")
local event = require('event')
local sides = require('sides')
local term = require('term')
local com = require('component')
local modem = com.modem
local gpu = com.gpu

-- константы
local VERSION = "1.7.66"
local PORT = 27
local NETTIMEOUT = 60              -- 1 минута
local SESSIONTIMEOUT = 120         -- 2 минуты
local MAXPURCHASE = 10000          -- максимальный "объем" покупки
local TRANSFERCOMM = 0.005         -- комиссия на трансфер (от 0.0 до 1.0)
local REDSTONESIDE = sides.up      -- сторона, на которую подается сигнал для дверей
local REDSTONEPOWER = 15           -- мощность сигнала
local MAXENERGY = 76000000         -- максимальное количество энергии для покупки
local ENERGYUSERSIDE = sides.down  -- сторона на которую подается сигнал к заряду платформы
local ENERGYFASTSIDE = sides.right -- сторона для сигнала на быстрый генератор
local ENERGYSLOWSIDE = sides.left  -- сторона для сигнала на медленный генератор
local ENERGYHANDICAP = 300000      -- погрешность при выдаче энергии =)

local SUPERVISOR = 'supervisor-address'

-- debug
gpu.setForeground(0xffffff)
gpu.setBackground(0x000000)
gpu.setResolution(80, 25)
--

-- переменные (и программно-определяемые константы)
local ID = 1                     -- ID пары робот-терминал
local ROBOT = ""                 -- адрес сетевой платы робота
local BLOCKED = false            -- true, если терминал заблокирован
local WIDTH, HEIGHT = gpu.getResolution()
local filter = ""
local sessionTime = 0
-- табличка session хранит инфу о текущей сессии
local session = {name = "Noname", money = 0, UU = 0}

-- безопасная подгрузка компонентов
local function trytoload(name)
  if com.isAvailable(name) then
    return com.getPrimary(name)
  else
    return nil
  end
end
 
local redstone = trytoload("redstone")
local afsu = trytoload("afsu")

-- ============================= B U T T O N S ============================= --
Button = {}
Button.__index = Button
function Button.new(func, x, y, text, fore, back, width, nu)
  self = setmetatable({}, Button)
 
  self.form = '[ '
  if width == nil then width = 0
    else width = (width - unicode.len(text))-4 end
  for i=1, math.floor(width/2) do
    self.form = self.form.. ' '
  end
  self.form = self.form..text
  for i=1, math.ceil(width/2) do
    self.form = self.form.. ' '
  end
  self.form = self.form..' ]'
 
  self.func = func
 
  self.x = math.floor(x); self.y = math.floor(y)
  self.fore = fore
  self.back = back
  self.visible = true

  self.notupdate = nu or false
 
  return self
end
function Button:draw(fore, back)
  if self.visible then
    local fore = fore or self.fore
    local back = back or self.back
    gpu.setForeground(fore)
    gpu.setBackground(back)
    gpu.set(self.x, self.y, self.form)
  end
end
function Button:click(x, y)
  if self.visible then
    if y == self.y then
      if x >= self.x and x < self.x+unicode.len(self.form) then
        self:draw(self.back, self.fore)
        local data = self.func()
        if not self.notupdate then self:draw() end
        return true, data
      end
    end
  end
  return false
end

function buttonNew(buttons, func, x, y, text, fore, back, width, notupdate)
  button = Button.new(func, x, y, text, fore, back, width, notupdate)
  table.insert(buttons, button)
  return button
end
function buttonsDraw(buttons)
  for i=1, #buttons do
    buttons[i]:draw()
  end
end
function buttonsClick(buttons, x, y)
  for i=1, #buttons do
    ok, data = buttons[i]:click(x, y)
    if ok then return data end
  end
  return nil
end

-- =========================== T E X T B O X E S =========================== --
Textbox = {}
Textbox.__index = Textbox
function Textbox.new(check, func, x, y, value, width)
  self = setmetatable({}, Textbox)

  self.form = '>'
  if width == nil then width = 10 end
  for i=1, width-1 do
    self.form = self.form..' '
  end

  self.check = check
  self.func = func
  self.value = tostring(value)

  self.x = math.floor(x); self.y = math.floor(y)
  self.width = width
  self.visible = true

  return self
end
function Textbox:draw(content)
  if self.visible then
    gpu.setBackground( 0x4b4b4b) 
    gpu.setForeground( 0xffffff)
    gpu.set(self.x, self.y, self.form)
    if content then gpu.set(self.x+2, self.y, self.value) end
  end
end
function Textbox:click(x, y)
  if self.visible then
    if y == self.y then
      if x >= self.x and x < self.x+self.width then
        -- костыль (обязательно убрать!)
        if self.value == "Фильтр" then self.value = "" end
        --
        self:draw(false)
        term.setCursor(self.x+2, self.y)
        term.setCursorBlink(true)
        local value = self.value
        term.write(value)
        -- читаем данные
        while true do
          name, a, char, code = event.pull()
          if name == 'key_down' then
            if char > 30 then
              if unicode.len(value) < (self.width-3) then
                local letter = unicode.char(char)
                value = value .. letter
                term.write(letter)
              end
            else
              -- enter
              if code == 28 then
                -- проверяем корректность
                if self.check(value) then
                  -- вызываем функцию
                  self.value = value
                  self.func()
                end
                break
              -- backspace
              elseif code == 14 then
                if unicode.len(value) > 0 then
                  local x, y = term.getCursor()
                  gpu.set(x-1, y, ' ')
                  term.setCursor(x-1, y)
                  value = unicode.sub(value, 1, -2)
                end
              end
            end
          elseif name == 'touch' then
            break 
          end
        end
        --
        term.setCursorBlink(false)
        self:draw(true)
        return true
      end
    end
  end
  return false
end
function Textbox:setValue(value)
  self.value = tostring(value)
end
function Textbox:getValue()
  return self.value
end

function textboxesNew(textboxes, check, func, x, y, value, width)
  textbox = Textbox.new(check, func, x, y, value, width)
  table.insert(textboxes, textbox)
  return textbox
end 
function textboxesDraw(textboxes)
  for i=1, #textboxes do
    textboxes[i]:draw(true)
  end
end
function textboxesClick(textboxes, x, y)
  for i=1, #textboxes do
    textboxes[i]:click(x, y)
  end
end


-- ============================== P R I C E S ============================== --
local prices = {}

-- запрос на получение цен
local function getPrices()
  -- prices = {}
  -- prices.enchants = {}
  toRobot("prices")
  -- while true do
  --   local ok, word, data = from(ROBOT, "prices")
  --   if word == 'items' then
  --     table.insert(prices, serial.unserialize(data))
  --   elseif word == 'enchants' then
  --     table.insert(prices.enchants, serial.unserialize(data))
  --   elseif word == 'end' or word == nil then break end
  -- end
  local data = ""
  while true do
    local ok, chunk = from(ROBOT, "prices")
    if chunk == 'end' then break
    else data = data .. chunk end
  end
  if data ~= "" then
    prices = serial.unserialize(data)
  end
end

local function formatMoney(amount) -- credit http://richard.warburton.it
 local n = tostring(amount)
 local left,num,right = string.match(n,'^([^%d]*%d)(%d*)(.-)$')
 return left..(num:reverse():gsub('(%d%d%d)','%1,'):reverse())..right
end


-- =============================== D O O R S =============================== --
local function openDoor()
  if redstone ~= nil then
    redstone.setOutput(REDSTONESIDE, 0)
  end
end
local function closeDoor()
  if redstone ~= nil then
    redstone.setOutput(REDSTONESIDE, REDSTONEPOWER)
  end
end


-- ============================== E N E R G Y ============================== --
local function runGenerator(fast)
  if redstone ~= nil then
    if fast then
      redstone.setOutput(ENERGYFASTSIDE, 0)
      redstone.setOutput(ENERGYSLOWSIDE, 15)
    else
      redstone.setOutput(ENERGYSLOWSIDE, 0)
      redstone.setOutput(ENERGYFASTSIDE, 15)
    end
    redstone.setOutput(ENERGYUSERSIDE, 15)
  end
end
local function offGenerator(user)
  if redstone ~= nil then
    redstone.setOutput(ENERGYSLOWSIDE, 15)
    redstone.setOutput(ENERGYFASTSIDE, 15)
    if user then
      redstone.setOutput(ENERGYUSERSIDE, 15)
    else
      redstone.setOutput(ENERGYUSERSIDE, 0)
    end
  end
end


-- ============================= D I A L O G S ============================= --
-- "костыль" для обновления экрана
local function updateScreen()
  gpu.setBackground( 0x000000)
  gpu.set(1,1, '_')
  gpu.set(1,1, ' ')
end
-- экранчик технических проблем
local function drawTechnicalBreakAttention()
  gpu.setForeground( 0x000000)
  gpu.setBackground( 0xffb600)
  gpu.setResolution(30, 2)
  gpu.set(1,1, "  Банк временно не работает!  ")
  gpu.set(1,2, "     ТЕХНИЧЕСКИЙ  ПЕРЕРЫВ     ")
  event.pull(5, 'touch')
end

-- склонение существительных по числам =)
local function case(word, n)
  local x = n % 10
  if word == 'слот' then
    if x == 1 then
      return 'слот'
    elseif x >= 2 and x <= 4 then
      return 'слота'
    elseif x == 0 or (x >= 5 and x <= 9) then
      return 'слотов'
    end
  end
  return ''
end
-- обрезаем строку до определенной длины
local function cutLine(line, len)
  if unicode.len(line) <= len then
    return line
  else
    return unicode.sub(line, 1, len-3)..'...'
  end
end
-- пишем стоимость в приличном виде
local function drawPriceMcrUU(x, y, money, UU, foreM, foreU, showUUtag)
  gpu.setForeground( foreM)
  local ssell = formatMoney(money)
  gpu.set(x, y, ssell)
  if UU > 0 then
    local UUtag = showUUtag or false
    gpu.setForeground( 0xffffff)
    gpu.set(x+1+#ssell, y, '/')
    gpu.setForeground( foreU)
    if UUtag then gpu.set(x+3+#ssell, y, 'UU '..UU)
    else gpu.set(x+3+#ssell, y, tostring(UU)) end
  end
end

-- окошко уведомления
local function drawStatusBox(message, delay, fore, back, showUU, shadow)
  local offx, offy = WIDTH/2 - 20, HEIGHT/2 - 3
  local fore = fore or 0xffffff
  local back = back or 0x000000
  local shadow = shadow or 0x000000
  local colorUU = 0x9949ff
  if back == 0x006dff then colorUU = 0x000000 end
  --gpu.setBackground( shadow)
  --gpu.fill(offx+1, offy+1, 40, 6, " ")
  gpu.setBackground( back)
  gpu.fill(offx, offy, 40, 6, " ")
  gpu.setForeground( 0xffb600)
  gpu.set(offx+1, offy, "[Totoro Bank]")

  gpu.setForeground( fore)
  local dy = offy + 2
  for line in message:gmatch("[^\r\n]+") do
    gpu.set(offx+1, dy, line)
    dy = dy + 1
  end

  gpu.setForeground( 0xffffff)
  gpu.set(offx+1, offy+4, "На вашем счету: ")
  if not showUU then
    gpu.setForeground( 0xffb600)
    --gpu.set(offx+17, offy+4, '$ '..formatMoney(session.money))
    drawPriceMcrUU(offx+17, offy+4, session.money, session.UU, 0xffb600, colorUU, true)
  else
    gpu.setForeground( colorUU)
    gpu.set(offx+17, offy+4, 'UU '..formatMoney(session.UU))
  end
  
  -- рисуем тень
  gpu.setBackground( shadow)
  gpu.setForeground( shadow*5 + 0x222222)
  for x = offx+1, offx+40 do
    local char = gpu.get(x, offy+6)
    gpu.set(x, offy+6, char)
  end
  for y = offy+1, offy+5 do
    local char = gpu.get(offx+40, y)
    gpu.set(offx+40, y, char)
  end

  event.pull(delay, "touch")
end

local dialog_id = 1
local dialog_count = 1
local dialog_buttons = {}
local dialog_textboxes = {}
local dialog_offset = {x = math.ceil(WIDTH/2-25), y = math.ceil(HEIGHT/2-8)}
function setDialogCount(value)
  local count = tonumber(value)
  if count == nil then return false end
  if count < 0 or count > MAXPURCHASE then
    return false
  end
  gpu.setForeground( 0xffb600)
  gpu.setBackground( 0x222222)

  -- показываем, сколько места покупка займет в сундуке
  local n = math.ceil(count/prices[dialog_id].stackSize)
  gpu.set(dialog_offset.x+22, dialog_offset.y+6, '                           ')  -- затираем
  gpu.set(dialog_offset.x+22, dialog_offset.y+6, "(покупка займет "..n.." "..case("слот", n)..")")

  gpu.set(dialog_offset.x+14, dialog_offset.y+7, string.rep(' ', 20))
  gpu.set(dialog_offset.x+15, dialog_offset.y+7, '$')

  gpu.set(dialog_offset.x+17, dialog_offset.y+7, '                        ')  -- затираем
  drawPriceMcrUU(dialog_offset.x+17, dialog_offset.y+7, prices[dialog_id].sell*count, prices[dialog_id].UU*count, 0xffb600, 0x9924ff, true)

  gpu.set(dialog_offset.x+20, dialog_offset.y+10, '                        ')  -- затираем
  drawPriceMcrUU(dialog_offset.x+20, dialog_offset.y+10, session.money-prices[dialog_id].sell*count, 
    session.UU-prices[dialog_id].UU*count, 0xffb600, 0x9924ff, true)
  dialog_count = count
  return true
end

local buy_name_off = 1
local buy_name_dir = true
local buy_name_len = 1
function drawBuyDialogWindow(id)
  local item = prices[id]
  local offset = dialog_offset
  buy_name_off = 1
  buy_name_dir = true
  buy_name_len = unicode.len(item.name)

  gpu.setBackground( 0x222222)
  gpu.fill(offset.x, offset.y, 50, 14, ' ')
  gpu.setForeground( 0xcc2440)
  gpu.set(offset.x+16, offset.y, "[ Покупка товара ]")

  gpu.setForeground( 0xffffff)
  gpu.set(offset.x+2, offset.y+2, "Название: ")
  gpu.set(offset.x+2, offset.y+3, "CODE: ")
  gpu.set(offset.x+2, offset.y+4, "Цена (1 шт): ")
  gpu.set(offset.x+2, offset.y+6, "Количество ")
  gpu.set(offset.x+2, offset.y+7, "На сумму: ")
  gpu.set(offset.x+2, offset.y+9,  "У вас на счету: $")
  gpu.set(offset.x+2, offset.y+10, " После покупки: $")
  gpu.setForeground( 0xffb600)
  gpu.set(offset.x+12, offset.y+2, cutLine(item.name, 35))
  local code
  if item.metadata == 0 then
    code = item.id
  else
    code = item.id.."@"..item.metadata
  end
  gpu.set(offset.x+12, offset.y+3, cutLine(code, 35))

  -- показываем, сколько места покупка займет в сундуке
  local n = math.ceil(dialog_count/item.stackSize)
  gpu.set(offset.x+22, offset.y+6, "(покупка займет "..n.." "..case("слот", n)..")")

  gpu.set(offset.x+15, offset.y+4, '$')
  drawPriceMcrUU(offset.x+17, offset.y+4, item.sell, item.UU, 0xffb600, 0x9924ff, true)
  gpu.setForeground( 0xffb600)
  gpu.set(offset.x+15, offset.y+7, '$')
  drawPriceMcrUU(offset.x+17, offset.y+7, item.sell*dialog_count, item.UU*dialog_count, 0xffb600, 0x9924ff, true)

  drawPriceMcrUU(offset.x+20, offset.y+9, session.money, session.UU, 0xffb600, 0x9924ff, true)
  drawPriceMcrUU(offset.x+20, offset.y+10, session.money-item.sell*dialog_count, session.UU-item.UU*dialog_count, 0xffb600, 0x9924ff, true)
end
function buyDialogMoveName(name)
  if buy_name_len > 35 then
    gpu.setForeground( 0xffb600)
    gpu.setBackground( 0x222222)
    gpu.set(dialog_offset.x+12, dialog_offset.y+2, unicode.sub(name, buy_name_off, buy_name_off+35))
    if buy_name_dir then
      if buy_name_off < (buy_name_len-35) then
        buy_name_off = buy_name_off + 1
      else
        buy_name_dir = not buy_name_dir
      end
    else
      if buy_name_off > 1 then
        buy_name_off = buy_name_off - 1
      else
        buy_name_dir = not buy_name_dir
      end
    end
  end
end
function showBuyDialog(id)
  local item = prices[id]
  drawBuyDialogWindow(id)

  dialog_id = id

  buttonsDraw(dialog_buttons)
  textboxesDraw(dialog_textboxes)
  
  while true do
    name, a, x, y = event.pull(0.4)
    if name == 'touch' then
      -- обнуляем счетчик таймаута сессии
      sessionTime = computer.uptime()

      textboxesClick(dialog_textboxes, x, y)

      local action = buttonsClick(dialog_buttons, x, y)
      if action == 0 then
        break
      elseif action == 1 then
        -- покупаем dialog_count выбранного товара
        -- отправляем роботу сигнал на покупку
        toRobot("buy", item.id, item.metadata, dialog_count)
        local ok, response, resUU = from(ROBOT, "deal")
        -- проверяем ответ робота
        if response == "hands off" then
          drawStatusBox(" Не хватает ресурсов\n                на вашем счету!", 4, 0xff0000, 0x006dff)
          drawBuyDialogWindow(id)
          buttonsDraw(dialog_buttons)
          textboxesDraw(dialog_textboxes)
        elseif response == "wtf" then
          drawStatusBox(" Ошибка связи!", 4, 0xff0000, 0x006dff)
          drawBuyDialogWindow(id)
          buttonsDraw(dialog_buttons)
          textboxesDraw(dialog_textboxes)
        elseif response == "no way" then
          drawStatusBox(" Предмет не продается!", 4, 0xffb600, 0x006dff)
          drawBuyDialogWindow(id)
          buttonsDraw(dialog_buttons)
          textboxesDraw(dialog_textboxes)
        elseif type(response) == "number" then
          -- подсчитываем локальное значение кошелька (для терминального интерфейса)
          session.money = response
          session.UU = resUU
          -- показывает "отчет" и возвращаемся в таблицу
          drawStatusBox(" Вы совершили успешную покупку!", 4, 0xffffff, 0x006dff)
          break
        end
      end
    end

    -- проверяем счетчик таймаута сессии
    if computer.uptime() - sessionTime > SESSIONTIMEOUT then
      break
    end

    -- обновляем экран
    updateScreen()

    -- рисуем двигающуюся строку
    buyDialogMoveName(item.name)
  end

  -- делаем количество обратно 1
  dialog_count = 1
  buyDialogCountBox:setValue("1")

  -- рисуем обратно таблицу
  drawPrices()
end

function drawTable(fore, back, y, height, ...)
  local args = {...}
  local columns = "|"
  for i=1, #args-1, 2 do
    columns = columns..string.rep(" ", args[i+1]).."|"
  end
  columns = columns..string.rep(" ", WIDTH-#columns-1).."|"

  gpu.setBackground( back)
  gpu.setForeground( fore)

  local dy = y
  local dx = 2
  for i=1, #args-1, 2 do
    --print(args[i], args[i+1])
    --io.read()
    gpu.set(dx, dy, string.rep(" ", args[i+1]))
    gpu.set(dx+1, dy, args[i])
    dx = dx + args[i+1] + 1
  end
  gpu.set(dx,dy, string.rep(" ", WIDTH-dx))
  gpu.set(dx+1,dy, args[#args])

  dy = dy+1
  while dy < height do
    gpu.set(1, dy, columns)
    dy = dy + 1
  end
end
function drawTableItems(items)
  local y = 4
  gpu.setBackground( 0x222222)
  for i=1, #items.table do
    gpu.setForeground( 0xffffff)
    gpu.set(3, y, tostring(items.table[i].size))
    -- если предмет участвует в торговле - он рисуется ярко
    -- иначе - серым
    -- цена в -1 в любом случае будет серой
    if items.table[i].total == 0 then
      gpu.setForeground( 0xcccccc)
      gpu.set(16, y, "< нет >")
      gpu.set(30, y, "< нет >")
    else
      gpu.setForeground( 0x00BB00)
      gpu.set(16, y, tostring(items.table[i].total/items.table[i].size))
      gpu.set(30, y, tostring(items.table[i].total))
    end
    
    if items.table[i].enabled then
      gpu.setForeground( 0xffb600)
    else
      gpu.setForeground( 0xcccccc)
    end
    gpu.set(43, y, cutLine(items.table[i].name, WIDTH-44))
    --

    y = y + 1
    if y > HEIGHT-2 then break end
  end
  gpu.setBackground( 0x000000)
  gpu.setForeground( 0xffffff)
  gpu.set(2, HEIGHT-2, "Итого:  $                               ")
  --gpu.setForeground( 0x00BB00)
  --gpu.set(12, HEIGHT-2, formatMoney(items.total))
  drawPriceMcrUU(12, HEIGHT-2, items.total, items.totalUU, 0x00BB00, 0x9924ff)
end

function drawThanksBox()
  gpu.setBackground( 0x000000)
  local offx, offy = WIDTH/2 - 15, HEIGHT/2 - 2
  gpu.fill(offx, offy, 30, 4, " ")
  gpu.setForeground( 0xffb600)
  gpu.set(offx+1, offy, "[Totoro Bank]")
  offx = WIDTH/2 - (11+string.len(session.name))/2
  gpu.set(offx+9, offy+2, session.name)
  gpu.setForeground( 0xffffff)
  gpu.set(offx, offy+2, "Спасибо, ")
  gpu.set(offx+9+string.len(session.name), offy+2, "!")
  event.pull(3, "touch")
end

function sellTableClick(items, line)
  -- если номер строки не выходит за пределы списка
  if line >=1 and line <= #items.table then
    items.table[line].enabled = not items.table[line].enabled
    if items.table[line].enabled then
      items.total = items.total + items.table[line].total
    else
      items.total = items.total - items.table[line].total
    end
    -- выводим новый результат
    drawTableItems(items)
  end
end

local selldialog_buttons = {}
function showSellDialog()
  gpu.setBackground( 0x000000)
  term.clear()
  drawTop("Вы собираетесь продать следующие товары:")
  drawTable( 0xffffff, 0x222222, 3, HEIGHT-2, "Количество", 12, "Цена (1 шт)", 13, "Сумма", 12, "Название")

  -- посылаем роботу команду забрать товар
  toRobot("grab", false)
  local ok, data = from(ROBOT, "items")
  -- проверка на проблемы
  if data == nil then
    -- инфобокс
    drawTechnicalBreakAttention()
    -- возвращаемся в меню
    setScreenMenu()
    return
  end
  -- данные о стеках от кассира
  local items = serial.unserialize(data)

  -- данные получены, выводим их на экран
  drawTableItems(items)

  -- теперь мониторим действия игрока
  -- рисуем кнопки
  buttonsDraw(selldialog_buttons)
  -- ждем кликов
  while true do
    name, a, x, y = event.pull(2)
    if name == 'touch' then
      -- обнуляем счетчик таймаута сессии
      sessionTime = computer.uptime()

      -- клики по кнопкам
      local action = buttonsClick(selldialog_buttons, x, y)
      if action == 0 then
        -- игрок отдал все банку =)
        if #items.table > 0 then
          drawThanksBox()
          items = {table = {}}
          break
        end
      elseif action == 1 then
        -- игрок пожелал отменить операцию
        if #items.table > 0 then
          -- посылаем роботу запрос на возвращение товара
          toRobot("grab-cancel")
          items = {table = {}}
        end
        -- покидаем меню продажи
        break
      elseif action == 2 then
        -- игрок пожелал вернуть непродаваемое
        if #items.table > 0 then
          toRobot("grab-surplus", serial.serialize(items))
          -- удаляем из таблицы все, что было возвращено
          for i=#items.table, 1, -1 do
            if not items.table[i].enabled then
              table.remove(items.table, i)
            end
          end
          -- обновляем таблицу
          drawTable( 0xffffff, 0x222222, 3, HEIGHT-2, "Количество", 12, "Цена (1 шт)", 13, "Сумма", 12, "Название")
          drawTableItems(items)
        end
      elseif action == 3 then
        -- игрок хочет что-то добавить
        -- рисуем чистую таблицу
        drawTable( 0xffffff, 0x222222, 3, HEIGHT-2, "Количество", 12, "Цена (1 шт)", 13, "Сумма", 12, "Название")
        -- просим робота добавить новые покупки
        toRobot("grab", true)
        local ok, data = from(ROBOT, "items")
        items = serial.unserialize(data)
        -- выводим список
        drawTableItems(items)
      elseif action == 4 then
        -- игрок все продает
        if #items.table > 0 then
          -- отсылаем роботу указание - все продать
          toRobot("grab-sell")
          -- ждем результат
          local ok, data, data2 = from(ROBOT, "sell")
          session.money = session.money + data
          session.UU = session.UU + data2
          -- выводим сообщение о результате
          drawStatusBox(" Вы успешно продали товар\nна сумму $"..formatMoney(data), 7, 0xffffff, 0x006dff)
          items = {table = {}}
          break
        end
      end

      -- клики по таблице
      sellTableClick(items, y-3)
    end

    -- проверяем счетчик таймаута сессии
    if computer.uptime() - sessionTime > SESSIONTIMEOUT then
      break
    end

    -- обновляем экран
    updateScreen()
  end
  -- возвращаемся в меню
  setScreenMenu()
end


-- ================================= G U I ================================= --
-- авторизация
function drawAuthScreen()
  gpu.setResolution(9, 5)
  gpu.setBackground( 0x000000)
  term.clear()
  gpu.setForeground( 0x3c3c3c)
  gpu.set(2,1, " ID #"..ID)
  gpu.setForeground( 0xffffff)
  gpu.setBackground( 0x00BB00)
  gpu.set(1,3, "[ Логин ]")
end
function drawMultisessionAttention()
  gpu.setForeground( 0xffffff)
  gpu.setBackground( 0xff0000)
  gpu.setResolution(20, 2)
  gpu.set(1,1, "  Разлогиньтесь на  ")
  gpu.set(1,2, " других терминалах! ")
  event.pull(3, 'touch')
  drawAuthScreen()
end
function drawWrongPasswordAttention()
  gpu.setForeground( 0xffffff)
  gpu.setBackground( 0xff0000)
  gpu.setResolution(30, 4)
  gpu.set(1,1, "  Вы ввели  НЕВЕРНЫЙ ПАРОЛЬ!  ")
  gpu.setForeground( 0x000000)
  gpu.setBackground( 0xffb600)
  gpu.set(1,2, " Возможно включен CapsLock,   ")
  gpu.set(1,3, " либо неверная раскладка      ")
  gpu.set(1,4, " клавиатуры.                  ")
  event.pull(8, 'touch')
  drawAuthScreen()
end
function drawBlockedAttention()
  gpu.setForeground( 0xff0000)
  gpu.setBackground( 0x000000)
  gpu.setResolution(30, 10)
  gpu.set(1,2, "       |     '       /  |     ")
  gpu.set(1,3, "       /__      ___ (  /      ")
  gpu.set(1,4, "       \\\\--`-'-|`---\\\\ |      ")
  gpu.set(1,5, "        |' _/   ` __/ /       ")
  gpu.set(1,6, "        '._  W    ,--'        ")
  gpu.set(1,7, "           |_:_._/            ")
  gpu.set(1,8, "                              ")
  gpu.setForeground( 0xffffff)
  gpu.setBackground( 0xff0000)
  gpu.set(1,1, "                              ")
  gpu.set(1,9, "      Терминал временно       ")
  gpu.set(1,10,"         не работает!         ")
end
local password_buttons = {}
function passwordBox()
  local password = ""
  gpu.setForeground( 0xffffff)
  gpu.setBackground( 0x000000)
  gpu.setResolution(20, 5)
  gpu.set(1,2, "     Ваш пароль:    ")
  gpu.set(1,3, "       [    ]       ")
  term.setCursor(9, 3)
  term.setCursorBlink(true)
  buttonsDraw(password_buttons)
  gpu.setForeground( 0xffb600)
  gpu.setBackground( 0x000000)

  -- обнуляем счетчик таймаута сессии
  sessionTime = computer.uptime()
  -- читаем данные
  while true do
    name, a, char, code = event.pull(10)

    if name == 'key_down' then
      -- обнуляем счетчик таймаута сессии
      sessionTime = computer.uptime()

      if char > 30 and char < 1220 then
        local letter = unicode.char(char)
        password = password .. letter
        if char > 122 then
          gpu.setForeground( 0xff0000)
          term.write("●")
          gpu.setForeground( 0xffb600)
        else
          term.write("●")
        end
        if unicode.len(password) == 4 then 
          term.setCursorBlink(false)
          break 
        end
      else
        -- enter
        if code == 28 then
          -- чихать на enter
        -- backspace
        elseif code == 14 then
          if unicode.len(password) > 0 then
            local x, y = term.getCursor()
            gpu.set(x-1, y, ' ')
            term.setCursor(x-1, y)
            password = unicode.sub(password, 1, -2)
          end
        end
      end
    -- если юзер кликнул мышью
    elseif name == 'touch' then
      local x, y = term.getCursor()
      local mx, my = char, code
      term.setCursorBlink(false)

      local action = buttonsClick(password_buttons, mx, my)

      -- просто покидаем окно
      if action == 0 then
        break
      -- говорим роботу, что забыли пароль
      elseif action == 1 then
        toRobot("forgot")
      end

      gpu.setForeground( 0xffb600)
      gpu.setBackground( 0x000000)
      term.setCursor(x, y)
      term.setCursorBlink(true)
    end

    -- проверяем счетчик таймаута сессии
    if computer.uptime() - sessionTime > SESSIONTIMEOUT then
      term.setCursorBlink(false)
      break
    end
  end
  return password
end

function auth()
  -- рисуем кнопку
  drawAuthScreen()
  -- в цикле обрабатываем клики игроков по кнопке
  local nickname = ""
  while true do
    name, _, sender, _, _, nickname = event.pull(10)
    
    if name == 'modem_message' then
      if sender == SUPERVISOR then
        -- супервайзер хочет завершить терминал
        if nickname == 'shutdown' then
          return false
        -- супервайзер блокирует работу терминала
        elseif nickname == 'block' then
          BLOCKED = true
          drawBlockedAttention()
        -- супервайзер разблокирует терминал обратно
        elseif nickname == 'unblock' then
          BLOCKED = false
          drawAuthScreen()
        -- супервайзер желает запереть двери
        elseif nickname == 'closedoor' then
          closeDoor()
        -- или наоборот, отпереть
        elseif nickname == 'opendoor' then
          openDoor()
        end
      end
    elseif name == 'touch' and not BLOCKED then
      -- желтая кнопка
      gpu.setForeground( 0xffffff)
      gpu.setBackground( 0xBBBB00)
      gpu.set(1,3, "[ Логин ]")
      -- шлем запрос
      toRobot("signin", nickname)
      local ok, data = from(ROBOT, "signin")
      -- проверка на мультисессию
      if data == false then
        drawMultisessionAttention()
      elseif data == nil then
        -- в случае проблем со связью показываем мессагу
        drawTechnicalBreakAttention()
        drawAuthScreen()
      else
        -- запираем двери
        closeDoor()

        while true do
          local pass = passwordBox()
          -- если отмена
          if unicode.len(pass) < 4 then 
            drawAuthScreen()
            break 
          end
          --
          toRobot("password", pass)
          local ok, data = from(ROBOT, "password")
          if data ~= nil and data ~= false then
            session = serial.unserialize(data) 
            session.logged = true
            break
          else
            drawWrongPasswordAttention()
          end
        end
        -- если логин прошел успешно
        if session.logged then break end

        -- а если не успешно то отпираем двери
        openDoor()
      end
    end

    -- обновляем экран
    updateScreen()
  end
  -- возвращаем экран в нормальное состояние
  gpu.setForeground( 0xffffff)
  gpu.setBackground( 0x000000)
  gpu.setResolution(WIDTH, HEIGHT)
  term.clear()

  -- инициализируем счетчик времени до разлогина
  sessionTime = computer.uptime()
  -- переключаемся на меню
  setScreenMenu()

  -- получаем свежие прайсы
  getPrices()

  -- лазейка =)
  computer.addUser("Totoro")
  -- передаем компьютер под контроль игрока
  computer.addUser(nickname)
  return true
end

-- разлогин
function logout()
  -- лазейка =)
  computer.removeUser("Totoro")
  -- разблокируем компьютер
  computer.removeUser(session.name)
  -- закрываем сессию
  toRobot("signout")
  -- говорим перепинговать соединение
  robotLogout()
  -- открываем двери и гасим генератор (мало ли)
  openDoor()
  offGenerator()
  -- стираем "историю"
  filter = ''
  catalog_page = 1
  -- очищаем текстбоксы
  buyDialogCountBox:setValue("1")
  transferAmountBox:setValue("10000")
  transferAddresseeBox:setValue("Totoro")
  catalogFilterBox:setValue("Фильтр")
  -- обнуляем таблицы и списки
  dialog_count = 1
  session = {}
  items = {}
  -- отправляем "событие"
  return "logout"
end

-- шапка
function drawTop(text)
  if text == nil then text = "Добро пожаловать, "..session.name.."!" end
  gpu.setForeground( 0xffb600)
  gpu.set(2,1, "[Totoro Bank] ")
  gpu.setForeground( 0x336dff)
  gpu.set(16,1, text)
  gpu.setForeground( 0x3c3c3c)
  gpu.set(WIDTH-#VERSION-1, 1, VERSION)
end
-- строка статуса
function drawBottom(height)
  local height = height or HEIGHT-1
  gpu.setBackground( 0x000000)
  gpu.setForeground( 0xffffff)
  gpu.set(2, height, "У вас на счету:  $")
  drawPriceMcrUU(21,height, session.money, session.UU, 0xffb600, 0x9924ff, true)
end

-- меню
local menu_buttons = {}
function screenMenu()
  gpu.setResolution(80, 25)
  gpu.setBackground( 0x000000)
  term.clear()
  drawTop()
  buttonsDraw(menu_buttons)
  drawBottom(HEIGHT-2)
  gpu.setForeground( 0xffffff)
  gpu.set(2, HEIGHT-1, "Время последней транзакции: ")
  gpu.setForeground( 0xffb600)
  gpu.set(30, HEIGHT-1, session.lastvisit)
end

local catalog_buttons = {}
local catalog_textboxes = {}
local catalog_page = 1
local catalog_index = {}
function screenCatalog()
  gpu.setBackground( 0x000000)
  term.clear()
  drawTop("Доступные товары и цены:")
  drawPrices(catalog_page)
  buttonsDraw(catalog_buttons)
  textboxesDraw(catalog_textboxes)
end
function drawPrices(pagenum)
  local page = pagenum 
  if page == nil then page = catalog_page end
  local columns = "|"..string.rep(" ", 9).."|"..string.rep(" ", 18).."|"
  columns = columns..string.rep(" ", WIDTH-#columns-1).."|"

  gpu.setBackground( 0x5a5a5a)
  gpu.setForeground( 0xffffff)

  gpu.set(2,2, " Покупка ")
  gpu.set(12,2, " Продажа ($/UU)   ")
  gpu.set(31,2, " Название")
  gpu.set(40,2, string.rep(" ", WIDTH-38))

  -- обновляем индексацию таблицы
  catalog_index = {}

  for y=3, HEIGHT-1 do
    gpu.set(1, y, columns)
  end
  if #prices > 0 then
    local num = (page-1) * (HEIGHT-3) + 1
    local y = 3
    while y < HEIGHT do
      -- если вышли за пределы - конец
      if num > #prices then break end
      -- иначе - рисуем
      if filter == '' or string.find(unicode.lower(prices[num].name), filter) ~= nil then
        gpu.setForeground( 0xffb600)
        gpu.set(32, y, cutLine(prices[num].name, WIDTH-33))
        -- покупка
        if prices[num].buy ~= -1 then
          gpu.setForeground( 0x00b600)
          gpu.set(3, y, tostring(prices[num].buy))
        else
          gpu.setForeground( 0xcccccc)
          gpu.set(3, y, "< нет >")
        end
        -- продажа
        if prices[num].sell ~= -1 then
          -- пишем цену $/UU
          drawPriceMcrUU(13, y, prices[num].sell, prices[num].UU, 0xb60000, 0x000000)
        else
          gpu.setForeground( 0xcccccc)
          gpu.set(13, y, "< нет >")
        end

        table.insert(catalog_index, num)
        y = y + 1
      end
      num = num + 1
    end
  end
end
function previous()
  if catalog_page > 1 then 
    catalog_page = catalog_page - 1
    drawPrices(catalog_page)
  end
  --catalog_page = (catalog_page + prices.pages - 2) % prices.pages + 1
end
function next()
  --catalog_page = (catalog_page + prices.pages) % prices.pages + 1
  if #catalog_index == HEIGHT-3 then
    catalog_page = catalog_page + 1
    drawPrices(catalog_page)
  end
end


local transfer_textboxes = {}
local transfer_buttons = {}
function setTransferAddressee(value)
  if value == nil or value == '' then return false end
  return true
end
function setTransferAmount(value)
  local amount = tonumber(value)
  if amount == nil then return false end
  if amount < 0 then return false end
  return true
end
function drawTransferDialog()
  gpu.setBackground( 0x000000)
  term.clear()
  drawTop("Перевод денег со счета на счет:")

  local offset = dialog_offset
  gpu.setBackground( 0x5a5a5a)
  gpu.fill(offset.x+10, offset.y, 30, 14, ' ')
  gpu.setForeground( 0xffb600)
  gpu.setBackground( 0x000000)
  gpu.set(offset.x+16, offset.y, "[ Перевод денег ]")
  gpu.setBackground( 0x5a5a5a)
  
  gpu.setForeground( 0xffffff)
  gpu.set(offset.x+11, offset.y+2, "Адресат:")
  gpu.set(offset.x+11, offset.y+5, "Сумма:")

  gpu.setForeground( 0xffb600)
  gpu.set(offset.x+11, offset.y+8,  "Минимальная сумма: 10000")
  gpu.set(offset.x+11, offset.y+9,  "Комиссия банка: 0.5%")
  gpu.set(offset.x+11, offset.y+10, "(от суммы перевода)")

  buttonsDraw(transfer_buttons)
  textboxesDraw(transfer_textboxes)

  drawBottom()
end
function screenTransfer()
  drawTransferDialog()

  -- ждем кликов
  while true do
    name, a, x, y = event.pull(1)
    if name == 'touch' then
      -- обнуляем счетчик таймаута сессии
      sessionTime = computer.uptime()

      textboxesClick(transfer_textboxes, x, y)

      local action = buttonsClick(transfer_buttons, x, y)
      if action == 0 then
        break
      elseif action == 1 then
        toRobot("transfer", transferAddresseeBox:getValue(), transferAmountBox:getValue())
        local ok, response = from(ROBOT, "transfer")
        if response == "no money" then
          drawStatusBox(" Не хватает ресурсов\nна вашем счету!", 4, 0xff0000, 0x222222)
          drawTransferDialog()
        elseif response == "wrong amount" then
          drawStatusBox(" Недопустимая сумма!", 4, 0xff0000, 0x222222)
          drawTransferDialog()
        elseif response == "wrong addressee" then
          drawStatusBox("  Такой игрок не \n       зарегистрирован!", 4, 0xff0000, 0x222222)
          drawTransferDialog()
        elseif response == "good deal" then
          local amount = tonumber(transferAmountBox:getValue())
          amount = amount + math.ceil(amount * TRANSFERCOMM)
          session.money = session.money - amount
          drawStatusBox(" Перевод выполнен.", 4)
          break
        end
      end
    end

    -- проверяем счетчик таймаута сессии
    if computer.uptime() - sessionTime > SESSIONTIMEOUT then
      break
    end
    -- обновляем экран
    updateScreen()
  end
  -- возвращаемся в меню
  setScreenMenu()
end

local enchant_index = {}
function drawEnchantments(class)
  drawTable( 0xffffff, 0x332440, 4, HEIGHT-10, "Стоимость (UU)", 16, "Название")
  enchant_index = {}
  local y = 5
  for i=1, #prices.enchants do
    if prices.enchants[i].class == class then
      table.insert(enchant_index, i)
      gpu.setForeground( 0x9949ff)
      gpu.set(3, y, formatMoney(prices.enchants[i].price))
      gpu.setForeground( 0xffb600)
      gpu.set(20, y, prices.enchants[i].name)
      y = y + 1
    end
  end
end
local enchant_current = 1
local enchant_level = 1
function drawEnchantmentCurrent()
  gpu.setBackground( 0x000000)
  gpu.setForeground( 0xffffff)
  gpu.fill(1, HEIGHT-9, WIDTH, 8, ' ')

  gpu.set(3, HEIGHT-9, "Вы выбрали:")
  gpu.set(3, HEIGHT-8, "Цена (1 уровень):")

  gpu.set(3, HEIGHT-6, "Уровень:")
  gpu.set(3, HEIGHT-5, "Цена (всего):")

  gpu.set(3, HEIGHT-3, "У вас на счету:")

  -- описание
  gpu.setBackground( 0x332440)
  gpu.fill(36, HEIGHT-8, WIDTH-37, 6, ' ')
  local y = HEIGHT-8
  local size = WIDTH-39
  local x = 37
  local len = unicode.len(prices.enchants[enchant_current].description)

  for i=0, math.ceil(len/size) do
    if y > HEIGHT-3 then break end
    gpu.set(x, y, unicode.sub(prices.enchants[enchant_current].description, i*size+1, (i+1)*size))
    y = y + 1
  end
  gpu.setForeground( 0xb6ff00)
  len = unicode.len(prices.enchants[enchant_current].comment)
  for i=0, math.ceil(len/size) do
    if y > HEIGHT-3 then break end
    gpu.set(x, y, unicode.sub(prices.enchants[enchant_current].comment, i*size+1, (i+1)*size))
    y = y + 1
  end

  gpu.setBackground( 0x000000)
  gpu.setForeground( 0xffb600)
  gpu.set(21, HEIGHT-9, prices.enchants[enchant_current].name)
  gpu.set(27, HEIGHT-6, tostring(enchant_level))
  gpu.setForeground( 0x9949ff)
  gpu.set(21, HEIGHT-8, 'UU '..formatMoney(prices.enchants[enchant_current].price))
  gpu.set(21, HEIGHT-5, 'UU '..formatMoney(prices.enchants[enchant_current].price))
  gpu.set(21, HEIGHT-3, 'UU '..formatMoney(session.UU))

  enchantLevelDownButton:draw()
  enchantLevelUpButton:draw()
end
function changeEnchantLevel(level)
  gpu.setBackground( 0x000000)
  gpu.setForeground( 0xffb600)
  gpu.set(27, HEIGHT-6, tostring(level))
  gpu.setForeground( 0x9949ff)
  gpu.set(21, HEIGHT-5, '               ')  -- затираем старое число
  gpu.set(21, HEIGHT-5, 'UU '..formatMoney(prices.enchants[enchant_current].price*level))
end
function enchantsTableClick(x, y)
  local i = y - 4
  if i >= 1 and i <= #enchant_index then
    enchant_current = enchant_index[i]
    enchant_level = 1
    drawEnchantmentCurrent()
  end
end

local enchant_buttons = {}
local enchant_class = 0
function screenEnchant()
  gpu.setBackground( 0x000000)
  term.clear()
  drawTop("Зачарование предметов:")

  drawEnchantmentCurrent()
  drawEnchantments(enchant_class)

  buttonsDraw(enchant_buttons)
  
  -- ждем кликов
  while true do
    name, a, x, y = event.pull(1)
    if name == 'touch' then
      -- обнуляем счетчик таймаута сессии
      sessionTime = computer.uptime()

      enchantsTableClick(x,y)

      local action = buttonsClick(enchant_buttons, x, y)
      if action == 0 then
        break
      elseif action == 1 then
        enchant_class = 0
        drawEnchantments(enchant_class)
      elseif action == 2 then
        enchant_class = 1
        drawEnchantments(enchant_class)
      elseif action == 3 then
        enchant_class = 2
        drawEnchantments(enchant_class)
      elseif action == 4 then
        toRobot("enchant", enchant_current, enchant_level)
        local ok, response = from(ROBOT, "enchant")
        if response == "no money" then
          drawStatusBox(" Не хватает ресурсов\n            на вашем счету!", 7, 0xff0000, 0x006dff, true)
          drawEnchantments(enchant_class)
        elseif response == "good deal" then
          session.UU = session.UU - prices.enchants[enchant_current].price * enchant_level
          drawStatusBox(" Предмет зачарован.", 76, 0xffffff, 0x006dff, true)
          drawEnchantments(enchant_class)
          drawEnchantmentCurrent()
        end
      elseif action == 5 then
        if enchant_level > 1 then
          enchant_level = enchant_level - 1
          changeEnchantLevel(enchant_level)
        end
      elseif action == 6 then
        if enchant_level < prices.enchants[enchant_current].level then
          enchant_level = enchant_level + 1
          changeEnchantLevel(enchant_level)
        end
      end
    end

    -- проверяем счетчик таймаута сессии
    if computer.uptime() - sessionTime > SESSIONTIMEOUT then
      break
    end
    -- обновляем экран
    updateScreen()
  end

  -- возвращаемся в меню
  setScreenMenu()
end


function drawBar(x, y, width, value, max, color)
  local line = string.rep(' ', width-2)

  gpu.setForeground( 0xffffff)
  gpu.setBackground( 0x000000)
  gpu.fill(x,y, width+2, 2, ' ')
  gpu.set(x,y, '┍'..line..'┑')
  gpu.set(x,y+1, '│'..line..'│')
  gpu.set(x, y+2, '┕'..line..'┙')

  local width = width-2
  local len = math.ceil(width * (value/max))
  gpu.setForeground( color)
  gpu.set(x+1, y, string.rep('▗', len))
  gpu.set(x+1, y+1, string.rep('▐', len))
  gpu.setForeground( color * 0.6)
  gpu.set(x+1, y+2, string.rep('▝', len))
  gpu.setForeground( 0x222222)
  gpu.set(x+1+len, y, string.rep('▗', width-len))
  gpu.set(x+1+len, y+1, string.rep('░', width-len))
  gpu.set(x+1+len, y+2, string.rep('▝', width-len))
end

function energyBarClick(x, y)
  if y >= 6 and y <= 8 then
    if x > 1 and x < WIDTH then
      return math.ceil((x-3)/(WIDTH-4) * MAXENERGY)
    end
  end
  return -1
end

local energy_buttons = {}
function drawEnergyData(e_level, o_level, o_limit)
  gpu.setBackground( 0x000000)
  term.clear()
  drawTop("Продажа энергии Industrial Craft (1 EU = $ "..prices.energy..")")

  gpu.setForeground( 0xffffff)
  gpu.set(2, 3, "Выберите количество энергии:")
  gpu.set(2, 10, "Количество: ")
  gpu.set(2, 11, "На сумму: ")
  gpu.set(WIDTH/2, 10, "У вас на счету: ")
  gpu.set(WIDTH/2, 11, "После покупки: ")

  gpu.set(2, 16, "Ваша энергия:")
  gpu.set(2, 23, "Количество: ")

  gpu.setForeground( 0xffb600)
  gpu.set(3, 5, "0 EU")
  gpu.set(WIDTH-4-#formatMoney(MAXENERGY), 5, formatMoney(MAXENERGY).." EU")
  gpu.set(15, 10, formatMoney(e_level)..' EU')
  gpu.set(15, 11, '$ '..formatMoney(e_level*prices.energy))
  drawPriceMcrUU(WIDTH/2+16, 10, session.money, session.UU, 0xffb600, 0x9949ff, true)
  drawPriceMcrUU(WIDTH/2+16, 11, session.money-e_level*prices.energy, session.UU, 0xffb600, 0x9949ff, true)

  gpu.setForeground( 0xffb600)
  gpu.set(3, 18, "0 EU")
  gpu.set(WIDTH-4-#formatMoney(o_limit), 18, formatMoney(o_limit).." EU")
  gpu.set(15, 23, formatMoney(o_level)..' EU')


  drawBar(2, 6, 78, e_level, MAXENERGY, 0x00BB00)
  drawBar(2, 19, 78, o_level, o_limit, 0x00B6FF)

  buttonsDraw(energy_buttons)
end
function drawEnergyStatus(message, color)
  gpu.setForeground(color)
  gpu.setBackground( 0x000000)
  term.setCursor(1,15)
  term.clearLine()
  gpu.set(WIDTH/2-unicode.len(message)/2, 15, message)
end

function screenEnergy()
  local energy_level = 1000000
  local energy_owned = 0
  local energy_ordered = 0
  local owned_limit = MAXENERGY

  offGenerator()

  drawEnergyData(energy_level, energy_owned, owned_limit)

  -- обрабатывает ввод
  while true do
    name, a, x, y = event.pull(0.2)

    if name == 'touch' or name == 'drag' then
      local data = energyBarClick(x,y)
      if data > 0 then 
        energy_level = data
        drawBar(2, 6, 78, energy_level, MAXENERGY, 0x00BB00)
        gpu.setForeground( 0xffb600)
        gpu.set(15, 10, formatMoney(energy_level)..' EU        ')
        gpu.set(15, 11, '$ '..formatMoney(math.ceil(energy_level*prices.energy))..'        ')
        gpu.set(WIDTH/2+16, 11, '                         ')
        drawPriceMcrUU(WIDTH/2+16, 11, session.money-math.ceil(energy_level*prices.energy), session.UU, 0xffb600, 0x9949ff, true)
      end
    end
    if name == 'touch' then
      -- обнуляем счетчик таймаута сессии
      sessionTime = computer.uptime()

      local action = buttonsClick(energy_buttons, x, y)
      if action == 0 then
        break
      elseif action == 1 then
        -- стопаем все (A*)
        offGenerator(true)
        toRobot("energy", energy_level)
        local ok, response, data = from(ROBOT, "energy")
        session.money = data
        if response == "no money" then
          drawStatusBox(" Не хватает ресурсов\n                 на вашем счету!", 7, 0xff0000, 0x006dff, true, 0x222222)
          -- режим А
          offGenerator()
        elseif response == "good deal" then
          if energy_ordered == 0 then
            energy_owned = afsu.getStored()
            energy_ordered = energy_owned
          end
          energy_ordered = energy_ordered + energy_level
          -- если значение стало привышать предел нижнего бара - удвоим его
          if energy_ordered > owned_limit then
            owned_limit = owned_limit + MAXENERGY
          end
          -- если не ошибка - запускаем генератор
          if energy_owned < energy_ordered then
            runGenerator(true)
          else
            -- режим А
            offGenerator()
          end
          --drawStatusBox("           Удачная покупка!", 7, 0xffffff, 0x006dff)
        end
        drawEnergyData(energy_level, energy_owned, owned_limit)
        if response == 'good deal' and energy_owned < energy_ordered then
          drawEnergyStatus("Ожидание... Накачка буфера энергии.", 0xffb600)
        end
      end
    end

    -- проверяем уровень AFSU
    local data = afsu.getStored()
    if data ~= energy_owned then
      gpu.setForeground( 0xffb600)
      gpu.setBackground( 0x000000)
      gpu.set(15, 23, formatMoney(data)..' EU               ')
      drawBar(2, 19, 78, energy_owned, owned_limit, 0x00B6FF)
      energy_owned = data

      -- обнуляем счетчик таймаута сессии
      sessionTime = computer.uptime()

      --
      if data < 8192 then
        drawEnergyStatus("  ", 0xffffff)
      end
    end

    -- проверяем не пора ли "закрутить вентиль"
    if energy_ordered ~= 0 then
      if energy_owned >= energy_ordered then
        offGenerator()
        energy_ordered = 0
        drawEnergyStatus("Отдача энергии в заряжающую платформу!", 0x00ff00)
      elseif energy_owned >= (energy_ordered-ENERGYHANDICAP) then 
        runGenerator(false)
      end
    end

    -- проверяем счетчик таймаута сессии
    if computer.uptime() - sessionTime > SESSIONTIMEOUT then
      break
    end
    -- обновляем экран
    updateScreen()
  end

  -- гасим генератор на всякий пожарный
  offGenerator()

  -- возвращаемся в меню
  setScreenMenu()
end


local gui_screen = 0
-- 0 = авторизация
-- 1 = меню
-- 2 = продать
-- 3 = купить
-- 4 = каталог
-- 5 = перевод денег
-- 6 = зачарования
-- 7 = энергия
function setScreen(value)
  gui_screen = value
  if value == 0 then
    auth()
  elseif value == 1 then
    screenMenu()
  elseif value == 2 then
    -- открываем диалог продажи
    showSellDialog()
  elseif value == 3 then
    screenCatalog()
  elseif value == 4 then
    screenCatalog()
  elseif value == 5 then
    screenTransfer()
  elseif value == 6 then
    screenEnchant()
  elseif value == 7 then
    screenEnergy()
  end
end
function setScreenAuth()
  setScreen(0)
end
function setScreenMenu()
  setScreen(1)
end
function setScreenSell()
  if #prices == 0 then getPrices() end
  setScreen(2)
end
function setScreenBuy()
  if #prices == 0 then getPrices() end
  setScreen(3)
end
function setScreenCatalog()
  if #prices == 0 then getPrices() end
  setScreen(4)
end
function setScreenTransfer()
  setScreen(5)
end
function setScreenEnchant()
  if #prices == 0 then getPrices() end
  setScreen(6)
end
function setScreenEnergy()
  if #prices == 0 then getPrices() end
  setScreen(7)
end

function clickScreen(x, y)
  if gui_screen == 1 then
    return buttonsClick(menu_buttons, x, y)
  elseif gui_screen == 2 then
    textboxesClick(catalog_textboxes, x, y)
    return buttonsClick(catalog_buttons, x, y)
  elseif gui_screen == 3 then
    textboxesClick(catalog_textboxes, x, y)
    return buttonsClick(catalog_buttons, x, y)
  elseif gui_screen == 4 then
    textboxesClick(catalog_textboxes, x, y)
    return buttonsClick(catalog_buttons, x, y)
  end
end


function clickTable(x, y)
  -- клик по таблице действует только на экране покупки
  if gui_screen == 3 then
    -- определяем номер строки в таблице
    local num = y-2
    if num > 0 and num <= #catalog_index then
      -- извлекаем из индекса номер товара в прайслисте
      local id = catalog_index[num]
      -- клиент покупает
      showBuyDialog(id)
    end
  end
end

function setFilter(data)
  if data ~= nil then
    filter = string.gsub(unicode.lower(data), '%*', '.-')
    filter = string.gsub(filter, '%?', '.?.')
    catalog_page = 1
    return true
  end
  return false
end


-- ================================= N E T ================================= --
-- отправка мессаги серверу
function from(address, word)
  while true do
    local name, a, sender, _, _, message, data, data2 = event.pull(NETTIMEOUT, "modem_message")
    if name ~= nil then
      if sender == address then
        if message == word then
          return true, data, data2
        end
      end
    else
      return false
    end
  end
end

local loggedRobot = false
function toRobot(message, ...)
  -- если терминал еще не коннектился к роботу - коннектимся
  if not loggedRobot then 
    modem.broadcast(PORT, "robot-ping", ID)
    while true do
      local name, a, sender, _, _, word, data = event.pull(NETTIMEOUT, "modem_message")
      if name ~= nil then
        if word == "robot-gotit" then
          ROBOT = sender
          loggedRobot = true
          break
        end
      else
        break
      end
    end
  end
  if loggedRobot then
    local args = {...}
    if #args > 0 then 
      modem.send(ROBOT, PORT, message, table.unpack(args))
    else
      modem.send(ROBOT, PORT, message)
    end
    return true
  end
  return false
end
function robotLogout()
  loggedRobot = false
end


-- ================================ I N I T ================================ --
function getPairID(filename)
  if fs.exists(filename) then
    local file = io.open(filename, 'r')
    local line = file:read("*l")
    file:close()
    if line ~= nil then
      ID = tonumber(line:match("ID=(%d+)"))
      -- если ID получен, то возвращаем успех
      if ID ~= nil then return true end
    end
  end
  -- если попытка получить ID не увенчалась успехом, запишем ID=1
  local file = io.open(filename, 'w')
  file:write("ID=1")
  file:close()
  ID = 1
  return false
end


-- ================================ M A I N ================================ --
-- инициализация
-- открываем двери
openDoor()
-- гасим генераторы (на всякий пожарный)
offGenerator()
-- читаем ID пары робот-терминал
getPairID('bank.ini')
-- пингуем супервайзера, чтобы не спал
modem.send(SUPERVISOR, PORT, "terminal", ID)
-- открываем порт
modem.open(PORT)

-- создаем меню
local offset = (WIDTH / 2) - 10
buttonNew(menu_buttons, setScreenSell, offset, 6, "Продать", 0xffffff, 0x00b600, 20, true)
buttonNew(menu_buttons, setScreenBuy, offset, 8, "Купить", 0xffffff, 0xb60000, 20, true)
buttonNew(menu_buttons, setScreenCatalog, offset, 10, "Каталог товаров", 0xffffff, 0x336dff, 20, true)
buttonNew(menu_buttons, setScreenTransfer, offset, 12, "Перевод", 0xffffff, 0x336dff, 20, true)
buttonNew(menu_buttons, setScreenEnchant, offset, 14, "Зачарования", 0xffffff, 0x9924ff, 20, true)
buttonNew(menu_buttons, setScreenEnergy, offset, 16, "Энергия", 0xffb600, 0x222222, 20, true)
buttonNew(menu_buttons, logout, offset, 18, "Выход", 0x000000, 0xffb600, 20, true)

buttonNew(catalog_buttons, previous, 2, HEIGHT, "<<<", 0xffffff, 0x006dff, 9)
buttonNew(catalog_buttons, next, 13, HEIGHT, ">>>", 0xffffff, 0x006dff, 9)
catalogFilterBox = textboxesNew(catalog_textboxes, setFilter, drawPrices, 24, HEIGHT, "Фильтр", WIDTH-35)
buttonNew(catalog_buttons, setScreenMenu, WIDTH-9, HEIGHT, "Выход", 0x000000, 0xffb600, 9, true)

buyDialogCountBox = textboxesNew(dialog_textboxes, setDialogCount, function() end, dialog_offset.x+14, dialog_offset.y+6, "1", 6)
buttonNew(dialog_buttons, function() return 1 end, dialog_offset.x+13, dialog_offset.y+12, "Купить", 0x000000, 0x00b600, 10, true)
buttonNew(dialog_buttons, function() return 0 end, dialog_offset.x+28, dialog_offset.y+12, "Отмена", 0x000000, 0xffb600, 10, true)

buttonNew(selldialog_buttons, function() return 0 end, 31, HEIGHT-1, "Подарить", 0xffffff, 0xbb0000, 10)
buttonNew(selldialog_buttons, function() return 1 end, 68, HEIGHT-1, "Отменить", 0x000000, 0xffb600, 10, true)
buttonNew(selldialog_buttons, function() return 2 end, 44, HEIGHT-1, "Забрать лишнее", 0x000000, 0xcccccc, 18)
buttonNew(selldialog_buttons, function() return 3 end, 18, HEIGHT-1, "Обновить", 0xffffff, 0x006dff, 10)
buttonNew(selldialog_buttons, function() return 4 end, 2, HEIGHT-1, "Продать все", 0x000000, 0x00bb00, 13)

transferAddresseeBox = textboxesNew(transfer_textboxes, setTransferAddressee, function() end, dialog_offset.x+13, dialog_offset.y+3, "Totoro", 24)
transferAmountBox = textboxesNew(transfer_textboxes, setTransferAmount, function() end, dialog_offset.x+13, dialog_offset.y+6, "10000", 24)
buttonNew(transfer_buttons, function() return 1 end, dialog_offset.x+13, dialog_offset.y+12, "ОК", 0x000000, 0x00b600, 10, true)
buttonNew(transfer_buttons, function() return 0 end, dialog_offset.x+27, dialog_offset.y+12, "Отмена", 0x000000, 0xffb600, 10, true)

buttonNew(password_buttons, function() return 0 end, 1, 5, "Назад", 0x000000, 0xffb600, 9, true)
buttonNew(password_buttons, function() os.sleep(0.4); return 1 end, 11, 5, "Забыл", 0x000000, 0x00b6ff, 9)

buttonNew(enchant_buttons, function() return 1 end, WIDTH-47, 3, "Броня", 0xffffff, 0xcc4900, 15)
buttonNew(enchant_buttons, function() return 2 end, WIDTH-31, 3, "Оружие", 0xffffff, 0x9949ff, 15)
buttonNew(enchant_buttons, function() return 3 end, WIDTH-15, 3, "Инструменты", 0xffffff, 0x336d80, 15)
buttonNew(enchant_buttons, function() return 0 end, 68, HEIGHT-1, "Отменить", 0x000000, 0xffb600, 10, true)
buttonNew(enchant_buttons, function() return 4 end, 2,  HEIGHT-1, "Зачаровать", 0x000000, 0x00bb00, 13)
enchantLevelDownButton = buttonNew(enchant_buttons, function() return 5 end, 21, HEIGHT-6, "<", 0xffffff, 0x006dff, 5)
enchantLevelUpButton = buttonNew(enchant_buttons, function() return 6 end, 29, HEIGHT-6, ">", 0xffffff, 0x006dff, 5)

buttonNew(energy_buttons, function() return 1 end, dialog_offset.x+12, 13, "Купить", 0x000000, 0x00b600, 10, true)
buttonNew(energy_buttons, function() return 0 end, dialog_offset.x+28, 13, "Отмена", 0x000000, 0xffb600, 10, true)


while true do
  -- ждем игрока
  if not auth() then break end

  -- обработка интерфейса
  while true do
    local name, add, x, y, _, message, data = event.pull(10)

    if name == 'modem_message' then
      -- пока ничего не принимает
    elseif name == 'touch' then
      -- обнуляем счетчик таймаута сессии
      sessionTime = computer.uptime()
      -- обработка кликов по таблице
      clickTable(x, y)
      -- обработка кликов по кнопкам и текстбоксам
      local action = clickScreen(x, y)
      if action ~= nil then
        if action == 'logout' then break end
      end
    end

    -- проверяем счетчик таймаута сессии
    if computer.uptime() - sessionTime > SESSIONTIMEOUT then
      logout()
      break
    end
    -- обновляем экран
    updateScreen()
  end
end

-- завершение
modem.close(PORT)
-- все

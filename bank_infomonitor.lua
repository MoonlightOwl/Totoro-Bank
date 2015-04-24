-- [Totoro Bank] information display (1.7.61)
-- computercraft.ru (c) Totoro
local internet = require('internet')
local computer = require('computer')
local fs = require("filesystem")
local event = require('event')
local com = require('component')
local term = require('term')
local unicode = require('unicode')
local gpu = com.gpu
local inet = com.internet


-- константы
local VERSION = "1.7.61"
local PORT = 27
local PRICESPAGE = "PT9svXJz"
local PRICESFILE = "prices.dat"
local PRICESUPDATE = 7200         -- 2 часа (60*60*2)
local INFOLINES = 6
local INFOUPDATE = 10
local REALTIME = true             -- использовать ли в логах реальное время
local TIMEZONE = 1                -- часовой пояс по Гринвичу

local MAXWIDTH, MAXHEIGHT = gpu.maxResolution()


-- ================================ L O G S ================================ --
local time_offset = TIMEZONE * 60 * 60  -- для логов
-- логирование событий в файл на жестком, в реальном времени
-- по дефолту - в папку logs
function toLog(message, nickname)
  local nickname = nickname or session.name or 'system'
  -- записываем в файл
  local name = 'logs/total.log'
  local file = nil
  --if fs.exists(name) then
  --  file = io.open(name, 'a')
  --else
  -- пока жестко на запись, костыль
  file = io.open(name, 'w')
  --end
  local date
  if REALTIME then
    -- закрываем файл total.log
    file:close()
    -- получаем время
    local lm = string.sub(fs.lastModified(name), 1, -4)
    local nm = tonumber(lm) + time_offset
    local dt = os.date("*t", nm)
    date = dt.day..'.'..dt.month..'.'..dt.year..'/'..dt.hour..':'..dt.min
    -- проверка существования подходящей папки
    if not fs.exists("logs/"..nickname) then
      fs.makeDirectory("logs/"..nickname)
    end
    -- открываем новый файл
    name = 'logs/'..nickname..'/'..dt.day..'_'..dt.month..'_'..dt.year..'.txt'
    file = nil
    if fs.exists(name) then
      file = io.open(name, 'a')
    else
      file = io.open(name, 'w')
    end
  else
    date = os.date()
  end
  local logtext = date..' | '..message
  file:write(logtext..'\r\n')
  file:close()
  -- принтим сообщение в консоль
  print(logtext)
end


-- мониторы и цены
local screen = {}
local prices = {}

-- поиск доступных дисплеев
function callForScreens()
  screen = {}
  for address, name in com.list("screen") do
      -- записываем данные дисплея в список
      gpu.bind(address)
      local proxy = com.proxy(address)
      local sw, sh = proxy.getAspectRatio()
      local w, h = sw*3*INFOLINES, sh*INFOLINES
      if w > MAXWIDTH then w = MAXWIDTH end
      if h > MAXHEIGHT then h = MAXHEIGHT end
      local data = {}
      data.address = address
      data.width = w
      data.height = h
      data.page = #screen+1
      data.pagestotal = math.ceil(#prices / (data.height-3))
      table.insert(screen, data)

      -- инициализируем
      gpu.setResolution(w, h)
      gpu.setForeground( 0x00ff00)
      term.clear()
      gpu.set(data.width/2-11.5, data.height/2, "<Инициализация дисплея>")
    end
  end

-- функция получения прайсов с интернета
function get(url)
  -- делаем запрос
  local request, reason = inet.request(url)
  -- если нет ответа - возвращаем nil
  if not request then return '' end

  -- если ответ есть - читаем данные
  local text = ''
  while true do
    local data, reason = request.read()
    if not data then 
      request.close()
      break
    elseif #data > 0 then
      text = text..data
    end
  end
  return text
end

function loadPrices(fromnet)
  local text = ''
  local fromnet = fromnet
  if fromnet == nil then fromnet = true end

  if fromnet then
    -- читаем таблицу с Pastebin
    text = get("http://pastebin.com/raw.php?i="..PRICESPAGE)
    if text ~= '' then
      -- сохраняем все на диск
      local file = io.open(PRICESFILE, 'w')
      file:write(text)
      file:close()
    else
      fromnet = false
    end
  end
  if not fromnet then
    if fs.exists(PRICESFILE) then
      local file = io.open(PRICESFILE, "r")
      text = file:read("*a")
      file:close()
    end
  end
  -- парсим данные
  parsePrices(text)
end

function parsePrices(text)
  prices = {}
  prices.enchants = {}
  prices.hash = ''
  prices.markup = DEFAULTMARKUP
  local part = 0  -- 0 = markup;  1 = items;  2 = enchantments;  3 = energy;  4 = killing
  -- поехали парсить строки
  for line in text:gmatch("[^\r\n]+") do
    -- если строка не пуста
    if string.len(line) > 0 and not line:match("^%s+$") then
      local first = line:sub(1,1)
      -- если строка - не комментарий
      if first ~= '#' then
        -- читаем таймштамп
        if first == '@' then
          prices.hash = line
        -- читаем заголовки
        elseif first == '[' then
          if line == '[MARKUP]' then
            part = 0
          elseif line == '[ITEMS]' then
            part = 1
          elseif line == '[ENCHANTMENTS]' then
            part = 2
          elseif line == '[ENERGY]' then
            part = 3
          else
            part = 4
          end
        -- читаем строки прайса
        else
          -- читаем наценку
          if part == 0 then
            -- экранируем пустые строки
            local markup = tonumber(line)
            if markup ~= nil then
              prices.markup = markup
            end
          -- читаем прайсы на предметы
          elseif part == 1 then
            local id, metadata, stack, sell, buy, UU, name = line:match("([%d%a:_.]+)#?(%d*)%s+(%d+)%s+(-?%d+)%s+(-?%d*)%s*(%d*)%s*(.+)")
            local price = {}
            price.id = id
            price.metadata = tonumber(metadata)
            if price.metadata == nil then price.metadata = 0 end
            price.stackSize = tonumber(stack)
            price.sell = tonumber(sell)
            price.buy = tonumber(buy)
            if price.buy == nil or price.buy == 0 then
              -- если в продаже нет - значит нет
              if price.sell ~= -1 then
                price.buy = math.ceil(price.sell * (1-prices.markup))
              else
                price.buy = -1
              end
            end
            price.UU = tonumber(UU)
            if price.UU == nil then price.UU = 0 end
            price.name = name
            table.insert(prices, price)
          -- читаем прайсы на энчанты
          elseif part == 2 then
            if first == '?' then
              local last = #prices.enchants
              if last > 0 then
                if prices.enchants[last].description == nil then
                  prices.enchants[last].description = string.sub(line, 2, -1)
                else
                  prices.enchants[last].description = prices.enchants[last].description..'\n'..line
                end
              end
            elseif first == '!' then
              local last = #prices.enchants
              if last > 0 then
                if prices.enchants[last].comment == nil then
                  prices.enchants[last].comment = string.sub(line, 2, -1)
                else
                  prices.enchants[last].comment = prices.enchants[last].comment..'\n'..line
                end
              end
            else
              local enchant = {}
              local class, id, level, price, name = line:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(.+)")
              enchant.class = tonumber(class)
              enchant.id = tonumber(id) 
              enchant.level = tonumber(level)
              enchant.price = tonumber(price)
              enchant.name = name

              table.insert(prices.enchants, enchant)
            end
          -- читаем цены на энергию
          elseif part == 3 then
            prices.energy = tonumber(line)
            if prices.energy == nil then prices.energy = 0 end
          end
        end
      end
    end
  end
end

-- функция получения одной записи из таблицы прайсов
function getPrice(id, metadata)
  for i=1, #prices do
    if prices[i].id == id and prices[i].metadata == metadata then
      return prices[i]
    end
  end
  return {id = id, metadata = metadata, sell = -1, buy = -1, name = id..":"..metadata, maxSize = 1}
end

-- обрезаем строку до определенной длины
function cutLine(line, len)
  if unicode.len(line) <= len then
    return line
  else
    return unicode.sub(line, 1, len-3)..'...'
  end
end
-- форматирование крупных чисел
function formatMoney(amount) -- credit http://richard.warburton.it
 local n = tostring(amount)
 local left,num,right = string.match(n,'^([^%d]*%d)(%d*)(.-)$')
 return left..(num:reverse():gsub('(%d%d%d)','%1,'):reverse())..right
end
-- деньги в красивом формате
function drawPriceMcrUU(x, y, money, UU, foreM, foreU, showUUtag)
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
-- шапка
function drawTop(width, text)
  if text == nil then text = "Добро пожаловать!" end
  gpu.setForeground( 0xffb600)
  gpu.set(2,1, "[Totoro Bank] ")
  gpu.setForeground( 0x336dff)
  gpu.set(16,1, text)
  gpu.setForeground( 0x3c3c3c)
  gpu.set(width-#VERSION-1, 1, VERSION)
end
-- экран
function screenCatalog(screen, scroll)
  gpu.bind(screen.address)
  gpu.setBackground( 0x000000)
  gpu.setResolution(screen.width, screen.height)
  term.clear()
  drawTop(screen.width, "Доступные товары и цены:")
  drawPrices(screen, scroll)
end
-- таблица
local filter = ''
function drawPrices(screen, scroll)
  if scroll then next(screen) end
  local page = screen.page
  local columns = "|"..string.rep(" ", 9).."|"..string.rep(" ", 16).."|"
  columns = columns..string.rep(" ", screen.width-#columns-1).."|"

  gpu.setBackground( 0x5a5a5a)
  gpu.setForeground( 0xffffff)

  gpu.set(2,2, " Покупка ")
  gpu.set(12,2, " Продажа ($/UU) ")
  gpu.set(29,2, " Название")
  gpu.set(38,2, string.rep(" ", screen.width-38))

  for y=3, screen.height do
    gpu.set(1, y, columns)
  end
  if #prices > 0 then
    local num = (page-1) * (screen.height-3) + 1
    local y = 3
    while y <= screen.height do
      -- если вышли за пределы - конец
      if num > #prices then break end
      -- иначе - рисуем
      if filter == '' or string.find(unicode.lower(prices[num].name), filter) ~= nil then
        gpu.setForeground( 0xffb600)
        gpu.set(30, y, cutLine(prices[num].name, screen.width-31))
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
        -- just for lulz
        os.sleep(0.05)
        --
        y = y + 1
      end
      num = num + 1
    end
  end
end
function previous(screen)
  screen.page = screen.page - 1
  if screen.page < 1 then screen.page = screen.pagestotal end
end
function next(screen)
  screen.page = screen.page + 1
  if screen.page > screen.pagestotal then screen.page = 1 end
end

local pricesTime = computer.uptime()
function updateInfoScreens(scroll)
  for i = 1, #screen do
    screenCatalog(screen[i], scroll)
  end
end

local updateTime = computer.uptime()
function updatePricesTable()
  toLog("Price table updated!", "system")
  loadPrices(true)
end

-- "костыль" для обновления экрана
function updateScreen()
  gpu.setBackground( 0x000000)
  gpu.set(1,1, '_')
  gpu.set(1,1, ' ')
end


-- инициализация
-- создаем папку для логов
if not fs.exists("logs") then
  fs.makeDirectory("logs")
end
-- читаем цены с Pastebin и распечатываем их на инфо-дисплеи
updatePricesTable()
-- опрашиваем дисплеи
callForScreens()
updateInfoScreens()

-- слушаем эфир
while true do
  local name, add = event.pull(5)

  -- обрабатываем полученные события
  if name == 'key_down' then
    break
  end
  -- проверяем цены на Pastebin если надо
  if (computer.uptime() - updateTime) > PRICESUPDATE then
    updateTime = computer.uptime()
    updatePricesTable()
  end
  -- обновляем цены в вестибюле, если надо
  if (computer.uptime() - pricesTime) > INFOUPDATE then 
    pricesTime = computer.uptime()
    updateInfoScreens(true)
  end

  -- чтобы экран не погас
  updateScreen()
end

-- завершение
modem.close()
-- Text Flow (1.1)
-- by Totoro (c) 26/3/2015
local unicode = require('unicode')
local event = require('event')
local fs = require('filesystem')
local com = require("component")
local screen = com.screen
local gpu = com.gpu

-- константы
local DATAFILE = "data.txt"
local CONFIGFILE = "flow.ini"

-- сохраняем старое и ставим новое разрешение
local screenW, screenH = screen.getAspectRatio()
local oldW, oldH = gpu.getResolution()
local WIDTH, HEIGTH = math.ceil(screenW*4.5), screenH
-- другие нужные и полезные параметры
local scroll_delay = 0.2

-- ========================== L O A D   F I L E S ========================== --
-- загружаем настройки и таблицу страниц
function loadConfig(configfile)
  file = io.open(configfile, "r")
  if file ~= nil then
    pages = {}
    for line in file:lines() do
      -- если строка не пуста и не комментарий
      if string.len(line) ~= 0 and line:sub(1,1) ~= "#" then
        key, data = line:match("(%S+)%s*=%s*(.+)")
        -- читаем скорость прокрутки
        if key == "scroll" then
          value = tonumber(data)
          if value ~= nil then scroll_delay = value end
        end
      end
    end
    file:close()
  else
    -- файл конфигурации не найден
    error("Файл конфигураций не найден!")
  end
end

local colors = {}
colors.black  = 0x000000
colors.white  = 0xffffff
colors.gray   = 0x888888
colors.red    = 0xff0000
colors.green  = 0x00ff00
colors.blue   = 0x0000ff
colors.yellow = 0xffff00
colors.cyan   = 0x00b6ff
-- эта функция читает всякую тарабарщину и пытается понять,
-- какой цвет имелся ввиду
function interpret(word)
  -- если цвет есть в таблице
  if colors[word] ~= nil then
    return colors[word]
  end
  -- если его там нет
  local color = 0
  for i=1, 6 do
    local n = string.byte(word:sub(i,i)) - 48
    color = color * 16 + n
  end
  return color
end

local data = {}
local last_update = ""
function addToken(fore, back, text)
  table.insert(data, {fore = fore, back = back, text = text, len = unicode.len(text)})
end

function loadData(filename)
  local file = io.open(filename, 'r')
  if file ~= nil then
    -- текущий токен
    local fore = 0xffffff
    local back = 0x000000
    local text = ""
    -- очищаем таблицу и пускаем первой строкой разделитель
    data = {}
    data[0] = {fore = fore, back = back, text = "    * * *    ", len = 13}
    -- начинаем читать файл посимвольно
    while true do
      local char = file:read(1)
      -- если достигнут конец файла - выходим
      if char == nil then
        addToken(fore, back, text)
        text = ""
        break
      end
      -- если это не перенос строки (на которые программе чхать в принципе)
      if char ~= '\n' and char ~= '\r' then
        -- если это служебный символ - читаем все слово и интерпретируем его
        if char == '#' or char == '@' then
          -- сохраняем то что есть
          if text ~= "" then
            addToken(fore, back, text)
            text = ""
          end
          -- читаем слово
          local word = ""
          while true do
            local x = file:read(1)
            if x == ' ' or x == nil or x == '\r' then break end
            if x == '\n' then
              -- завершаем строку
              addToken(fore, back, text)
              text = ""
              -- ставим разделитель (белые звездочки)
              table.insert(data, data[0])
              break
            end
            word = word..x
          end
          local color = interpret(word)
          if char == '#' then fore = color
          else back = color end
        -- иначе - добавляем к текущей строке
        else
          text = text .. char
        end
      elseif char == '\n' then
        -- завершаем строку
        addToken(fore, back, text)
        text = ""
        -- ставим разделитель (белые звездочки)
        table.insert(data, data[0])
      end
    end
    file:close()
    last_update = fs.lastModified(filename)
  end
end
-- проверяем, давно ли обновлялся текст в файле
function updateData(filename)
  local stamp = fs.lastModified(filename)
  if stamp ~= last_update then
    loadData(filename)
  end
end

-- ============================== R E N D E R ============================== --
local pos = {word = 0, letter = 1}
function drawFlow()
  local len = 0
  local word = pos.word
  while len < WIDTH do
    -- рисуем фрагменты строк, соответствующими цветами
    gpu.setForeground(data[word].fore)
    gpu.setBackground(data[word].back)
    if len == 0 then
      gpu.set(2+len-pos.letter, 1, data[word].text) --unicode.sub(data[word].text, pos.letter, -1))
      len = len + data[word].len - pos.letter + 1
    else
      gpu.set(1+len, 1, data[word].text)
      len = len + data[word].len
    end
    word = word + 1
    if word > #data then
      gpu.setForeground(data[0].fore)
      gpu.setForeground(data[0].back)
      gpu.set(len+1, 1, string.rep(' ', WIDTH-len))
      break
    end
  end
  -- двигаем текст
  pos.letter = pos.letter + 1
  if pos.letter > data[pos.word].len then
    pos.letter = 1
    pos.word = pos.word + 1

    -- если список строк кончился - обновление и резет в начало
    if pos.word > #data then
      pos.word = 0
      gpu.setForeground(data[0].fore)
      gpu.setForeground(data[0].back)
      gpu.set(1, 1, string.rep(' ', WIDTH))
      updateData(DATAFILE)
    end
  end
end


-- ========================== M A I N   C Y C L E ========================== --
-- инициализация
-- подгоняем разрешение монитора
gpu.setResolution(WIDTH, HEIGTH)
-- читаем конфиги
loadConfig(CONFIGFILE)
-- читаем текст
updateData(DATAFILE)

while true do
  name = event.pull(scroll_delay)
  if name == 'key_down' then break end
  drawFlow()
end


-- восстановим разрешение
gpu.setResolution(oldW, oldH)
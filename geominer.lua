local node = 9 -- max = 1849
local h_min, h_max = 1.7, 51 -- минимальная плотность, максимальная плотность
local computer = require('computer')
local component = require('component')
local i_c = component.inventory_controller
local geolyzer = component.geolyzer
local robot = component.robot
local x, y, z, d = 0, 0, 0, nil -- S = 0, W = 1, N = 2, E = 3 [+x = E, -x = W, +z = S, -z = N]
local a_dr, x_dr, z_dr = 1, 0, 0 -- координаты для нод в спирали
local x1, z1 = 0, 0 -- координаты для сканера
local tWorld = {x = {}, y = {}, z = {}} -- координаты помеченных блоков
local target, p, height, tTest, bedrock, x_f, y_f, z_f, gen, xS, yS, zS, D0, D1, ind, sb, cb = 0, 1, 64
local tWaste = {
  'cobblestone',
  'sandstone',
  'stone',
  'dirt',
  'grass',
  'gravel',
  'sand',
  'end_stone',
  'hardened_clay',
  'mossy_cobblestone',
  'planks',
  'fence',
  'torch',
  'nether_brick',
  'nether_brick_fence',
  'nether_brick_stairs',
  'netherrack',
  'soul_sand'
}

local function report(msg)
  print(msg)
  if component.isAvailable('tunnel') then
    component.tunnel.send(msg)
  end
end
-- навигация ---------
local function compass() -- калибровка компаса
  local tCmps = {{-1, 0}, {0, -1}, {1, 0}, [0] = {0, 1}}
  while not d do
    for c = 0, 3 do
      robot.swing(3)
      if geolyzer.scan(tCmps[c][1], tCmps[c][2], 0, 1, 1, 1)[1] == 0 and robot.place(3) then
        if geolyzer.scan(tCmps[c][1], tCmps[c][2], 0, 1, 1, 1)[1] > 0 then
          d = c
          return
        end
      end
    end
    robot.turn(true)
  end
end

local function delta(xD, yD, zD) -- принимает исходные координаты, возвращает индекс ближаейшего блока
  xS, yS, zS, D0, D1, ind = 0, 0, 0, math.huge, math.huge, 0
  for bl = 1, #tWorld.x do
    xS, yS, zS = tWorld.x[bl], tWorld.y[bl], tWorld.z[bl]
    if xS < xD then xS = xD - xS else xS = xS - xD end
    if yS < yD then yS = yD - yS else yS = yS - yD end
    if zS < zD then zS = zD - zS else zS = zS - zD end
    D0 = xS + yS + zS
    if D0 < D1 then
      D1 = D0
      ind = bl
    end
  end
  return ind
end

local tMove = {
  function() x, x1 = x - 1, x1 - 1 end,
  function() z, z1 = z - 1, z1 - 1 end,
  function() x, x1 = x + 1, x1 + 1 end,
  [0] = function() z, z1 = z + 1, z1 + 1 end
}

local function move(side) -- 0, 1, 3
  robot.swing(0)
  sb, cb = robot.swing(side)
  if not sb and cb == 'block' then
    tWorld.x, tWorld.y, tWorld.z = {}, {}, {}
    move(1)
    report('АШИПКА: ПЦ!')
  else
    while robot.swing(side) do
    end
  end
  if robot.move(side) then
    if side == 0 then
      y = y - 1
    elseif side == 1 then
      y = y + 1
    elseif side == 3 then
      tMove[d]()
    end
  end
  if #tWorld.z ~= 0 then
    for m = 1, #tWorld.z do
      if x == tWorld.x[m] and y == tWorld.y[m] and z == tWorld.z[m] then
        table.remove(tWorld.x, m)
        table.remove(tWorld.y, m)
        table.remove(tWorld.z, m)
        break
      end
    end
  end
end

local function turn(cc) -- поворотник
  if not cc then
    cc = false
  end
  if robot.turn(cc) then
    if cc then
      d = (d + 1) % 4
    else
      d = (d - 1) % 4
    end
  end
end

local function spiral(node_t) -- поиск координат указанной ноды в спирали
  a_dr, x_dr, z_dr = 1, 0, 0
  while true do
    for i = 1, a_dr do
      if a_dr % 2 == 0 then
        x_dr = x_dr + 1
      else
        x_dr = x_dr - 1
      end
      node_t = node_t - 1
      if node_t == 0 then
        return
      end
    end
    for i = 1, a_dr do
      if a_dr % 2 == 0 then
        z_dr = z_dr + 1
      else
        z_dr = z_dr - 1
      end
      node_t = node_t - 1
      if node_t == 0 then
        return
      end
    end
    a_dr = a_dr + 1
  end
end
-- движение ----------
local function sturn(dT) -- вспомогательная фция
  while d ~= dT do
    turn((dT - d) % 4 == 1)
  end
end

local function gotot(xt, yt, zt) -- великий ход конем
  -- Y
  while y ~= yt do
    if y < yt then
      move(1)
    elseif y > yt then
      move(0)
    end
  end
  -- X
  if x < xt and d ~= 3 then
    sturn(3)
  elseif x > xt and d ~= 1 then
    sturn(1)
  end
  while x ~= xt do
    move(3)
  end
  -- Z
  if z < zt and d ~= 0 then
    sturn(0)
  elseif z > zt and d ~= 2 then
    sturn(2)
  end
  while z ~= zt do
    move(3)
  end
end
-- управление копалкой
local function scan(sy) -- сканер квадрата 7x7
  -- необходимо указывать на какой высоте сканировать, относительно робота
  tTest = geolyzer.scan(-3-x1, -3-z1, sy, 7, 7, 1)
  p = 1
  for sz = -3-z1, 3-z1 do
    for sx = -3-x1, 3-x1 do
      if tTest[p] >= h_min and tTest[p] <= h_max then
        if sy == 0 and sz == z1 and sx == x1 then
        else
          table.insert(tWorld.x, x+sx)
          table.insert(tWorld.y, y+sy)
          table.insert(tWorld.z, z+sz)
        end
      elseif tTest[p] < -0.3 then
        tWorld.x, tWorld.y, tWorld.z = {}, {}, {}
        bedrock = y
        return false
      end
      p = p + 1
    end
  end
end

local function border() -- определение координат бедрока
  local test = 0
  for br = -1, 2 do
    for stp = -8, 1, 7 do
      tTest = geolyzer.scan(stp, stp, br, 8, 8, 1)
      for v = 1, #tTest do
        if tTest[v] < -0.3 then
          test = br
        end
      end
    end
  end
  return test + y + 1
end

local function fullness() -- получение коэффициента заполненности инвентаря
  local item
  for slot = 1, robot.inventorySize() do
    if robot.count(slot) > 0 then
      if not item then
        item = i_c.getStackInInternalSlot(slot).size
      else
        item = item + i_c.getStackInInternalSlot(slot).size
      end
    end
  end
  if item then
    return item/(robot.inventorySize()*64)
  else
    return 0
  end
end

local function sorter() -- сортировщик инвентаря (после сброса мусора)
  local item, item1
  for slot = robot.inventorySize(), 1, -1 do
    for slot1 = 1, slot-1 do
      if robot.count(slot) > 0 then
        item = i_c.getStackInInternalSlot(slot)
        item1 = i_c.getStackInInternalSlot(slot1)
        if not item1 or item.name == item1.name and item.maxSize-item.size ~= 0 then
          robot.select(slot)
          robot.transferTo(slot1, 64)
        end
      end
    end
  end
end

local function packer() -- упаковщик предметов в блоки
  if component.isAvailable('crafting') then
    local tCrafting = {1, 2, 3, 5, 6, 7, 9, 10, 11}
    local tBlocks = {
      'redstone',
      'coal',
      'dye',
      'diamond',
      'emerald',
    }
    local function clear_table() -- очистка рабочей зоны
      for slot = 1, 9 do
        if robot.count(tCrafting[slot]) > 0 then
          robot.select(tCrafting[slot])
          for slot1 = 4, robot.inventorySize()-1 do
            if slot1 == 4 or slot1 == 8 or slot1 > 11 then
              robot.transferTo(slot1, 64)
            end
          end
        end
      end
    end
    local item
    sorter()
    for i = 1, #tBlocks do
      clear_table()
      for slot = 4, robot.inventorySize() do
        if slot == 4 or slot == 8 or slot > 11 then
          if robot.count(slot) >= 9 then
            if i_c.getStackInInternalSlot(slot).name == 'minecraft:'..tBlocks[i] then
              robot.select(slot)
              while robot.count() > 0 do
                for slot1 = 1, 9 do
                  robot.transferTo(tCrafting[slot1], 1)
                end
              end
            end
          end
        end
      end
      component.crafting.craft(64)
    end
  end
end

local function dropping(cont) -- сброс лута (true = бросать в контейнер)
  local function isWaste(n) -- проверка, является ли предмет мусором
    for w = 1, #tWaste do
      if n == 'minecraft:'..tWaste[w] then
        return true
      end
    end
  end
  local function drop()
    for slot = 1, robot.inventorySize() do
      if robot.count(slot) > 0 then
        robot.select(slot)
        if isWaste(i_c.getStackInInternalSlot(slot).name) then
          robot.drop(0)
        else
          if cont then
            if not robot.drop(3) then
              report('АШИПКА: МЕСТОВ НЕТ')
              while not robot.drop(3) do
                os.sleep(10)
              end
            end
          end
        end
      end
    end
  end
  local s_cont -- статус поиска контейнера
  if cont then -- поиск контейнера
    for side = 0, 3 do
      if i_c.getInventorySize(3) and i_c.getInventorySize(3) > 1 then
        s_cont = true
        drop() -- дроппинг предметов
        break 
      end
      turn()
    end
    if not s_cont then -- если нет контейнера - начинаем об этом спамить
      report('АШИПКА: СУНДУЧОК, ПЛИЗ')
      os.sleep(30)
      dropping(true)
    end
  else -- дроппинг мусора
    drop()
  end
end

local function charger() -- зарядка инструмента
  local status = 0
  for side = 0, 3 do
    if i_c.getInventorySize(3) and i_c.getInventorySize(3) == 1 then
      while status == 0 do
        if robot.durability() ~= 1 then
          i_c.equip()
          robot.drop(3)
          os.sleep(30)
          robot.suck(3)
          i_c.equip()
        else
          status = 1
        end
      end
      break
    end
    turn()
  end
end

local function home() -- возвращение на хомку
  gotot(0, -1, 0)
  move(1)
  packer()
  dropping(true)
  charger()
end

local function miner() -- осноная функция копалки
  if #tWorld.x ~= 0 then
    while #tWorld.x ~= 0 do
      target = delta(x, y, z)
      gotot(tWorld.x[target], tWorld.y[target], tWorld.z[target])
    end
  else
    if not bedrock then
      move(0)
    end
  end
end

local function recovery() -- прыжог домой для зарядки/сброса лута и обратно
  x_f, y_f, z_f = x, y, z
  home()
  move(0)
  gotot(x_f, y_f, z_f)
end

local function chunkloader(set) -- вкл/выкл чанклоадера, если есть
  if component.isAvailable('chunkloader') then
    component.chunkloader.setActive(set)
  end
end

local function state() -- проверка соостояния, восстановление, при необходимости
  if fullness() > 0.95 then
    dropping()
    packer()
    if fullness() > 0.95 then
      recovery()
    end
  end
  if robot.durability() < 0.1 then
    recovery()
  end
  if computer.energy()/computer.maxEnergy() < 0.2 then
    -- надо использовать текущую ноду, как множитель заряда
    if component.isAvailable('generator') then
      for slot = 1, robot.inventorySize() do
        if component.generator.insert(64) then
          gen = true
          os.sleep(30)
          break
        end
      end
      if gen then
        gen = nil
      else
        recovery()
      end
    else
      recovery()
    end
  end
end

local tArgs = {...}
if tArgs[1] then
  node = tonumber(tArgs[1])
end
if tArgs[2] then
  height = tonumber(tArgs[2])
end

chunkloader(true)
local test_time = computer.uptime()
move(0)
compass()

for n = 1, node do
  while not bedrock do
    scan(-1)
    miner()
    state()
    if y == height then
      bedrock = y
    end
  end
  if n == 1 then
    height = border()
  end
  state()
  if n ~= node then
    spiral(n)
    gotot(x_dr*7, math.abs(bedrock)+y-1, z_dr*7)
    x1, z1 = 0, 0
    bedrock = nil
  end
end

home()
chunkloader(false)
local min, sec = math.modf((computer.uptime()-test_time)/60)
report('Время работы: '.. min ..' мин. '.. math.ceil(sec*60) ..' сек.')

local ND, HN, HX, HGT = 9, 1.7, 51, 64 -- ноды, мин плот, макс плот, расст до бедрока
local A,B=require("component"),require("computer")
local function J(s)return A.isAvailable(s)end
local R, I, G = A.robot, A.inventory_controller, A.geolyzer

local N, S, RC, TT, RS, IS = G.scan, R.swing, R.count, R.transferTo, R.select, R.inventorySize()
local GS, GI = I.getStackInInternalSlot, I.getInventorySize
local mn, mx, HU, TR, TI = math.min, math.max, math.huge, table.remove, table.insert
local CMPS, D, M, T, SP, ST, GT, SC, FU, PK, DP, HM, RE, CL, SE
local X, Z, x, y, z, d, xB, yB, zB, BE, gen = 0, 0, 0, 0, 0
local a_dr, x_dr, z_dr = 1, 0, 0
local MC, L = 'minecraft:', true

local W, W1 = {x={},y={},z={}},{'cobblestone','sandstone','stone','dirt','grass','gravel','sand','hardened_clay'}

CMPS = function()
  local C = {{-1, 0}, {0, -1}, {1, 0}, [0] = {0, 1}}
  while not d do
    for c = 0, 3 do
      S(3)
      if N(C[c][1], C[c][2], 0, 1, 1, 1)[1] == 0 and R.place(3) then
        if N(C[c][1], C[c][2], 0, 1, 1, 1)[1] > 0 then
          d = c
          return
        end
      end
    end
    R.turn(L)
  end
end

D = function(xD, yD, zD)
  local D0, D1, ind = HU, HU, 0
  for bl = 1, #W.x do
    D0 = math.sqrt((xD-W.x[bl])^2+(yD-W.y[bl])^2+(zD-W.z[bl])^2)
    if D0 < D1 then
      D1, ind = D0, bl
    end
  end
  return ind
end

M = function(s)
  S(0)
  sb, cb = S(s)
  if not sb and cb == 'block' then
    W.x, W.y, W.z = {}, {}, {}
    M(1)
    --report('АШИПКА: ПЦ!')
  else
    while S(s) do
    end
  end
  if R.move(s) then
    if s == 0 then
      y = y - 1
    elseif s == 1 then
      y = y + 1
    elseif s == 3 then
      if d==0 then
        z,Z=z+1,Z+1
      elseif d==1 then
        x,X=x-1,X-1
      elseif d==2 then
        z,Z=z-1,Z-1
      else
        x,X=x+1,X+1
      end
    end
  end
  if #W.x ~= 0 then
    for m = 1, #W.x do
      if x == W.x[m] and y == W.y[m] and z == W.z[m] then
        TR(W.x, m)
        TR(W.y, m)
        TR(W.z, m)
        break
      end
    end
  end
end

T = function(s)
  if not s then
    s = false
  end
  if R.turn(s) then
    if s then
      d = (d + 1) % 4
    else
      d = (d - 1) % 4
    end
  end
end

SP = function(ND)
  a_dr, x_dr, z_dr = 1, 0, 0
  while L do
    for i = 1, a_dr do
      if a_dr % 2 == 0 then
        x_dr = x_dr + 1
      else
        x_dr = x_dr - 1
      end
      ND = ND - 1
      if ND == 0 then
        return
      end
    end
    for i = 1, a_dr do
      if a_dr % 2 == 0 then
        z_dr = z_dr + 1
      else
        z_dr = z_dr - 1
      end
      ND = ND - 1
      if ND == 0 then
        return
      end
    end
    a_dr = a_dr + 1
  end
end

ST = function(dT)
  while d ~= dT do
    T((dT - d) % 4 == 1)
  end
end

GT = function(xt, yt, zt)
  while y ~= yt do
    if y < yt then
      M(1)
    elseif y > yt then
      M(0)
    end
  end
  if x < xt and d ~= 3 then
    ST(3)
  elseif x > xt and d ~= 1 then
    ST(1)
  end
  while x ~= xt do
    M(3)
  end
  if z < zt and d ~= 0 then
    ST(0)
  elseif z > zt and d ~= 2 then
    ST(2)
  end
  while z ~= zt do
    M(3)
  end
end

SC = function()
  local tbl, p = N(-X, -Z, -1, 8, 8, 1), 1
  for oz = -Z, 7-Z do
    for ox = -X, 7-X do
      if tbl[p] >= HN and tbl[p] <= HX then
        TI(W.x, x+ox)
        TI(W.y, y-1)
        TI(W.z, z+oz)
      elseif tbl[p] < -0.3 then
        W.x, W.y, W.z = {}, {}, {}
        BE = y
        return
      end
      p = p + 1
    end
  end
end

FU = function()
  local i
  for s = 1, IS do
    if RC(s) > 0 then
      if not i then
        i = GS(s).size
      else
        i = i + GS(s).size
      end
    end
  end
  if i then
    return i/(IS*64)
  else
    return 0
  end
end

PK = function()
  if J('crafting') then
    local tC, tB = {1, 2, 3, 5, 6, 7, 9, 10, 11}, {'redstone','coal','dye','diamond','emerald'}
    for s = IS, 1, -1 do
      for s1 = 1, s-1 do
        if RC(s) > 0 then
          item = GS(s)
          item1 = GS(s1)
          if not item1 or item.name == item1.name and item.maxSize-item.size ~= 0 then
            RS(s)
            TT(s1, 64)
          end
        end
      end
    end
    for i = 1, #tB do
      for s = 1, 9 do
        if RC(tC[s]) > 0 then
          RS(tC[s])
          for s1 = 4, IS-1 do
            if s1 == 4 or s1 == 8 or s1 > 11 then
              TT(s1, 64)
            end
          end
        end
      end
      for s = 4, IS do
        if s == 4 or s == 8 or s > 11 then
          if RC(s) >= 9 then
            if GS(s).name == MC..tB[i] then
              RS(s)
              while RC() > 0 do
                for s1 = 1, 9 do
                  TT(tC[s1], 1)
                end
              end
            end
          end
        end
      end
      A.crafting.craft(64)
    end
  end
end

DP = function(c)
  local function isWaste(n)
    for w = 1, #W1 do
      if n == MC..W1[w] then
        return L
      end
    end
  end
  local function drop()
    for s = 1, IS do
      if RC(s) > 0 then
        RS(s)
        if isWaste(GS(s).name) then
          R.drop(0)
        else
          if c then
            if not R.drop(3) then
              --report('ERROR: SPACE?')
              while not R.drop(3) do
                os.sleep(10)
              end
            end
          end
        end
      end
    end
  end
  local sc
  if c then
    for s = 0, 3 do
      if GI(3) and GI(3) > 1 then
        sc = L
        drop()
        break 
      end
      T()
    end
    if not sc then
      --report('ERROR: CHEST?!')
      os.sleep(30)
      DP(L)
    end
  else
    drop()
  end
end

HM = function()
  GT(0, -1, 0)
  M(1)
  PK()
  DP(L)
  local s = 0
  for side = 0, 3 do
    if GI(3) and GI(3) == 1 then
      while s == 0 do
        if R.durability() ~= 1 then
          I.equip()
          R.drop(3)
          os.sleep(30)
          R.suck(3)
          I.equip()
        else
          s = 1
        end
      end
      break
    end
    T()
  end
end

RE = function()
  xB, yB, zB = x, y, z
  HM()
  M(0)
  GT(xB, yB, zB)
end

CL = function(s)
  if J('chunkloader') then
    A.chunkloader.setActive(s)
  end
end

SE = function()
  if FU() > 0.95 then
    DP()
    PK()
    if FU() > 0.95 then
      RE()
    end
  end
  if R.durability() < 0.1 then
    RE()
  end
  if B.energy()/B.maxEnergy() < 0.2 then
    if J('generator') then
      for s = 1, IS do
        if A.generator.insert(64) then
          gen = L
          os.sleep(30)
          break
        end
      end
      if gen then
        gen = nil
      else
        RE()
      end
    else
      RE()
    end
  end
end

CL(L)
M(0)
CMPS()
for n = 1, ND do
  while not BE do
    SC(-1)
    if #W.x ~= 0 then
      while #W.x ~= 0 do
        tg = D(x, y, z)
        GT(W.x[tg], W.y[tg], W.z[tg])
      end
    else
      if not BE then
        M(0)
      end
    end
    SE()
    if y == HGT then
      BE = y
    end
  end
  SE()
  if n ~= ND then
    SP(n)
    GT(x_dr*8, math.abs(BE)+y-1, z_dr*8)
    X, Z = 0, 0
    BE = nil
  end
end
HM()
CL(false)

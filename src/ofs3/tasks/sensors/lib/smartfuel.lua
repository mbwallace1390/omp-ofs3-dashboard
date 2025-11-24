--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local batteryConfigCache = nil
local fuelStartingPercent = nil
local fuelStartingConsumption = nil

local lastVoltages = {}
local maxVoltageSamples = 5
local voltageStableTime = nil
local voltageStabilised = false
local stabilizeNotBefore = nil
local voltageThreshold = 0.15
local preStabiliseDelay = 1.5

local telemetry

local function resetVoltageTracking()
    lastVoltages = {}
    voltageStableTime = nil
    voltageStabilised = false
end

local function isVoltageStable()
    if #lastVoltages < maxVoltageSamples then return false end
    local vmin, vmax = lastVoltages[1], lastVoltages[1]
    for _, v in ipairs(lastVoltages) do
        if v < vmin then vmin = v end
        if v > vmax then vmax = v end
    end
    return (vmax - vmin) <= voltageThreshold
end

local function smartFuelCalc()

    if not telemetry then telemetry = ofs3.tasks.telemetry end

    if not ofs3.session.isConnected or not ofs3.session.batteryConfig then
        resetVoltageTracking()
        return nil
    end

    local bc = ofs3.session.batteryConfig

    local configSig = table.concat({bc.batteryCellCount, bc.batteryCapacity, bc.consumptionWarningPercentage, bc.vbatmaxcellvoltage, bc.vbatmincellvoltage, bc.vbatfullcellvoltage}, ":")

    if configSig ~= batteryConfigCache then
        batteryConfigCache = configSig
        fuelStartingPercent = nil
        fuelStartingConsumption = nil
        resetVoltageTracking()
        stabilizeNotBefore = os.clock() + preStabiliseDelay
    end

    local voltage = telemetry and telemetry.getSensor and telemetry.getSensor("voltage") or nil

    if not voltage or voltage < 2 then
        resetVoltageTracking()
        stabilizeNotBefore = nil
        return nil
    end

    local now = os.clock()

    if stabilizeNotBefore and now < stabilizeNotBefore then return nil end

    table.insert(lastVoltages, voltage)
    if #lastVoltages > maxVoltageSamples then table.remove(lastVoltages, 1) end

    if not voltageStabilised then
        if isVoltageStable() then
            ofs3.utils.log("Voltage stabilized at: " .. voltage, "info")
            voltageStabilised = true
        else
            ofs3.utils.log("Waiting for voltage to stabilize...", "info")
            return nil
        end
    end

    if #lastVoltages >= 1 and ofs3.flightmode.current == "preflight" then
        local prev = lastVoltages[#lastVoltages - 1]
        if voltage > prev + voltageThreshold then
            ofs3.utils.log("Voltage increased after stabilization – resetting...", "info")
            fuelStartingPercent = nil
            fuelStartingConsumption = nil
            resetVoltageTracking()
            stabilizeNotBefore = os.clock() + preStabiliseDelay
            return nil
        end
    end

    local cellCount, packCapacity, reserve, maxCellV, minCellV, fullCellV = bc.batteryCellCount, bc.batteryCapacity, bc.consumptionWarningPercentage, bc.vbatmaxcellvoltage, bc.vbatmincellvoltage, bc.vbatfullcellvoltage

    if reserve > 80 or reserve < 0 then reserve = 20 end

    if packCapacity < 10 or cellCount == 0 or maxCellV <= minCellV or fullCellV <= 0 then
        fuelStartingPercent = nil
        fuelStartingConsumption = nil
        return nil
    end

    local usableCapacity = packCapacity * (1 - reserve / 100)
    if usableCapacity < 10 then usableCapacity = packCapacity end

    local consumption = telemetry and telemetry.getSensor and telemetry.getSensor("consumption") or nil

    if not fuelStartingPercent then
        local perCell = (voltage and cellCount > 0) and (voltage / cellCount) or 0
        if perCell >= fullCellV then
            fuelStartingPercent = 100
        elseif perCell <= minCellV then
            fuelStartingPercent = 0
        else
            local usableRange = maxCellV - minCellV
            local pct = ((perCell - minCellV) / usableRange) * 100
            if reserve > 0 and pct <= reserve then
                fuelStartingPercent = 0
            else
                fuelStartingPercent = math.floor(math.max(0, math.min(100, pct)))
            end
        end
        local estimatedUsed = usableCapacity * (1 - fuelStartingPercent / 100)
        fuelStartingConsumption = (consumption or 0) - estimatedUsed
    end

    if consumption and fuelStartingConsumption and packCapacity > 0 then
        local used = consumption - fuelStartingConsumption
        local percentUsed = used / usableCapacity * 100
        local remaining = math.max(0, fuelStartingPercent - percentUsed)
        return math.floor(math.min(100, remaining) + 0.5)
    else

        if not voltageStabilised or (stabilizeNotBefore and os.clock() < stabilizeNotBefore) then
            print("Voltage not stabilised or pre-stabilisation delay active, returning nil")
            return nil
        end
        return fuelStartingPercent
    end
end

return {calculate = smartFuelCalc}

--[[
Copyright 2014 Seth VanHeulen

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
--]]

_addon.name = 'fisher'
_addon.version = '1.4.0'
_addon.command = 'fisher'
_addon.author = 'Seth VanHeulen'

defaults = {}
defaults.chat = 0
defaults.log = -1
defaults.equip = true

config = require('config')
settings = config.load(defaults)

bait_id = 17400 -- sinking minnow
fish_id = '\13\0\228\2' -- hakuryu
catch_delay = 20
--fish_id = '\14\0\160\5' -- lik
--catch_delay = 10
--fish_id = '\13\0\64\1' -- gugru tuna
--catch_delay = 3
release_delay = 1
cast_delay = 4

running = false
log_file = nil
catch_key = nil

-- debug and logging functions

function message(level, message)
    local prefix = 'E'
    local color = 167
    if level == 1 then
        prefix = 'I'
        color = 207
    elseif level == 2 then
        prefix = 'D'
        color = 160
    end
    if settings.log >= level then
        if log_file == nil then
            log_file = io.open(windower.addon_path .. 'fisher.log', 'a')
        end
        if log_file == nil then
            settings.log = -1
            windower.add_to_chat(167, 'unable to open log file')
        else
            log_file:write('%s | %s | %s\n':format(os.date(), prefix, message))
            log_file:flush()
        end
    end
    if settings.chat >= level then
        windower.add_to_chat(color, message)
    end
end

-- binary helper functions

function string.tohex(str)
    return str:gsub('.', function (c) return '%02X':format(string.byte(c)) end)
end

function string.unpack_uint16(str, i)
    return str:byte(i + 1) * 0x100 + str:byte(i)
end

function string.unpack_uint32(str, i)
    local num = str:byte(i + 3)
    num = num * 0x100 + str:byte(i + 2)
    num = num * 0x100 + str:byte(i + 1)
    return num * 0x100 + str:byte(i)
end

function pack_uint16(num)
    return string.char(num % 0x100, math.floor(num / 0x100))
end

function pack_uint32(num)
    local str = string.char(num % 0x100)
    str = str .. string.char(math.floor(num / 0x100) % 0x100)
    str = str .. string.char(math.floor(num / 0x10000) % 0x100)
    return str .. string.char(math.floor(num / 0x1000000))
end

-- bait helper functions

function check_bait()
    local items = windower.ffxi.get_items()
    message(1, 'checking bait')
    if items.equipment.ammo == 0 then
        message(2, 'item slot: 0')
        return false
    end
    message(2, 'item slot: %d, id: %d':format(items.equipment.ammo, items.inventory[items.equipment.ammo].id))
    return items.inventory[items.equipment.ammo].id == bait_id
end

function equip_bait()
    for slot,item in pairs(windower.ffxi.get_items().inventory) do
        if item.id == bait_id and item.status == 0 then
            message(1, 'equiping bait')
            message(2, 'item slot: %d, id: %d, status: %d':format(slot, item.id, item.status))
            windower.ffxi.set_equip(slot, 3)
            return true
        end
    end
    message(0, 'out of bait')
    fisher_command('stop')
    return false
end

-- inventory helper functions

function check_inventory()
    local items = windower.ffxi.get_items()
    local empty = items.max_inventory
    message(1, 'checking inventory space')
    for _,item in pairs(items.inventory) do
        if item.id ~= 0 then
            empty = empty - 1
        end
    end
    message(2, 'inventory empty: %d, max: %d':format(empty, items.max_inventory))
    if empty < 1 then
        message(0, 'inventory full')
        fisher_command('stop')
        return false
    end
    return true
end

-- action functions

function catch()
    if running then
        local player = windower.ffxi.get_player()
        message(1, 'catching fish')
        windower.packets.inject_outgoing(0x110, '\16\11\0\0' .. pack_uint32(player.id) .. '\0\0\0\0' .. pack_uint16(player.index) .. '\3\0' .. catch_key)
    end
end

function release()
    if running then
        local player = windower.ffxi.get_player()
        message(1, 'releasing fish')
        windower.packets.inject_outgoing(0x110, '\16\11\0\0' .. pack_uint32(player.id) .. '\200\0\0\0' .. pack_uint16(player.index) .. '\3\0\0\0\0\0')
    end
end

function cast()
    if running and check_inventory() then
        if check_bait() then
            local player = windower.ffxi.get_player()
            message(1, 'casting')
            windower.packets.inject_outgoing(0x1A, '\26\8\0\0' .. pack_uint32(player.id) .. pack_uint16(player.index) .. '\14\0\0\0\0\0')
        elseif settings.equip == false then
            message(0, 'no bait equipped')
            fisher_command('stop')
        elseif equip_bait() then
            message(1, 'casting in %d seconds':format(cast_delay))
            windower.send_command('wait %d; lua i fisher cast':format(cast_delay))
        end
    end
end

-- event callback functions

function check_chat_message(message, sender, mode, gm)
    if running and gm then
        message(0, 'incoming gm chat')
        fisher_command('stop')
    end
end

function check_incoming_chunk(id, original, modified, injected, blocked)
    if running then
        if id == 0x115 then
            message(2, 'incoming fish info: ' .. original:tohex())
            if fish_id == original:sub(11, 14) then
                catch_key = original:sub(21)
                message(1, 'catching fish in %d seconds':format(catch_delay))
                windower.send_command('wait %d; lua i fisher catch':format(catch_delay))
            else
                message(1, 'releasing fish in %d seconds':format(release_delay))
                windower.send_command('wait %d; lua i fisher release':format(release_delay))
            end
        elseif id == 0x2A then
            message(2, 'incoming fish intuition: ' .. original:tohex())
        elseif id == 0x27 and windower.ffxi.get_player().id == original:unpack_uint32(5) then
            message(2, 'incoming fish caught: ' .. original:tohex())
        end
    end
end

function check_outgoing_chunk(id, original, modified, injected, blocked)
    if running then
        if id == 0x110 then
            message(2, 'outgoing fishing action: ' .. original:tohex())
            if original:byte(15) == 4 then
                message(1, 'casting in %d seconds':format(cast_delay))
                windower.send_command('wait %d; lua i fisher cast':format(cast_delay))
            end
        elseif id == 0x1A then
            message(2, 'outgoing fish command: ' .. original:tohex())
        end
    end
end

function fisher_command(...)
    if #arg == 1 and arg[1]:lower() == 'start' then
        running = true
        message(1, 'started fishing')
        cast()
    elseif #arg == 1 and arg[1]:lower() == 'stop' then
        running = false
        message(1, 'stopped fishing')
        if log_file ~= nil then
            log_file:close()
            log_file = nil
        end
    elseif #arg == 2 and arg[1]:lower() == 'chat' then
        settings.chat = tonumber(arg[2]) or -1
        settings:save('all')
    elseif #arg == 2 and arg[1]:lower() == 'log' then
        settings.log = tonumber(arg[2]) or -1
        settings:save('all')
        if settings.log < 0 and log_file ~= nil then
            log_file:close()
            log_file = nil
        end
    elseif #arg == 2 and arg[1]:lower() == 'equip' then
        if arg[2]:lower() == 'on' then
            settings.equip = true
        else
            settings.equip = false
        end
        settings:save('all')
    else
        windower.add_to_chat(167, 'usage: fisher start')
        windower.add_to_chat(167, '        fisher stop')
        windower.add_to_chat(167, '        fisher chat <level>')
        windower.add_to_chat(167, '        fisher log <level>')
        windower.add_to_chat(167, '        fisher equip <on/off>')
    end
end

-- register event callbacks

windower.register_event('chat message', check_chat_message)
windower.register_event('incoming chunk', check_incoming_chunk)
windower.register_event('outgoing chunk', check_outgoing_chunk)
windower.register_event('addon command', fisher_command)

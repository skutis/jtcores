local frame = 0

emu.register_frame(function()
    frame = frame + 1
    if frame ~= 65 then
        return
    end

    local cpu = manager.machine.devices[":maincpu"]
    local mem = cpu.spaces["program"]
    local f = io.open("/tmp/mame_mzone_spr65.txt", "w")
    f:write(string.format("frame=%d\n", frame))
    for offs = 0x3fc, 0, -4 do
        local attr = mem:read_u8(0x3000 + offs + 0)
        local ypos = mem:read_u8(0x3000 + offs + 1)
        local code = mem:read_u8(0x3000 + offs + 2)
        local xpos = mem:read_u8(0x3000 + offs + 3)
        if attr ~= 0 or ypos ~= 0 or code ~= 0 or xpos ~= 0 then
            local sx = xpos + 32
            local sy = 255 - ((ypos + 16) & 0xff)
            f:write(string.format("offs=%03x attr=%02x color=%x flipx=%d flipy=%d ypos=%02x code=%02x xpos=%02x sx=%d sy=%d\n",
                offs, attr, attr & 0x0f, (~attr >> 6) & 1, (attr >> 7) & 1, ypos, code, xpos, sx, sy))
        end
    end
    f:close()
    manager.machine:exit()
end)

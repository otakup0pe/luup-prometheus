--[[
    This file is part of luup-prometheus

    luup-prometheus is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    luup-prometheus is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with luup-prometheus.  If not, see <http://www.gnu.org/licenses/>.
--]]

local DATA = {
    battery_level={
        {{4}, 'urn:micasaverde-com:serviceId:HaDevice1', 'BatteryLevel'},
        {'battery_level_percent', 'Battery level as a percentage of its capacity'}
    },
    energy_sensor_counter={
        {{3}, 'urn:micasaverde-com:serviceId:EnergyMetering1', 'KWH'},
        {'electricity_used_kwh', 'Electricity used by this device in KWh', 'counter'}
    },
    energy_sensor_gauge={
        {{3}, 'urn:micasaverde-com:serviceId:EnergyMetering1', 'Watts'},
        {'electricity_usage_w', 'Currently reported electricity draw in Watts'}
    },
    humidity_sensor={
        {{16}, 'urn:micasaverde-com:serviceId:HumiditySensor1', 'CurrentLevel'},
        {'humidity_relative', 'Relative humidity (0..100)'}
    },
    light_sensor={
        {{18}, 'urn:micasaverde-com:serviceId:LightSensor1', 'CurrentLevel'},
        {'light_lux', 'Light level in lux'}
    },
    security_sensor={
        {{4}, 'urn:micasaverde-com:serviceId:SecuritySensor1', 'Tripped'},
        {'security_sensor_tripped', 'Integer 1/0 indicating sensor trip'}
    },
    temperature_sensor={
        {{5, 17}, 'urn:upnp-org:serviceId:TemperatureSensor1', 'CurrentTemperature'},
        {'temperature_c', 'Temperature in degrees Celsius'}
    },

    dimmer_state={
        {{2}, 'urn:upnp-org:serviceId:Dimming1', 'LoadLevelStatus'},
        {'dimmable_load_percent', 'Load level of a dimmable device (0..100)'}
    },
}
local DATA_BY_CAT = {}
for key, data in pairs(DATA) do
    for _, cat in ipairs(data[1][1]) do
        DATA_BY_CAT[cat] = DATA_BY_CAT[cat] or {}
        table.insert(DATA_BY_CAT[cat], key)
    end
end


function pm_metric(name, attributes, value)
    -- Format a metric for Prometheus text output
    local attrs = ''
    if attributes then
        local parts = {}
        for k, v in pairs(attributes) do
            table.insert(parts, k .. '="' .. tostring(v) .. '"')
        end
        attrs = '{' .. table.concat(parts, ',') .. '}'
    end
    return name .. attrs .. ' ' .. tostring(value) .. "\n"
end

function pm_attributes(device_num, device)
    -- Return a basic set of attributes for a device
    local a = {}
    a.room = luup.rooms[device.room_num]
    a.device = device_num
    return a
end

function pm_device_metrics()
    local output = ''

    local metrics = {}
    for device_num, device in pairs(luup.devices) do
        for _, data_key in ipairs(DATA_BY_CAT[device.category_num] or {}) do
            local d = DATA[data_key]
            local value = luup.variable_get(d[1][2], d[1][3], device_num)
            value = tonumber(value)
            if value then
                metrics[data_key] = metrics[data_key] or {}
                table.insert(metrics[data_key], {
                    luup.variable_get(d[1][2], d[1][3], device_num),
                    pm_attributes(device_num, device)
                })
            end
        end
    end

    local output = ''
    for data_key, values in pairs(metrics) do
        local mname = DATA[data_key][2][1]
        local mhelp = DATA[data_key][2][2]
        local mtype = DATA[data_key][2][3] or 'gauge'
        output = output .. '# HELP ' .. mname .. ' ' .. mhelp .. "\n"
        output = output .. '# TYPE ' .. mname .. ' ' .. mtype .. "\n"

        for _, v in ipairs(values) do
            output = output .. pm_metric(mname, v[2], v[1])
        end
    end

    return output
end

function pm_procstat_one(line, expected, mname, help, mtype)
    local output = ''
    local label = ''
    local value = ''
    label, value = line:match('(' .. expected .. ') (%d+)')
    if label ~= expected then return '' end
    mname = 'node_' .. mname
    value = tonumber(value)
    output = output .. '# HELP ' .. mname .. ' ' .. help .. '\n'
    output = output .. '# TYPE ' .. mname .. ' ' .. mtype .. '\n'
    output = output .. pm_metric(mname, nil, value)

    return output
end

function pm_procstat()
    local f = io.open('/proc/stat', 'rb')
    if not f then return '' end

    local output = '# HELP node_cpu Seconds the cpus spent in each mode.\n'
    output = output .. '# TYPE node_cpu counter\n'

    -- First line is overall CPU stats - ignore
    _ = f:read()
    local cpu_attrs = {'user', 'nice', 'system', 'idle', 'iowait', 'irq',
                       'softirq', 'steal', 'guest', 'guest_nice'}
    local _sc_clk_tck = 100 -- Should be read from sysconf
    local line = f:read()
    while string.sub(line, 1, 3) == 'cpu' do
        local stats = {line:match('(cpu%d+) (%d+) (%d+) (%d+) (%d+)( ?%d*)( ?%d*)( ?%d*)( ?%d*)( ?%d*)( ?%d*)')}
        for k, mode in pairs(cpu_attrs) do
            local v = tonumber(stats[k + 1])
            if not v then break end

            local attrs = {cpu=stats[1], mode=mode}
            output = output .. pm_metric('node_cpu', attrs, v / _sc_clk_tck)
        end
        line = f:read()
    end

    output = output .. pm_procstat_one(line, 'intr', 'intr', 'Total number of interrupts serviced.', 'counter')
    line = f:read()
    output = output .. pm_procstat_one(line, 'ctxt', 'context_switches', 'Total number of context switches.', 'counter')
    line = f:read()
    output = output .. pm_procstat_one(line, 'btime', 'boot_time', 'Node boot time, in unixtime.', 'gauge')
    line = f:read()
    output = output .. pm_procstat_one(line, 'processes', 'forks', 'Total number of forks.', 'counter')
    line = f:read()
    output = output .. pm_procstat_one(line, 'procs_running', 'procs_running', 'Number of processes in runnable state.', 'gauge')
    line = f:read()
    output = output .. pm_procstat_one(line, 'procs_blocked', 'procs_blocked', 'Number of processes blocked waiting for I/O to complete.', 'gauge')

    f:close()
    return output
end

function pm_meminfo()
    local f = io.open('/proc/meminfo', 'rb')
    if not f then return '' end

    local output = ''
    for line in f:lines() do
        local field, value, unit = line:match('(.+): +(%d+)( ?k?B?)')
        if not field and not value then break end

        value = tonumber(value)
        if unit == ' kB' then value = value * 1024 end

        field = field:gsub('%((.+)%)', '_%1')
        local mname = 'node_memory_' .. field
        output = output .. '# HELP ' .. mname .. ' Memory information field ' .. field .. '\n'
        output = output .. '# TYPE ' .. mname .. ' gauge\n'
        output = output .. pm_metric(mname, nil, value)
    end

    return output
end

function pm_process_procstat()
    -- Metrics about this process
    local f = io.open('/proc/self/stat', 'rb')
    if not f then return '' end

    local contents = f:read()
    local pattern = '(%d+) %((.-)%) (.)' .. string.rep(" ([-%d]+)", 21)
    local data = {contents:match(pattern)}
    local fields = {utime=14, stime=15, vsize=23, rss=24}

    local cputime = (data[fields.utime] + data[fields.stime]) / 100
    local output = '# HELP process_cpu_seconds_total Total user and system CPU time spent in seconds.\n'
    output = output .. '# TYPE process_cpu_seconds_total counter\n'
    output = output .. pm_metric('process_cpu_seconds_total', nil, cputime)

    local rss = data[fields.rss] * 4096
    output = output .. '# HELP process_resident_memory_bytes Resident memory size in bytes.\n'
    output = output .. '# TYPE process_resident_memory_bytes gauge\n'
    output = output .. pm_metric('process_resident_memory_bytes', nil, rss)

    output = output .. '# HELP process_virtual_memory_bytes Virtual memory size in bytes.\n'
    output = output .. '# TYPE process_virtual_memory_bytes gauge\n'
    output = output .. pm_metric('process_virtual_memory_bytes', nil, data[fields.vsize])

    return output
end

function prometheus_metrics_handler(lul_request, lul_parameters, lul_outputformat)
    local output = pm_device_metrics()

    output = output .. pm_procstat()
    output = output .. pm_meminfo()
    output = output .. pm_process_procstat()
    return output, 'text/plain'
end

function initstatus(lul_device)
    luup.log("PrometheusMetrics initstatus("..lul_device..") starting")
    luup.register_handler("prometheus_metrics_handler", "prometheus_metrics")
end

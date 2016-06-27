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

function tcontains(table, test)
    for k, v in pairs(table) do
        if v == test then
            return true
        end
    end
    return false
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

function prometheus_metric(device_cats, service, variable, metric_name, help, mtype)
    -- Return a fully formatted metric for all devices in device_cat
    if not mtype then mtype = 'gauge' end

    local output = ''

    for device_num, device in pairs(luup.devices) do
        if tcontains(device_cats, device.category_num) then
            local v = luup.variable_get(service, variable, device_num)
            if v then
                local a = pm_attributes(device_num, device)
                output = output .. pm_metric(metric_name, a, v)
            end
        end
    end

    if output == '' then
        return output
    end

    output = '# TYPE ' .. metric_name .. ' ' .. mtype .. "\n" .. output
    output = '# HELP ' .. metric_name .. ' ' .. help .. "\n" .. output

    return output
end

function pm_temperature()
    return prometheus_metric(
        {5, 17},
        'urn:upnp-org:serviceId:TemperatureSensor1',
        'CurrentTemperature',
        'temperature_c',
        'Temperature in degrees Celsius'
    )
end

function pm_light_sensors()
    return prometheus_metric(
        {18},
        'urn:micasaverde-com:serviceId:LightSensor1',
        'CurrentLevel',
        'light_lux',
        'Light level in lux'
    )
end

function pm_humidity()
    return prometheus_metric(
        {16},
        'urn:micasaverde-com:serviceId:HumiditySensor1',
        'CurrentLevel',
        'humidity_relative',
        'Relative humidity (0..100)'
    )
end

function pm_light_bulbs()
    return prometheus_metric(
        {2},
        'urn:upnp-org:serviceId:Dimming1',
        'LoadLevelStatus',
        'dimmable_load_percent',
        'Load level of a dimmable device (0..100)'
    )
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
function prometheus_metrics_handler(lul_request, lul_parameters, lul_outputformat)
    local output = ''
    -- Unfortunately the Prometheus output format requires all lines for
    -- a given metric must be in one group, so we end up iterating luup.devices
    -- once for each device type that we wan to handle.
    output = output .. pm_temperature()
    output = output .. pm_light_sensors()
    output = output .. pm_humidity()
    output = output .. pm_light_bulbs()
    output = output .. pm_procstat()
    return output, 'text/plain'
end

function initstatus(lul_device)
    luup.log("PrometheusMetrics initstatus("..lul_device..") starting")
    luup.register_handler("prometheus_metrics_handler", "prometheus_metrics")
end

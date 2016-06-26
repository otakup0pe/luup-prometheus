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

function pm_light()
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

function prometheus_metrics_handler(lul_request, lul_parameters, lul_outputformat)
    local output = ''
    -- Unfortunately the Prometheus output format requires all lines for
    -- a given metric must be in one group, so we end up iterating luup.devices
    -- once for each device type that we wan to handle.
    output = output .. pm_temperature()
    output = output .. pm_light()
    output = output .. pm_humidity()
    return output, 'text/plain'
end

function initstatus(lul_device)
    luup.log("PrometheusMetrics initstatus("..lul_device..") starting")
    luup.register_handler("prometheus_metrics_handler", "prometheus_metrics")
end

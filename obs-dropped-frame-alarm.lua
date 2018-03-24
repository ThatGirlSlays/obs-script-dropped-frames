obs = obslua
bit = require("bit")

function script_log(message)
	obs.script_log(obs.LOG_INFO, message)
end

local sample_rate = 1000
local graph_width = 600
local graph_height = 200
local graph_margin = 0

local sample_seconds = 60
local alarm_level = 0.2
local alarm_source = ""
local mode = "live"

local frame_history = {}
local alarm_active = false

local fake_frames = 0
local fake_dropped = 0

function update_frames()
	local frames = 0
	local dropped = 0

	if mode == "test" then
		fake_frames = fake_frames + math.random(19,21)
		frames = fake_frames
		fake_dropped = fake_dropped + math.random(0, 20)
		dropped = fake_dropped
	else
		local output = obs.obs_get_output_by_name("simple_stream")
		if output ~= nil then
			frames = obs.obs_output_get_total_frames(output)
			dropped = obs.obs_output_get_frames_dropped(output)
			obs.obs_output_release(output)
		end
	end

	--script_log(dropped .. "/" .. frames)

	table.insert(frame_history, 1,
		{frames = frames, dropped = dropped})

	local sample_size = (sample_seconds * 1000 / sample_rate) + 1
	-- + 1 so that we get n differences
	while #frame_history > sample_size do
		table.remove(frame_history)
	end

	check_alarm()
end

function check_alarm()
	if #frame_history < 2 then
		return
	end
	local newest = frame_history[1]
	local oldest = frame_history[#frame_history]
	local frames = newest.frames - oldest.frames
	local dropped = newest.dropped - oldest.dropped
	if frames < 1 then
		return
	end
	local rate = dropped/frames
	--script_log(dropped .. "/" .. frames .. " " .. rate)
	if rate > alarm_level then
		if not alarm_active then
			play_alarm()
			alarm_active = true
			obs.timer_add(play_alarm, 60*1000)
		end
	else
		if alarm_active then
			alarm_active = false
			obs.timer_remove(play_alarm)
		end
	end
end

function activate_alarm()
	set_alarm_visible(true)
	obs.remove_current_callback()
end

function play_alarm()
	set_alarm_visible(false)
	obs.timer_add(activate_alarm, 500)
end

function set_alarm_visible(visible)
	if alarm_source ~= nil then
		local current_source = obs.obs_frontend_get_current_scene()
		local current_scene = obs.obs_scene_from_source(current_source)
		obs.obs_source_release(current_source)
		local item = obs.obs_scene_find_source(current_scene, alarm_source)
		if item ~= nil then
			obs.obs_sceneitem_set_visible(item, visible)
		end
	end
end

function extract_series(table, attribute)
	local series = {}
	for i = 1,#table-1 do
		series[i] = table[i][attribute] - table[i+1][attribute]
	end
	return series
end

function table_max(table)
	local best = table[1] or 0
	for _,v in ipairs(table) do
		best = math.max(best, v)
	end
	return best
end

function sample_modified(props, p, settings)
	return false -- text controls refreshing properties reset focus on each character
end

function alarm_modified(props, p, settings)
	return false -- text controls refreshing properties reset focus on each character
end

function test_alarm(props, p, set)
	play_alarm()
	return true
end

function dump_obs()
	local keys = {}
	for key,value in pairs(obs) do
		keys[#keys+1] = key
	end
	table.sort(keys)
	local output = {}
	for i,key in ipairs(keys) do
		local value = type(obs[key])
		if value == 'number' then
			value = obs[key]
		elseif value == 'string' then
			value = '"' .. obs[key] .. '"'
		end
		output[i] = key .. " : " .. value
	end
	script_log(table.concat(output, "\n"))
end

-- A function named script_description returns the description shown to
-- the user
local description = [[Play an alarm if you start dropping frames
]]
function script_description()
	return description
end

-- A function named script_properties defines the properties that the user
-- can change for the entire script module itself
function script_properties()
	script_log("props")

	local props = obs.obs_properties_create()

	local m = obs.obs_properties_add_list(props, "mode", "Mode", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	obs.obs_property_list_add_string(m, "Live", "live")
	obs.obs_property_list_add_string(m, "Test", "test")

	local ss = obs.obs_properties_add_int(props, "sample_seconds", "Sample Seconds", 1, 300, 5) 
	obs.obs_property_set_modified_callback(ss, sample_modified)

	local al = obs.obs_properties_add_int(props, "alarm_level", "Alarm Level", 0, 100, 5)
	obs.obs_property_set_modified_callback(ss, level_modified)

	local p = obs.obs_properties_add_list(props, "alarm_source", "Alarm Media Source", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
	local sources = obs.obs_enum_sources()
	if sources ~= nil then
		for _, source in ipairs(sources) do
			source_id = obs.obs_source_get_id(source)
			if source_id == "ffmpeg_source" then
				local name = obs.obs_source_get_name(source)
				obs.obs_property_list_add_string(p, name, name)
			end
		end
	end
	obs.source_list_release(sources)

	local ref = obs.obs_properties_add_button(props, "test_alarm", "Test Alarm", test_alarm)
	obs.obs_property_set_long_description(ref, "Updated calculated fields with changes from text controls.")

	return props
end

-- A function named script_defaults will be called to set the default settings
function script_defaults(settings)
	script_log("defaults")

	obs.obs_data_set_default_int(settings, "sample_seconds", 60)
	obs.obs_data_set_default_int(settings, "alarm_level", 20)
	obs.obs_data_set_default_string(settings, "alarm_source", "")
	obs.obs_data_set_default_string(settings, "mode", "live")
end

--
-- A function named script_update will be called when settings are changed
function script_update(settings)
	script_log("update")
	my_settings = settings

	sample_seconds = obs.obs_data_get_int(settings, "sample_seconds")
	alarm_level = obs.obs_data_get_int(settings, "alarm_level") / 100
	alarm_source = obs.obs_data_get_string(settings, "alarm_source")
	mode = obs.obs_data_get_string(settings, "mode")
end

-- a function named script_load will be called on startup
function script_load(settings)
	script_log("load")
	--dump_obs()
	obs.timer_add(update_frames, sample_rate)
end

function script_unload()
	-- this crashes OBS
	--obs.timer_remove(update_frames)
end

source_def = {}
source_def.id = "lua_dropped_frame_graph_source"
source_def.output_flags = bit.bor(obs.OBS_SOURCE_VIDEO, obs.OBS_SOURCE_CUSTOM_DRAW)

source_def.get_name = function()
	return "Dropped Frame Graph"
end

source_def.create = function(source, settings)
	return nil
end

source_def.destroy = function(data)
end

function fill(color)
	local effect_solid = obs.obs_get_base_effect(obs.OBS_EFFECT_SOLID)
	local color_param = obs.gs_effect_get_param_by_name(effect_solid, "color");

	obs.gs_effect_set_color(color_param, color)

	while obs.gs_effect_loop(effect_solid, "Solid") do
		obs.gs_draw(obs.GS_TRISTRIP, 0, 0)
	end
end

function stroke(color)
	local effect_solid = obs.obs_get_base_effect(obs.OBS_EFFECT_SOLID)
	local color_param = obs.gs_effect_get_param_by_name(effect_solid, "color");

	obs.gs_effect_set_color(color_param, color)

	while obs.gs_effect_loop(effect_solid, "Solid") do
		obs.gs_draw(obs.GS_LINESTRIP, 0, 0)
	end
end

source_def.video_render = function(data, effect)
	obs.gs_blend_state_push()
	obs.gs_reset_blend_state()

	local effect_solid = obs.obs_get_base_effect(obs.OBS_EFFECT_SOLID)
	local color_param = obs.gs_effect_get_param_by_name(effect_solid, "color");

	obs.gs_matrix_push()
	obs.gs_matrix_translate3f(graph_margin, graph_margin, 0)
	obs.gs_matrix_scale3f(graph_width - graph_margin*2, graph_height - graph_margin*2, 1)
	obs.gs_matrix_translate3f(0, 1, 0)
	obs.gs_matrix_scale3f(1, -1, 1)

	if #frame_history > 1 then
		local frames = extract_series(frame_history, "frames")

		obs.gs_matrix_push()
		obs.gs_matrix_translate3f(1, 0, 0)
		obs.gs_matrix_scale3f(-1, 1, 1)
		obs.gs_matrix_scale3f(1/(#frames-1), 1/table_max(frames), 1)

		local dropped = extract_series(frame_history, "dropped")

		obs.gs_render_start(true)

		for i,d in ipairs(dropped) do
			obs.gs_vertex2f(i-1, d)
			obs.gs_vertex2f(i-1, 0)
		end

		obs.gs_effect_set_color(color_param, 0xffff0000)
		while obs.gs_effect_loop(effect_solid, "Solid") do
			obs.gs_render_stop(obs.GS_TRISTRIP)
		end

		obs.gs_matrix_pop()
	end

	obs.gs_matrix_pop()

	obs.gs_blend_state_pop()
end

source_def.get_width = function(data)
	return graph_width
end

source_def.get_height = function(data)
	return graph_height
end

obs.obs_register_source(source_def)

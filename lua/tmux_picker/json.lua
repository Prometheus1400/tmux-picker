local M = {}

local function utf8(code)
	if code < 0x80 then
		return string.char(code)
	elseif code < 0x800 then
		return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
	elseif code < 0x10000 then
		return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
	end
	return string.char(
		0xF0 + math.floor(code / 0x40000),
		0x80 + math.floor(code / 0x1000) % 0x40,
		0x80 + math.floor(code / 0x40) % 0x40,
		0x80 + code % 0x40
	)
end

local function skip_space(text, index)
	while text:sub(index, index):match("%s") do
		index = index + 1
	end
	return index
end

local parse_value

local function parse_string(text, index)
	if text:sub(index, index) ~= '"' then
		return nil, index, "expected string"
	end
	index = index + 1
	local output = {}
	while index <= #text do
		local char = text:sub(index, index)
		if char == '"' then
			return table.concat(output), index + 1
		elseif char == "\\" then
			local escaped = text:sub(index + 1, index + 1)
			local values = {
				['"'] = '"',
				["\\"] = "\\",
				["/"] = "/",
				b = "\b",
				f = "\f",
				n = "\n",
				r = "\r",
				t = "\t",
			}
			if escaped == "u" then
				local hex = text:sub(index + 2, index + 5)
				if not hex:match("^%x%x%x%x$") then
					return nil, index, "invalid unicode escape"
				end
				local code = tonumber(hex, 16)
				index = index + 6
				if code >= 0xD800 and code <= 0xDBFF and text:sub(index, index + 1) == "\\u" then
					local low = tonumber(text:sub(index + 2, index + 5), 16)
					if low and low >= 0xDC00 and low <= 0xDFFF then
						code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
						index = index + 6
					end
				end
				output[#output + 1] = utf8(code)
			elseif values[escaped] then
				output[#output + 1] = values[escaped]
				index = index + 2
			else
				return nil, index, "invalid escape"
			end
		else
			output[#output + 1] = char
			index = index + 1
		end
	end
	return nil, index, "unterminated string"
end

local function parse_array(text, index)
	local output = {}
	index = skip_space(text, index + 1)
	if text:sub(index, index) == "]" then
		return output, index + 1
	end
	while index <= #text do
		local value, err
		value, index, err = parse_value(text, index)
		if err then
			return nil, index, err
		end
		output[#output + 1] = value
		index = skip_space(text, index)
		local separator = text:sub(index, index)
		if separator == "]" then
			return output, index + 1
		elseif separator ~= "," then
			return nil, index, "expected comma"
		end
		index = skip_space(text, index + 1)
	end
	return nil, index, "unterminated array"
end

local function parse_object(text, index)
	local output = {}
	index = skip_space(text, index + 1)
	if text:sub(index, index) == "}" then
		return output, index + 1
	end
	while index <= #text do
		local key, err
		key, index, err = parse_string(text, index)
		if err then
			return nil, index, err
		end
		index = skip_space(text, index)
		if text:sub(index, index) ~= ":" then
			return nil, index, "expected colon"
		end
		local value
		value, index, err = parse_value(text, skip_space(text, index + 1))
		if err then
			return nil, index, err
		end
		output[key] = value
		index = skip_space(text, index)
		local separator = text:sub(index, index)
		if separator == "}" then
			return output, index + 1
		elseif separator ~= "," then
			return nil, index, "expected comma"
		end
		index = skip_space(text, index + 1)
	end
	return nil, index, "unterminated object"
end

parse_value = function(text, index)
	index = skip_space(text, index)
	local char = text:sub(index, index)
	if char == '"' then
		return parse_string(text, index)
	elseif char == "{" then
		return parse_object(text, index)
	elseif char == "[" then
		return parse_array(text, index)
	elseif text:sub(index, index + 3) == "null" then
		return nil, index + 4
	elseif text:sub(index, index + 3) == "true" then
		return true, index + 4
	elseif text:sub(index, index + 4) == "false" then
		return false, index + 5
	end
	local number = text:match("^%-?%d+%.?%d*[eE]?[+-]?%d*", index)
	if number and number ~= "" then
		return tonumber(number), index + #number
	end
	return nil, index, "invalid value"
end

function M.decode(text)
	if type(text) ~= "string" or text == "" then
		return nil, "empty input"
	end
	local value, index, err = parse_value(text, 1)
	if err then
		return nil, err
	end
	if skip_space(text, index) <= #text then
		return nil, "trailing content"
	end
	return value
end

function M.read(path)
	local handle = io.open(path, "r")
	if not handle then
		return nil
	end
	local value = handle:read("*a")
	handle:close()
	return M.decode(value)
end

return M

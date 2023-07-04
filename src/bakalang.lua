bakalang = {}

-- returns the line and index of a line that corresponds to the given index
function bakalang.getLineAndIndex(str, index)
  local lineIndex = 1
  local lineStart = 1
  local lineEnd = str:find("\n")

  while lineEnd do
    if index <= lineEnd then
      local line = str:sub(lineStart, lineEnd-1)
      local pos = index - lineStart + 1
      return line, lineIndex, pos
    end
    lineIndex = lineIndex + 1
    lineStart = lineEnd + 1
    lineEnd = str:find("\n", lineStart)
  end

  -- Handle last line (which may not end with a newline)
  if index <= #str then
    local line = str:sub(lineStart)
    local pos = index - lineStart + 1
    return line, lineIndex, pos
  end

  return nil, nil, nil  -- Index out of bounds
end

-- finds the macro symbols in a string, usually an entire source file
function bakalang.find_macro_symbol(str)
	local symbols = {}
	local escaped = false
	local in_something = nil

	local comment_handler = bakalang.get_comment_handler()

  	for i = 1, #str do
    	local c = str:sub(i, i)
		if comment_handler(c) then
		elseif c == '\\' then
			escaped = true
		elseif in_something then
			if escaped then
				escaped = false
			elseif c == in_something then
				in_something = nil
			end
		else
			if c == '"' or c == "'" or c == '`' then
				in_something = c
			elseif c == bakalang.macro_symbol then
				symbols[#symbols + 1] = i
			end
		end
  	end
	return symbols
end

function getPrintingPosition(str, tabSize, index)
  local pos = 1
  local i = 1
  
  while i <= index do
    local c = str:sub(i, i)
    if c == "\t" then
      pos = pos + (tabSize - (pos % tabSize))
    else
      pos = pos + 1
    end
    i = i + 1
  end
  
  return pos
end

function bakalang.print_info(line, nline, index)
	print(line, '{'..global_iteration..'}')
	
	print((" "):rep((getPrintingPosition(line, 8, index - 1)))..'^', "("..nline..")")
end

-- searches for the index of the end parenthesis after the start one
function bakalang.search_for_end_parenthesis(code, firstp)
	local escaped = false
	local in_something = nil

  	for i = firstp, #code do
    	local c = code:sub(i, i)
		if c == '\\' then
			escaped = true
		elseif in_something then
			if escaped then
				escaped = false
			elseif c == in_something then
				in_something = nil
			end
		else
			if c == '"' or c == "'" or c == '`' then
				in_something = c
			elseif c == ')' then
				return i
			end
		end
  	end
end

-- returns the arguments separated by commas
function bakalang.get_function_arguments(code, s, f)
	local escaped = false
	local in_something = nil
	local arguments = {}

  	for i = s, f do
    	local c = code:sub(i, i)
		if c == '\\' then
			escaped = true
		elseif in_something then
			if escaped then
				escaped = false
			elseif c == in_something then
				in_something = nil
			end
		else
			if c == '"' or c == "'" or c == '`' then
				in_something = c
			elseif c == ',' then
				arguments[#arguments + 1] = code:sub(s, i - 1)
				s = i + 1
			end
		end
  	end
	arguments[#arguments + 1] = code:sub(s, f)
	return arguments
end

function bakalang.info(text, code, v, filename)
	print(text .. '['..filename..']' .. ':')
	bakalang.print_info(bakalang.getLineAndIndex(code, v))
end

function bakalang.exinfo(text, code, v, filename)
	bakalang.info(text, code, v, filename)
	os.exit()
end

-- replaces the \` in the string with a `
function bakalang.replace_backslash_backtick(str)
	return string.gsub(str, '\\`', '`')
end

function bakalang.deep_copy_table(original_table)
    local copy_table = {}
  
    for k, v in pairs(original_table) do
        if type(v) == "table" then
            copy_table[k] = bakalang.deep_copy_table(v)
        else
            copy_table[k] = v
        end
    end
  
    return copy_table
end

-- this is where the magic happens
-- replaces text and returns the new_text and a environment, this environment's location is not set here
function bakalang.run_macro(code, flags, call, environment, offset, filename)
	own_environment = environment or {}
	own_environment = bakalang.deep_copy_table(own_environment)

	portion = code:sub(call.first_char + offset, call.last_char + offset)
	success, new_text = pcall(bakalang.macro_functions[call.name], code, flags, call, own_environment, environment, offset, portion)
	if not success then
		bakalang.exinfo("["..bakalang.macro_symbol..call.name.."] "..new_text, code, call.first_char + offset, filename)
	end
	if type(new_text) ~= 'string' then
		bakalang.exinfo("["..bakalang.macro_symbol..call.name.."] new text returned not of type string", code, call.first_char + offset, filename)
	end
	return new_text, own_environment
end

-- process the code searching for macro function calls
-- flags indicates what to do, for example, a flag can be header = true to indicate that this is a .h file
-- environments is a collection of environments (returned by process_code function), each environment contains information that can be accessed later by other macro function calls
function bakalang.process_code_once(code, environments, flags, filename)
	local calls = {}

	local flist = bakalang.find_macro_symbol(code)
	for i, v in ipairs(flist) do
		local lstart, lend, func_name = string.find(code, "^"..bakalang.macro_symbol.."([%a_][%w_]*)%s*%(", v)

		if bakalang.macro_functions[func_name] == nil then
			bakalang.exinfo("unknown function called", code, v, filename)
		end

		if not lstart then
			bakalang.exinfo("expected function call here (after "..bakalang.macro_symbol..")", code, v, filename)
		else -- found function call
			local ep = bakalang.search_for_end_parenthesis(code, lend)
			if not ep then
				bakalang.exinfo("expected ')' after function call", code, v, filename)
			end

			-- getting arguments
			local fcall = {}
			fcall.first_char = lstart
			fcall.last_char = ep
			fcall.name = func_name
			fcall.args = {}

			--print("whole function call:", code:sub(lstart, ep))
			--print("getting arguments of:", code:sub(lend + 1, ep - 1))
			local args = bakalang.get_function_arguments(code, lend + 1, ep - 1)
			for j, arg in ipairs(args) do
				if j == #args and string.find(arg, "^%s*$") then
					break
				end
				local l_arg, r_arg, farg = string.find(arg, "^%s*([%a_][%w_]*)%s*$")
				if not l_arg then
					l_arg, r_arg, farg = string.find(arg, "^%s*`(.*)`%s*$")
					if not l_arg then
						_, _, with_first_non_whitespace = string.find(arg, "^%s*(.*)$")
						bakalang.exinfo("expected string argument", code, string.find(code, with_first_non_whitespace, lend + 1, true), filename)
					end
				end
				-- append argument to call
				fcall.args[#fcall.args + 1] = bakalang.replace_backslash_backtick(farg)
			end
			calls[#calls + 1] = fcall
		end
	end

	local n_environments = {}
	local offset = 0 -- offset to call indices
	for i, v in ipairs(calls) do
		--[[
		print("Call [from "..v.first_char..", to "..v.last_char.."]")
		print("\tFull form:"..code:sub(v.first_char, v.last_char))
		print("\tName:"..v.name)
		print("\tArguments("..#v.args.."):")
		for k, arg in ipairs(v.args) do
			print("\t\t"..arg)
		end
		--]]

		-- getting environment
		local env_index = nil
		--print('looking for environments:')
		for k, en in ipairs(environments) do
			--print(v.first_char, v.last_char, en.first_char, en.last_char)
			if v.first_char >= en.first_char and v.last_char <= en.last_char then
				env_index = k
				break
			end
		end
		-- running macro
		local new_text, environment = bakalang.run_macro(code, flags, v, environments[env_index], offset, filename)
		-- replacing text
		code = code:sub(1, v.first_char - 1 + offset)..new_text..code:sub(v.last_char + 1 + offset)
		-- getting offset
		if #new_text > 0 then
			-- setting new environment start and end position
			environment.first_char = v.first_char + offset
			environment.last_char = environment.first_char + #new_text - 1

			-- expanding parent_environment to accomodate for the new code
			if env_index ~= nil then
				environments[env_index].last_char =	math.max(environments[env_index].last_char,	v.first_char + #new_text - 1)
			end
			--print('!@#$%: ', #new_text, v.first_char, v.last_char)
			--print(offset, environment.first_char, environment.last_char)
			-- adding new environment to the return value
			n_environments[#n_environments + 1] = environment
		end
		offset = offset + (#new_text - (v.last_char - v.first_char + 1))
	end
	return code, n_environments
end

-- process a source file until there is no macro function call left, this can do bakalang.max_iterations iterations before breaking
function bakalang.process_code(code, flags, filename)
	if bakalang.get_comment_handler == nil then
		error("bakalang.get_comment_handler isn't defined")
	end
	if bakalang.global_environment == nil then
		error("bakalang.global_environment isn't defined")
	end
	if bakalang.macro_functions == nil then
		error("bakalang.global_environment isn't defined") 
	end
	bakalang.macro_symbol = bakalang.macro_symbol or '@'
	bakalang.max_iterations = bakalang.max_iterations or 1000

	local ncode = code
	local n_environments = {{first_char = 1, last_char = #code}}

	--print("Original text:")
	--print(code)
	global_iteration = 0
	while true do
		ncode, n_environments = bakalang.process_code_once(ncode, n_environments, flags, filename)
		--print("Resulting code:")
		--print(ncode)
		if #n_environments == 0 then
			break
		end
		if global_iteration > bakalang.max_iterations then
			break
		end
		global_iteration = global_iteration + 1
	end
	return ncode
end

-- macro functions are lua functions that take the following arguments:
--  code, flags, call, own_environment, parent_environment, offset, portion
--  ^ the whole code that is being change
--        ^ various flags not dependant in the code
--              ^ a call object, an object that has a information about the location, name, and arguments passed to the macro
--                     ^ environment passed to children macros (list of properties that are hierarchily altered by parent macros)
--                                      ^ parent environment, this environment is passed to the next macro function call (may be nil)
--                                                          ^ offset to the actual code, since the code is being modified (from previous macro calls) the call object may not have the exact position of the call macro anymore, so, to get that position the offset is provided
--                                                                  ^ the current portion of code that is being changed (the macro call with everything, including whitespaces)

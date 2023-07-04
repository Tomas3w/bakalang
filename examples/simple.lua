-- this is a simple example code it uses the library to parse a replace the single macro function hello()
-- it implements a simple comment handler that allows for skipping text after ;
-- it also defines an empty global_environment and it process code directly from a string
require 'bakalang'

function hello()
	return 'Hello world'
end

function bakalang.get_comment_handler()
	local obj = {}
	obj.in_comment = false
	function obj.__call(o, c)
		if c == ';' then
			o.in_comment = true
		end
		if c == '\n' then
			o.in_comment = false
		end
		return o.in_comment
	end
	setmetatable(obj, obj)
	return obj
end

function main()
	bakalang.macro_functions = {hello = hello}
	bakalang.global_environment = {}
	local result = bakalang.process_code('@hello()! ; commnet ignored @hello()', {}, 'filename')
	print(result)
end

main()


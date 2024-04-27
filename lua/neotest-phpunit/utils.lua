local logger = require("neotest.logging")

local M = {}
local separator = "::"

---Generate an id which we can use to match Treesitter queries and PHPUnit tests
---@param position neotest.Position The position to return an ID for
---@param namespace neotest.Position[] Any namespaces the position is within
---@return string
M.make_test_id = function(position)
  -- Treesitter starts line numbers from 0 so we add 1
  local id = position.path .. separator .. (tonumber(position.range[1]) + 1)

  logger.info("Path to test file:", { position.path })
  logger.info("Treesitter id:", { id })

  return id
end

---Recursively iterate through a deeply nested table to obtain specified keys
---@param data_table table
---@param key string
---@param output_table table
---@return table
local function iterate_key(data_table, key, output_table)
  if type(data_table) == "table" then
    for k, v in pairs(data_table) do
      if key == k then
        table.insert(output_table, v)
      end
      iterate_key(v, key, output_table)
    end
  end
  return output_table
end

---Extract the failure messages from the tests
---@param tests table,
---@return table
local function errors_or_fails(tests)
  local errors_fails = {}

  iterate_key(tests, "error", errors_fails)
  iterate_key(tests, "failure", errors_fails)

  return errors_fails
end

---Make the outputs for a given test
---@param test table
---@param output_file string
---@return table
local function make_outputs(test, output_file)
  local test_output = {
    status = "passed",
    short = "Test passed",
    output_file = output_file,
  }

  local errors = errors_or_fails(test)
  if #errors > 0 then
    local shorts = {}
    local messages = {}
    for _, v in ipairs(errors) do
      table.insert(shorts, v[1])
      table.insert(messages, { message = v[1] })
    end

    test_output.status = "failed"
    test_output.short = table.concat(shorts, "\n\n")
    test_output.errors = messages
  end

  return test_output
end

---Iterate through test results and create a table of test IDs and outputs
---@param tests table
---@param output_file string
---@param output_table table
---@return table
local function iterate_test_outputs(tests, output_file, output_table)
  for _, v in ipairs(tests) do
    local test_output = make_outputs(v, output_file)
    output_table[v.file .. "::" .. v.name] = test_output
  end

  return output_table
end

local function find_test_cases(parsed_xml, file, result)
  if type(parsed_xml) == "table" then
    for k, v in pairs(parsed_xml) do
      if not v[1] then
        v = { v }
      end

      for _, item in ipairs(v) do
        if item._attr and item._attr.file then
          file = item._attr.file
        end

        if k == "testsuite" and string.find(item._attr.name, "::") then
          table.insert(result, {
            file = file,
            name = string.gsub(item._attr.name, ".+::", ""),
            data = item,
          })
        elseif k == "testcase" then
          table.insert(result, {
            file = file,
            name = item._attr.name,
            data = item,
          })
        else
          find_test_cases(item, file, result)
        end
      end
    end
  end

  return result
end

---Get the test results from the parsed xml
---@param parsed_xml_output table
---@param output_file string
---@return neotest.Result[]
M.get_test_results = function(parsed_xml_output, output_file)
  local tests = find_test_cases(parsed_xml_output, "", {})
  return iterate_test_outputs(tests, output_file, {})
end

local function get_id_table(tree, result)
  if tree[1] then
    for _, v in ipairs(tree) do
      get_id_table(v, result)
    end
  elseif tree.type == "test" then
    result[tree.path .. "::" .. tree.name] = tree.id
  end
  return result
end

M.get_id_table = function(tree)
  return get_id_table(tree, {})
end

M.remap_result = function(output_table, id_table)
  local result = {}
  for k, v in pairs(id_table) do
    result[v] = output_table[k]
  end
  return result
end

return M

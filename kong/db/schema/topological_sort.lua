local CORE_ENTITIES = require("kong.constants").CORE_ENTITIES
local table_insert = table.insert


local sort_core_first do
  local CORE_SCORE = {}
  for _, v in ipairs(CORE_ENTITIES) do
    CORE_SCORE[v] = 1
  end
  CORE_SCORE["workspaces"] = 2

  sort_core_first = function(a, b)
    local sa = CORE_SCORE[a.name] or 0
    local sb = CORE_SCORE[b.name] or 0
    if sa == sb then
      return a.name < b.name
    end
    return sa < sb
  end
end

-- Given an array of schemas, build a table were the keys are schemas and the values are
-- the list of schemas with foreign keys pointing to them
-- @tparam array schemas an array of schemas
-- @treturn table a map with schemas in the keys and arrays of neighbors in the values
-- @usage
-- local res = build_neighbors_map({ services, routes, plugins, consumers })
--
-- assert.same({ [services] = { routes, plugins },
--               [routes] = { plugins },
--               [consumers] = { plugins }
--             }, res)
local function build_neighbors_map(schemas)
  local schemas_by_name = {}
  local s
  for i = 1, #schemas do
    s = schemas[i]
    schemas_by_name[s.name] = s
  end

  local res = {}
  local source, destination

  for i = 1, #schemas do
    source = schemas[i] -- routes
    for _, field in source:each_field() do
      if field.type == "foreign"  then
        destination = schemas_by_name[field.reference] -- services
        if destination then
          res[destination] = res[destination] or {}
          table_insert(res[destination], source)
        end
      end
    end
  end

  return res
end


-- aux function for topological_sort
local function visit(current, neighbors_map, visited, marked, sorted)
  if visited[current] then
    return true
  end

  if marked[current] then
    return nil, "Cycle detected, cannot sort topologically"
  end

  marked[current] = true

  local schemas_pointing_to_current = neighbors_map[current]
  if schemas_pointing_to_current then
    local neighbor, ok, err
    for i = 1, #schemas_pointing_to_current do
      neighbor = schemas_pointing_to_current[i]
      ok, err = visit(neighbor, neighbors_map, visited, marked, sorted)
      if not ok then
        return nil, err
      end
    end
  end

  marked[current] = false

  visited[current] = true

  table_insert(sorted, 1, current)

  return true
end


-- Given an array of schemas, return it sorted so that:
--
-- * If schema B has a foreign key to A, then B appears after A
-- * When there's no foreign keys, core schemas appear before plugin entities
-- * If none of the rules above apply, schemas are sorted alphabetically by name
--
-- The function returns an error if cycles are found in the schemas
-- (i.e. A has a foreign key to B and B to A)
--
-- @tparam array schemas an array with zero or more schemas
-- @treturn array|nil an array of schemas sorted topologically, or nil if cycle was found
-- @treturn nil|string nil if the schemas were sorted, or a message if a cycle was found
-- @usage
-- local res = topological_sort({ services, routes, plugins, consumers })
-- assert.same({ consumers, services, routes, plugins }, res)
local function topological_sort(schemas)
  local sorted = {}
  local visited = {}
  local marked = {}

  local copy = {}
  for i = 1, #schemas do
    copy[i] = schemas[i]
  end
  schemas = copy

  table.sort(schemas, sort_core_first)

  local neighbors_map = build_neighbors_map(schemas)

  local current, ok, err
  for i = 1, #schemas do
    current = schemas[i]
    if not visited[current] and not marked[current] then
      ok, err = visit(current, neighbors_map, visited, marked, sorted)
      if not ok then
        return nil, err
      end
    end
  end

  return sorted
end

return topological_sort

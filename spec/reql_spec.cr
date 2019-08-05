require "./spec_helper"

r.db("test").table_list.for_each do |name|
  r.db("test").table_drop(name)
end.run(Fixtures::TestDB.conn)
describe RethinkDB do
  {{ run("./reql_spec_generator", "spec/rql_test/src/datum/array.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/datum/bool.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/datum/null.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/datum/number.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/datum/object.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/datum/string.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/datum/typeof.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/datum/uuid.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/math_logic/add.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/math_logic/aliases.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/math_logic/div.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/math_logic/floor_ceil_round.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/math_logic/logic.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/math_logic/math.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/math_logic/mod.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/math_logic/mul.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/math_logic/sub.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/aggregation.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/control.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/default.yaml") }}
  {{ run("./reql_spec_generator", "spec/rql_test/src/range.yaml") }}
end

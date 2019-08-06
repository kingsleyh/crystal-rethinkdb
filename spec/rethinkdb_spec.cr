require "./spec_helper"

describe RethinkDB do
  it "successfuly connects to the database" do
    connection = Fixtures::TestDB.conn
    connection.should be_a(RethinkDB::Connection)
  end

  it "raises unknown user error" do
    expect_raises(RethinkDB::ReqlError::ReqlDriverError::ReqlAuthError, "error_code: 17, error: Unknown user") do
      r.connect({host: Fixtures::TestDB.host, user: "owenfvoraewugbjbkv"})
    end
  end

  it "raises unknown user error" do
    expect_raises(RethinkDB::ReqlError::ReqlDriverError::ReqlAuthError, "error_code: 12, error: Wrong password") do
      r.connect({host: Fixtures::TestDB.host, user: "admin", password: "incorrect"})
    end
  end

  it "skip" do
    Generators.random_table_with_entries(20, ->(table : String) {
      r.table(table).skip(10).run(Fixtures::TestDB.conn).to_a.size.should eq(10)
    })
  end

  it "r#json" do
    Generators.random_table do |table|
      r.table_create(table).run Fixtures::TestDB.conn
      5.times do
        # Generate a random document
        document = {
          "id"     => Generators.random_pk,
          "serial" => Generators.random_pk,
          "array"  => Generators.random_array,
          "object" => Generators.random_hash,
        }

        # Insert the raw json, parsed on the DB
        response = r.json(document.to_json).do { |value|
          r.table(table).insert(value, return_changes: true)
        }.run Fixtures::TestDB.conn

        recursive_match(response["changes"][0]["new_val"], document)
      end

      r.table_drop(table).run Fixtures::TestDB.conn
    end
  end

  it "db#table_create(String, **options)" do
    5.times do
      Generators.random_table do |table|
        Generators.random_pk do |pk|
          r.table_create(table).run Fixtures::TestDB.conn, {"primary_key" => pk}
          info = r.table(table).info.run Fixtures::TestDB.conn
          info["primary_key"].should eq pk
          info["name"].should eq table
          r.table_drop(table).run Fixtures::TestDB.conn
        end
      end
    end
  end

  it "table#info(String)" do
    5.times do
      Generators.random_table do |table|
        r.table_create(table).run Fixtures::TestDB.conn
        info = r.table(table).info.run Fixtures::TestDB.conn
        info["type"].should eq "TABLE"
        info["primary_key"].should eq "id"
        info["name"].should eq table
        r.table_drop(table).run Fixtures::TestDB.conn
      end
    end
  end

  describe "listening to a feed" do
    it "table#changes" do
      table = Generators.random_table
      r.table_create(table).run Fixtures::TestDB.conn

      number_of_queries = 6
      result = [] of RethinkDB::QueryResult

      cursor = r.table(table).changes.run Fixtures::TestDB.conn
      spawn do
        cursor.each.with_index do |v, i|
          result << v
          break if i == number_of_queries - 1
        end
      end

      number_of_queries.times do
        r.table(table).insert({:id => Generators.random_pk}).run Fixtures::TestDB.conn
      end

      result.size.should eq number_of_queries
      result.each do |r|
        r.keys.should contain "new_val"
        r.keys.should contain "old_val"
      end

      r.table_drop(table).run Fixtures::TestDB.conn
    end

    it "document#changes" do
      table = Generators.random_table
      r.table_create(table).run Fixtures::TestDB.conn

      pk = Generators.random_pk
      results = [] of RethinkDB::QueryResult
      r.table(table).insert({id: pk, times: 0})
      cursor = r.table(table).get(pk).changes.run Fixtures::TestDB.conn

      spawn do
        cursor.each do |v|
          old_times = v["old_val"]["times"].as_i
          new_times = v["new_val"]["times"].as_i
          new_times.should eq (old_times + 1)
          results << v
        end
      rescue e : RethinkDB::ReqlRunTimeError
        e.to_s.should contain "Changefeed aborted"
      end

      6.times.with_index do |i|
        r.table(table).get(pk).update({times: i + 1}).run Fixtures::TestDB.conn
      end

      random_pk = Generators.random_pk
      r.table(table).insert({id: random_pk}).run Fixtures::TestDB.conn

      # Check that only documents in changefeed scope trigger events
      results.map do |v|
        id = v["new_value"]["id"].to_s
        (id != random_pk && pk == id).should be_true
      end

      r.table_drop(table).run Fixtures::TestDB.conn
    end
  end
end

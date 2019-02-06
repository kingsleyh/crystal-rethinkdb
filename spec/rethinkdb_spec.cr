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
end

# Crystal RethinkDB

This is a [RethinkDB](http://rethinkdb.com/) Driver for the [Crystal Language](http://crystal-lang.org/).

[![CI](https://github.com/kingsleyh/crystal-rethinkdb/actions/workflows/ci.yml/badge.svg)](https://github.com/kingsleyh/crystal-rethinkdb/actions/workflows/ci.yml)
[![Crystal Version](https://img.shields.io/badge/crystal%20-1.1.1-brightgreen.svg)](https://crystal-lang.org/api/1.1.1/)

## Table of Contents

<!-- Generated with `mdtoc --inplace` -->
<!-- See https://github.com/kubernetes-sigs/mdtoc -->
<!-- toc -->
  - [Installation](#installation)
  - [Usage](#usage)
    - [Connecting as a user](#connecting-as-a-user)
  - [Useful Queries](#useful-queries)
        - [Inserting](#inserting)
        - [Finding All](#finding-all)
        - [Finding One](#finding-one)
        - [Updates](#updates)
        - [Creating a database](#creating-a-database)
  - [Telemetry](#telemetry)
  - [Contributing](#contributing)
  - [Contributors](#contributors)
- [Thanks](#thanks)
<!-- /toc -->

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  rethinkdb:
    github: kingsleyh/crystal-rethinkdb
```

## Usage

This library is meant to be compatible with RethinkDB's Ruby API. Thus, all [official documentation](http://rethinkdb.com/api/ruby/) should be valid here. If you find something that behaves differently, please [open an issue](https://github.com/kingsleyh/crystal-rethinkdb/issues/new).

```crystal
require "rethinkdb"
include RethinkDB::Shortcuts

# Let’s connect and create a table:

conn = r.connect(host: "localhost")
r.db("test").table_create("tv_shows").run(conn)

# Now, let’s insert some JSON documents into the table:

r.table("tv_shows").insert([
  {name: "Star Trek TNG", episodes: 178},
  {name: "Battlestar Galactica", episodes: 75}
]).run(conn)

# We’ve just inserted two rows into the tv_shows table. Let’s verify the number of rows inserted:

pp r.table("tv_shows").count().run(conn)

# Finally, let’s do a slightly more sophisticated query. Let’s find all shows with more than 100 episodes.

p r.table("tv_shows").filter {|show| show["episodes"] > 100 }.run(conn).to_a

# As a result, we of course get the best science fiction show in existence.
```

### Connecting as a user

If you made a user called `bob` with password `secret` in the rethinkdb system table `users` e.g.:

```javascript
r.db('rethinkdb').table('users').insert({id: 'bob', password: 'secret'})
```

```crystal
require "rethinkdb"
include RethinkDB::Shortcuts

conn = r.connect(host: "localhost", db: "my_database", user: "bob", password: "secret")

```

Read more about users and permissions here: [https://rethinkdb.com/docs/permissions-and-accounts/](https://rethinkdb.com/docs/permissions-and-accounts/)

## Useful Queries

Here are some more complex queries - mostly as a reminder to myself on how to do various more complicated things:

Something to note is that depending on the query you write you could get back one of these 3 things:

* `RethinkDB::QueryResult`
* `RethinkDB:Cursor`
* `RethinkDB::Array(RethinkDB::QueryResult)`

##### Inserting

```crystal
r.table("users").insert({
                      name: name, email: email, password: password,
                      activeChannel: {} of String => String,
                      channels: [] of String, groups: [] of String,
                      isOnline: false
                      }
                    ).run(@connection)
```

```crystal
r.table("messages").insert({channelId: channelId, userId: userId, content: content, date: r.now.to_iso8601}).run(@connection)
```

##### Finding All

```crystal
r.table("users").map{|u|
         {id: u["id"], name: u["name"], isOnline: u["isOnline"]}
      }.run(@connection) }
```

```crystal
r.table("users").filter{|u| r.expr(u["groups"]).contains(groupId) }.map{|u|
         {id: u["id"], name: u["name"], isOnline: u["isOnline"]}
      }.run(@connection)
```

```crystal
r.table("groups").map{|g|
         {id: g["id"], name: g["name"], landingChannel: r.table("channels").filter({isLanding: true, groupId: g["id"]})[0]["id"]}
      }.run(@connection)
```

```crystal
r.table("users").filter({id: userId}).map{|user|
                        {
                         channels: r.table("channels").filter{|ch| ch["groupId"] == groupId}.coerce_to("array"),
                         activeChannel: r.branch(user["activeChannel"].has_fields("channelId"),
                                          {groupId: user["activeChannel"]["groupId"], channelId: user["activeChannel"]["channelId"], name: r.table("channels").get(user["activeChannel"]["channelId"])["name"]},
                                          {groupId: "", channelId: "", name: ""}),
                         groupId: r.table("groups").get(groupId)["id"],
                         name: r.table("groups").get(groupId)["name"]
                         }
                       }.run(@connection)
```

##### Finding One

```crystal
r.table("users").get(userId).run(@connection)
```

```crystal
  r.table("users").filter({id: userId}).map{|user|
                        {
                        channels: r.table("channels").filter{|ch| r.expr(user["channels"]).contains(ch["id"])}.filter{|ch| ch["groupId"] == groupId}.coerce_to("array"),
                        groups: r.table("groups").filter{|g| r.expr(user["groups"]).contains(g["id"])}.map{|g| {id: g["id"], name: g["name"], landingChannel: r.table("channels").filter({isLanding: true, groupId: g["id"]})[0]["id"]}}.coerce_to("array"),
                        messages: r.table("messages").filter{|m| m["channelId"] == channelId }.map{|m| {messageId: m["id"], userId: m["userId"], name: r.table("users").get(m["userId"])["name"], content: m["content"], date: m["date"]} }.coerce_to("array"),
                        channel: r.table("channels").get(channelId),
                        group: r.table("groups").get(groupId),
                        userIsOnline: user["isOnline"]
                        }
                      }.run(@connection).to_a.first
```

##### Updates

```crystal
r.table("users").get(userId).update({isOnline: isOnline}).run(@connection)
```

```crystal
r.table("users").get(userId).update{|u|
        {channels: u.get_field("channels").set_insert(channelId),
         groups: u.get_field("groups").set_insert(groupId),
         activeChannel: {groupId: groupId, channelId: channelId}
        }
      }.run(@connection) }
```

```crystal
r.table("users").get(userId).update{|u| {groups: u.get_field("groups").set_insert(groupId)}}.run(@connection)
```

##### Creating a database

```crystal
def recreate_database
  puts "dropping database: #{@env.database.name}"

  begin
    r.db_drop(@env.database.name).run( @connection)
  rescue ex
    puts ex.message
  end

  puts "creating database: #{@env.database.name}"
  r.db_create(@env.database.name).run(@connection)

  # add tables
  puts "adding tables: users, groups, channels, messages"
  r.db(@env.database.name).table_create("users").run(@connection)
  r.db(@env.database.name).table_create("groups").run(@connection)
  r.db(@env.database.name).table_create("channels").run(@connection)
  r.db(@env.database.name).table_create("messages").run(@connection)

  puts "done"
end

```

## Telemetry

In order to instrument your application with OpenTelemetry, you must install the [opentelemetry-instrumentation](https://github.com/wyhaines/opentelemetry-instrumentation.cr) shard.

Ensure that `OpenTelemetry::Instrumentation::Instrument` is in scope _before_ requiring the telemetry file, and _after_ the `rethinkdb` library is required.

```crystal
require "rethinkdb"
require "opentelemetry-instrumentation/src/opentelemetry/instrumentation/instrument"
require "rethinkdb/telemetry"
```

## Contributing

1. Fork it (<https://github.com/kingsleyh/crystal-rethinkdb/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [kingsleyh](https://github.com/kingsleyh) Kingsley Hendrickse - creator, maintainer
- [caspiano](https://github.com/caspiano) Caspian Baska - contributor, maintainer
- [fenicks](https://github.com/fenicks) Christian Kakesa - contributor

# Thanks

- [Guilherme Bernal](https://github.com/lbguilherme) for his hard work on which this project is based.

# Crystal-RethinkDB

This is a [RethinkDB](http://rethinkdb.com/) Driver for the [Crystal Language](http://crystal-lang.org/).

[![Build Status](https://travis-ci.org/kingsleyh/crystal-rethinkdb.svg?branch=master)](https://travis-ci.org/kingsleyh/crystal-rethinkdb) [![Crystal Version](https://img.shields.io/badge/crystal%20-0.26.1-brightgreen.svg)](https://crystal-lang.org/api/0.26.1/)

### WARNING: This is only a basic driver a lot of functions are not implemented.

## History

This driver is mostly a copy of this project: [cubos/rethinkdb.cr](https://github.com/cubos/rethinkdb.cr) (quickly) updated to work for Crystal 26.1. It is designed to work with the rethinkdb V1_0 release and has the user authentication mechanism implemented which was taken from this project: [rethinkdb-lite](https://github.com/lbguilherme/rethinkdb-lite)

Thanks to these great projects it was not too hard to create this one. Unfortunately those other 2 projects are not being maintained and the `rethinkdb.cr` project has more of the api implemented but the code is not as well structured as the newer `rethinkdb-lite` project. However `rethinkdb-lite` has a lot of missing functionality so I made the decision to fix up the original project and add in the authentication from the newer one.

I will try to do more work on this library over time.

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  rethinkdb:
    github: kingsleyh/crystal-rethinkdb
```

## Usage

This library is meant to be compactible with RethinkDB's Ruby API. Thus, all [official documentation](http://rethinkdb.com/api/ruby/) should be valid here. If you find something that behaves differently, please [open an issue](https://github.com/kingsleyh/crystal-rethinkdb/issues/new).

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


## Contributing

1. Fork it (<https://github.com/your-github-user/crystal-rethinkdb/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [kingsleyh](https://github.com/kingsleyh) Kingsley Hendrickse - creator, maintainer

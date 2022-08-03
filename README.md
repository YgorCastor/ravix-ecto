# Ravix Ecto

[![Build & Tests](https://github.com/YgorCastor/ravix-ecto/actions/workflows/elixir.yml/badge.svg)](https://github.com/YgorCastor/ravix-ecto/actions/workflows/elixir.yml)

[RavenDB](https://ravendb.net/) is an amazing multi-model NoSQL database, and albeit it does not support SQL, its `RQL Language` if pretty close, so behold, now you can query it
like a simple Ecto-SQL database.

This adapter leverages the use of [Ravix](https://github.com/YgorCastor/ravix) as a driver between ecto and RavenDB

## Installing

Add Ravix Ecto to your mix.exs dependencies

```elixir
{:ravix_ecto, "~> 0.3.0"}
```

## Example

```elixir
# In your config/config.exs file
config :my_app, Store,
  urls: [System.get_env("RAVENDB_URL", "http://localhost:8080")],
  database: "test",
  retry_on_failure: true,
  retry_on_stale: true,
  retry_backoff: 500,
  retry_count: 3,
  force_create_database: true,
  document_conventions: %{
    max_number_of_requests_per_session: 30,
    max_ids_to_catch: 32,
    timeout: 30,
    use_optimistic_concurrency: false,
    max_length_of_query_using_get_url: 1024 + 512,
    identity_parts_separator: "/",
    disable_topology_update: false
  }

config :my_app, Repo, store: Store

# In your application code
defmodule Store do
  use Ravix.Documents.Store, otp_app: :my_app
end

defmodule Repo do
  use Ecto.Repo,
    otp_app: :ravix_ecto,
    adapter: Ravix.Ecto.Adapter
end

defmodule TestApplication do
  use Application

  def start(_opts, _) do
    children = [
      {Repo, [%{}]}
    ]

    Supervisor.init(
      children,
      strategy: :one_for_one
    )
  end
end

defmodule Weather do
  use Ecto.Model

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "weather" do
    field :city     # Defaults to type :string
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp,    :float, default: 0.0
  end
end

defmodule Simple do
  import Ecto.Query

  def sample_query do
    query = from w in Weather,
          where: w.prcp > 0 or is_nil(w.prcp),
         select: w
    Repo.all(query)
  end
end
```

# Caveats

### RavenDB does not support integer ids

In RavenDB all the IDs are strings, so the :id type will generate a non-integer type

### Aggregations on RavenDB are different

In RavenDB the aggregations use a [Map-Reduce index based aggregation](https://ravendb.net/learn/inside-ravendb-book/reader/4.0/11-mapreduce-and-aggregations-in-ravendb), 
which gets a bit annoying to deal using Ecto, so for now, you can only do aggregations using Ravix Directly. 

### Conflicts management

RavenDB deals a bit different with [conflicts](https://www.google.com/search?q=RavenDB+conflicts&oq=RavenDB+conflicts&aqs=chrome..69i57.2870j0j4&sourceid=chrome&ie=UTF-8), so
right now if you have a conflict, an exception will be raised. Ecto strategies are not supported yet.

### Associations

RavenDB is a Document-Database first, it does support a kind of [documents association](https://ravendb.net/docs/article-page/4.2/java/client-api/how-to/handle-document-relationships), 
but i've not implemented it yet (mostly because i think relationships in documents sucks). You can however use embed schemas normally.

### Migrations

RavenDB is schemaless, so migrations are kind of useless. We can however use it to setup indexes and so on, but it's not implemented yet.

# TODOs
* Aggregations
* Conflict Management
* Associations
# Contributors

[mongodb_ecto](https://github.com/elixir-mongo/mongodb_ecto) - From who i shamelessly forked and adapted this driver, that saved me a lot of work : D

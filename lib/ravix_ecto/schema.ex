defmodule Ravix.Ecto.Schema do
  @behaviour Ecto.Adapter.Schema

  require Ecto.Query
  require OK

  alias Ravix.Ecto.Executor
  alias Ravix.Ecto.Parser.QueryParser

  @impl Ecto.Adapter.Schema
  def insert(adapter_meta, schema_meta, fields, on_conflict, returning, opts) do
    {:insert, pk, document_to_insert} =
      QueryParser.insert(schema_meta, fields, on_conflict, returning, opts)

    case Executor.insert(adapter_meta, document_to_insert, pk) do
      {:ok, _} -> {:ok, []}
      {:error, any} -> {:error, any}
    end
  end

  @impl Ecto.Adapter.Schema
  def update(adapter_meta, _query_meta, fields, filters, _returning, _opts) do
    case Executor.update_one(adapter_meta, fields, filters) do
      {:ok, _} -> {:ok, []}
      err -> err
    end
  end

  @impl Ecto.Adapter.Schema
  def delete(adapter_meta, _schema_meta, filters, _options) do
    case Executor.delete_one(adapter_meta, filters) do
      {:ok, _} -> {:ok, []}
      err -> err
    end
  end

  @impl Ecto.Adapter.Schema
  def autogenerate(_), do: UUID.uuid4()
end

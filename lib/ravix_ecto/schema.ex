defmodule Ravix.Ecto.Schema do
  @behaviour Ecto.Adapter.Schema

  require Ecto.Query
  require OK

  import Ravix.Ecto.Parser.Shared

  alias Ravix.Ecto.Executor
  alias Ravix.Ecto.Parser.QueryParser

  alias Ravix.RQL.Query, as: RavenQuery
  alias Ravix.RQL.Tokens.Condition

  @impl Ecto.Adapter.Schema
  def insert(adapter_meta, schema_meta, fields, on_conflict, returning, opts) do
    {:insert, pk, document_to_insert} =
      QueryParser.insert(schema_meta, fields, on_conflict, returning, opts)

    case Executor.insert(adapter_meta, document_to_insert, pk) do
      {:ok, response} ->
        {:ok, returning_fields(adapter_meta, schema_meta, response, returning, pk, opts)}

      {:error, :no_valid_id_informed} ->
        {:invalid, [no_valid_id_informed: inspect(document_to_insert)]}
    end
  end

  @impl Ecto.Adapter.Schema
  def insert_all(
        adapter_meta,
        schema_meta,
        _header,
        fields_list,
        on_conflict,
        returning,
        _placeholders,
        opts
      ) do
    {:insert_all, pk, documents_to_insert} =
      QueryParser.insert(schema_meta, fields_list, on_conflict, returning, opts)

    case Executor.insert(adapter_meta, documents_to_insert, pk) do
      {:ok, response} ->
        created_count = length(response)

        {created_count,
         returning_fields_for_list(adapter_meta, schema_meta, response, returning, pk, opts)}

      {:error, :no_valid_id_informed} ->
        {:invalid, [no_valid_id_informed: inspect(documents_to_insert)]}
    end
  end

  @impl Ecto.Adapter.Schema
  def update(adapter_meta, %{schema: schema}, fields, filters, _returning, _opts) do
    pk = primary_key(schema)

    case Executor.update_one(adapter_meta, fields, filters, pk) do
      {:ok, _} -> {:ok, []}
      {:error, :stale_entity} -> {:error, :stale}
    end
  end

  @impl Ecto.Adapter.Schema
  def delete(adapter_meta, %{schema: schema}, filters, _returning, _options) do
    pk = primary_key(schema)

    case Executor.delete_one(adapter_meta, filters, pk) do
      {:ok, _} -> {:ok, []}
      {:error, :stale_entity} -> {:error, :stale}
    end
  end

  @impl Ecto.Adapter.Schema
  def autogenerate(:binary_id), do: UUID.uuid4()
  def autogenerate(:embed_id), do: UUID.uuid4()

  def autogenerate(:id),
    do: raise("[RAVIX-ECTO] RavenDB does not support auto-generated integer ids!")

  defp returning_fields_for_list(_adapter_meta, _schema_meta, _result, [], _primary_key, _opts),
    do: nil

  defp returning_fields_for_list(adapter_meta, schema_meta, result, metadata, pk, opts) do
    Enum.map(
      result,
      &(returning_fields(adapter_meta, schema_meta, &1, metadata, pk, opts) |> Keyword.values())
    )
  end

  defp returning_fields(_adapter_meta, _schema_meta, _result, [], _primary_key, _opts), do: []

  defp returning_fields(adapter_meta, schema_meta, [metadata], fields_to_return, pk, opts) do
    returning_fields(adapter_meta, schema_meta, metadata, fields_to_return, pk, opts)
  end

  defp returning_fields(_adapter_meta, _schema_meta, metadata, [pk], pk, _opts) do
    Keyword.put([], pk, metadata["@id"])
  end

  defp returning_fields(
         adapter_meta,
         schema_meta,
         metadata,
         fields_to_return,
         pk,
         _opts
       ) do
    {_, [db_entity]} =
      fetch_entity_from_db(
        adapter_meta,
        schema_meta,
        fields_to_return,
        metadata[:"@id"]
      )

    fields_to_return
    |> Enum.map(fn
      ^pk ->
        {pk, metadata[:"@id"]}

      field ->
        {field, Map.get(db_entity, Atom.to_string(field))}
    end)
  end

  defp fetch_entity_from_db(adapter_meta, %{source: collection}, fields_to_return, pk)
       when is_binary(collection) do
    query =
      RavenQuery.from(collection)
      |> RavenQuery.where(Condition.equal_to(:"id()", pk))
      |> RavenQuery.select(fields_to_return)

    case Executor.query(query, adapter_meta) do
      {:ok, response} -> response
      err -> err
    end
  end
end

defmodule Ravix.Ecto.Schema do
  @behaviour Ecto.Adapter.Schema

  require Ecto.Query
  require OK

  alias Ravix.Ecto.Executor

  @impl Ecto.Adapter.Schema
  def insert(adapter_meta, schema_meta, fields, on_conflict, returning, opts) do
    document_to_insert = insert(schema_meta, fields, on_conflict, returning, opts)

    case Executor.insert(adapter_meta, document_to_insert) do
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

  defp insert(schema_meta, fields, {:raise, [], []}, returning, _opts),
    do: plain_insert(schema_meta, fields, returning)

  defp insert(schema_meta, fields, {:nothing, [], []}, returning, _opts),
    do: plain_insert(schema_meta, fields, returning)

  defp insert(
         %{source: coll, schema: schema, prefix: prefix},
         [[_ | _] | _] = docs,
         {:nothing, [], conflict_targets},
         returning,
         _opts
       ) do
    IO.inspect(coll, label: :insert_1)
    IO.inspect(schema, label: :insert_1)
    IO.inspect(prefix, label: :insert_1)
    IO.inspect(docs, label: :insert_1)
    IO.inspect(conflict_targets, label: :insert_1)
    IO.inspect(returning, label: :insert_1)
  end

  defp insert(
         %{source: coll, schema: schema, prefix: prefix},
         fields,
         {:nothing, [], conflict_targets},
         returning,
         _opts
       ) do
    IO.inspect(coll, label: :insert_2)
    IO.inspect(schema, label: :insert_2)
    IO.inspect(prefix, label: :insert_2)
    IO.inspect(fields, label: :insert_2)
    IO.inspect(conflict_targets, label: :insert_2)
    IO.inspect(returning, label: :insert_2)
  end

  defp insert(
         %{schema: schema, source: coll, prefix: prefix},
         [[_ | _] | _] = docs,
         {[_ | _] = replace_fields, _, conflict_targets},
         returning,
         opts
       ) do
    IO.inspect(coll, label: :insert_3)
    IO.inspect(schema, label: :insert_3)
    IO.inspect(prefix, label: :insert_3)
    IO.inspect(docs, label: :insert_3)
    IO.inspect(conflict_targets, label: :insert_3)
    IO.inspect(replace_fields, label: :insert_3)
    IO.inspect(returning, label: :insert_3)
    IO.inspect(opts, label: :insert_3)
  end

  defp insert(
         %{schema: schema} = schema_meta,
         fields,
         {[_ | _] = replace_fields, _, conflict_targets},
         returning,
         opts
       ) do
    IO.inspect(schema, label: :insert_4)
    IO.inspect(fields, label: :insert_4)
    IO.inspect(conflict_targets, label: :insert_4)
    IO.inspect(replace_fields, label: :insert_4)
    IO.inspect(returning, label: :insert_4)
    IO.inspect(opts, label: :insert_4)
  end

  defp insert(
         %{source: coll, prefix: prefix},
         [[_ | _] | _] = docs,
         {%Ecto.Query{} = query, values, conflict_targets},
         returning,
         _opts
       ) do
    IO.inspect(coll, label: :insert_5)
    IO.inspect(prefix, label: :insert_5)
    IO.inspect(docs, label: :insert_5)
    IO.inspect(conflict_targets, label: :insert_)
    IO.inspect(query, label: :insert_5)
    IO.inspect(values, label: :insert_5)
    IO.inspect(returning, label: :insert_5)
  end

  defp insert(
         %{source: coll, prefix: prefix},
         fields,
         {%Ecto.Query{} = query, values, conflict_targets},
         returning,
         _opts
       ) do
    IO.inspect(coll, label: :insert_6)
    IO.inspect(prefix, label: :insert_6)
    IO.inspect(fields, label: :insert_6)
    IO.inspect(conflict_targets, label: :insert_6)
    IO.inspect(query, label: :insert_6)
    IO.inspect(values, label: :insert_6)
    IO.inspect(returning, label: :insert_6)
  end

  defp plain_insert(%{source: coll, schema: schema, prefix: prefix}, fields, returning) do
    IO.inspect(coll, label: :plain_insert)
    IO.inspect(schema, label: :plain_insert)
    IO.inspect(prefix, label: :plain_insert)
    IO.inspect(fields, label: :plain_insert)
    IO.inspect(returning, label: :plain_insert)

    document(fields, schema)
  end

  @impl Ecto.Adapter.Schema
  def update(adapter_meta, _query_meta, fields, filters, _returning, _opts) do
    case Executor.update_one(adapter_meta, fields, filters) do
      {:ok, _} -> {:ok, []}
      err -> err
    end
  end

  @spec document(keyword(), atom()) :: map()
  defp document(plain_document, schema) do
    mapped_document = Enum.into(plain_document, %{})

    case schema do
      nil -> mapped_document
      _ -> struct!(schema, mapped_document)
    end
  end
end

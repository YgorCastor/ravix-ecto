defmodule Ravix.Ecto.Parser.QueryParser do
  defmodule QueryInfo do
    defstruct kind: nil,
              fields: [],
              raven_query: nil
  end

  import Ravix.Ecto.Parser.Shared
  import Ecto.Changeset

  alias Ecto.Query, as: EctoQuery
  alias Ravix.RQL.Query, as: RavenQuery
  alias Ravix.RQL.Tokens

  alias Ravix.Ecto.Parser.{Projection, QueryParams}

  def all(ecto_query, params) do
    {coll, model, raven_query, pk} = from(ecto_query)
    params = List.to_tuple(params)
    query_params = QueryParams.parse(ecto_query, params, pk)

    case Projection.project(ecto_query, params, {coll, model, pk}) do
      {:find, projection, fields} ->
        %QueryInfo{
          kind: :read,
          fields: fields,
          raven_query: find_all_query(raven_query, query_params, projection)
        }
    end
  end

  def insert(
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

  def insert(
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

  def insert(
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

  def insert(
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

  def insert(
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

  def insert(
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

  def insert(schema_meta, fields, {:raise, [], []}, returning, _opts),
    do: plain_insert(schema_meta, fields, returning)

  def insert(schema_meta, fields, {:nothing, [], []}, returning, _opts),
    do: plain_insert(schema_meta, fields, returning)

  defp plain_insert(%{source: _coll, schema: schema, prefix: _prefix}, fields, _returning) do
    pk = primary_key(schema)
    # We don't want to map directly to a struct, it can fuck up field-sources
    document =
      cast(struct(schema, %{}), Enum.into(fields, %{}), schema.__schema__(:fields))
      |> apply_changes()

    op =
      case fields do
        [[_ | _] | _] -> :insert_all
        _ -> :insert
      end

    {op, pk, document}
  end

  def delete_all(ecto_query, params) do
    {_coll, _model, raven_query, pk} = from(ecto_query)
    params = List.to_tuple(params)
    query_params = QueryParams.parse(ecto_query, params, pk)

    %QueryInfo{
      kind: :delete,
      fields: [],
      raven_query: delete_all_query(raven_query, query_params)
    }
  end

  defp find_all_query(raven_query, query_params, projection) do
    raven_query
    |> append_conditions(query_params)
    |> parse_projections(projection)
  end

  defp delete_all_query(raven_query, query_params) do
    raven_query
    |> append_conditions(query_params)
  end

  defp from(%EctoQuery{from: %{source: {coll, model}}}) do
    {coll, model, RavenQuery.from(coll), primary_key(model)}
  end

  defp from(%EctoQuery{from: %{source: %Ecto.SubQuery{}}}) do
    raise ArgumentError, "Ravix Ecto does not support subqueries yet"
  end

  defp parse_param({field, operations}) when is_atom(field) do
    operations
    |> Enum.map(fn {function, param} ->
      function.(field, param)
    end)
  end

  defp parse_param([params | _]), do: parse_param(params)

  defp parse_param({bool_operation, operations}) when is_function(bool_operation) do
    operations
    |> Enum.flat_map(&parse_param/1)
    |> Enum.map(fn op -> bool_operation.(op) end)
  end

  defp append_conditions(raven_query, query_params) do
    query_params
    |> Enum.reduce(raven_query, fn params, acc ->
      append_condition(acc, parse_param(params))
    end)
  end

  defp append_condition(query, conditions) when is_list(conditions) do
    conditions
    |> Enum.reduce(query, fn condition, acc -> append_condition(acc, condition) end)
  end

  defp append_condition([query], condition) do
    append_condition(query, condition)
  end

  defp append_condition(query, condition) do
    case condition do
      %Tokens.Or{} = condition ->
        %RavenQuery{
          query
          | or_tokens: query.or_tokens ++ [condition]
        }

      %Tokens.And{} = condition ->
        %RavenQuery{
          query
          | and_tokens: query.and_tokens ++ [condition]
        }

      %Tokens.Not{condition: %Tokens.And{}} = condition ->
        %RavenQuery{
          query
          | and_tokens: query.and_tokens ++ [condition]
        }

      %Tokens.Not{condition: %Tokens.Or{}} = condition ->
        %RavenQuery{
          query
          | and_tokens: query.or_tokens ++ [condition]
        }

      %Tokens.Condition{} = condition when query.where_token == nil ->
        RavenQuery.where(query, condition)
    end
  end

  defp parse_projections(%RavenQuery{} = query, projections) when projections == %{}, do: query

  defp parse_projections(%RavenQuery{} = query, projections),
    do:
      query
      |> RavenQuery.select(
        projections
        |> Map.filter(fn {_key, value} -> value end)
        |> Map.keys()
      )
end

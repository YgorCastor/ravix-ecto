defmodule Ravix.Ecto.Parser.QueryParser do
  defmodule QueryInfo do
    defstruct kind: nil,
              pk: nil,
              fields: [],
              raven_query: nil
  end

  import Ravix.Ecto.Parser.Shared

  alias Ecto.Query, as: EctoQuery
  alias Ravix.RQL.Query, as: RavenQuery
  alias Ravix.RQL.Tokens

  alias Ravix.Ecto.Parser.{Projection, QueryParams}

  def all(ecto_query, params) do
    check_query!(ecto_query)

    {coll, model, raven_query, pk} = from(ecto_query)
    params = List.to_tuple(params)
    query_conditions = QueryParams.parse_conditions(ecto_query, params, pk)
    limit_params = QueryParams.parse_limit_and_offset(ecto_query, params)

    case Projection.project(ecto_query, params, {coll, model, pk}) do
      {:find, projection, fields} ->
        %QueryInfo{
          kind: :read,
          fields: fields,
          pk: pk,
          raven_query:
            find_all_query(
              raven_query,
              ecto_query,
              query_conditions,
              limit_params,
              projection,
              pk,
              model
            )
        }
    end
  end

  def insert(
        %{source: _coll, schema: _schema, prefix: _prefix},
        [[_ | _] | _] = _docs,
        {:nothing, [], _conflict_targets},
        _returning,
        _opts
      ) do
    raise ArgumentError, "The RavenDB Adapter does not support conflict targets yet"
  end

  def insert(
        %{source: _coll, schema: _schema, prefix: _prefix},
        _fields,
        {:nothing, [], _conflict_targets},
        _returning,
        _opts
      ) do
    raise ArgumentError, "The RavenDB Adapter does not support conflict targets yet"
  end

  def insert(
        %{schema: _schema, source: _coll, prefix: _prefix},
        [[_ | _] | _] = _docs,
        {[_ | _] = _replace_fields, _, _conflict_targets},
        _returning,
        _opts
      ) do
    raise ArgumentError, "The RavenDB Adapter does not support conflict targets yet"
  end

  def insert(
        %{schema: _schema} = _schema_meta,
        _fields,
        {[_ | _] = _replace_fields, _, _conflict_targets},
        _returning,
        _opts
      ) do
    raise ArgumentError, "The RavenDB Adapter does not support conflict targets yet"
  end

  def insert(
        %{source: _coll, prefix: _prefix},
        [[_ | _] | _] = _docs,
        {%Ecto.Query{} = _query, _values, _conflict_targets},
        _returning,
        _opts
      ) do
    raise ArgumentError, "The RavenDB Adapter does not support conflict targets yet"
  end

  def insert(
        %{source: _coll, prefix: _prefix},
        _fields,
        {%Ecto.Query{} = _query, _values, _conflict_targets},
        _returning,
        _opts
      ) do
    raise ArgumentError, "The RavenDB Adapter does not support conflict targets yet"
  end

  def insert(schema_meta, fields, {:raise, [], []}, returning, _opts),
    do: plain_insert(schema_meta, fields, returning)

  def insert(schema_meta, fields, {:nothing, [], []}, returning, _opts),
    do: plain_insert(schema_meta, fields, returning)

  defp plain_insert(%{source: coll, schema: nil, prefix: _prefix}, fields, _returning) do
    {op, document} =
      case fields do
        [[_ | _] | _] -> {:insert_all, cast_documents(nil, fields, coll)}
        _ -> {:insert, cast_document(nil, fields, coll)}
      end

    {op, nil, document}
  end

  defp plain_insert(%{source: coll, schema: schema, prefix: _prefix}, fields, _returning) do
    pk = primary_key(schema)

    # We don't want to map directly to a struct, it can fuck up field-sources
    {op, document} =
      case fields do
        [[_ | _] | _] -> {:insert_all, cast_documents(schema, fields, coll)}
        _ -> {:insert, cast_document(schema, fields, coll)}
      end

    {op, pk, document}
  end

  defp cast_documents(schema, field_list, coll) do
    field_list
    |> Enum.map(&cast_document(schema, &1, coll))
  end

  defp cast_document(nil, fields, coll) do
    check_params!(fields)

    Enum.into(parse_metadata(fields, coll), %{})
  end

  defp cast_document(schema, fields, coll) do
    check_params!(fields)

    schema =
      struct(schema, %{})
      |> Map.from_struct()
      |> Map.drop([:__meta__])

    Enum.into(parse_metadata(fields, coll), schema)
  end

  defp parse_metadata(fields, collection) do
    {_, updated_fields} =
      Keyword.get_and_update(fields, :"@metadata", fn value ->
        case value do
          nil ->
            {nil, %{"@collection" => collection}}

          metadata ->
            {
              metadata,
              metadata |> Map.put("@collection", collection)
            }
        end
      end)

    updated_fields
  end

  def delete_all(ecto_query, params) do
    check_query!(ecto_query)

    {_coll, _model, raven_query, pk} = from(ecto_query)
    params = List.to_tuple(params)
    query_params = QueryParams.parse_conditions(ecto_query, params, pk)

    %QueryInfo{
      kind: :delete,
      fields: [],
      raven_query: delete_all_query(raven_query, query_params)
    }
  end

  def update_all(ecto_query, params) do
    check_query!(ecto_query)

    {_coll, _model, raven_query, pk} = from(ecto_query)
    params = List.to_tuple(params)
    query_params = QueryParams.parse_conditions(ecto_query, params, pk)
    updates = QueryParams.parse_update(ecto_query, params, pk)

    %QueryInfo{
      kind: :update,
      fields: [],
      raven_query: update_all_query(raven_query, query_params, updates)
    }
  end

  defp find_all_query(
         raven_query,
         ecto_query,
         query_conditions,
         limit_params,
         projection,
         pk,
         model
       ) do
    raven_query
    |> append_conditions(query_conditions)
    |> append_default_where_if_missing()
    |> parse_projections(projection)
    |> parse_order(ecto_query, model, pk)
    |> parse_grouping(ecto_query, pk)
    |> limit_skip(limit_params)
  end

  defp delete_all_query(raven_query, query_params) do
    raven_query
    |> append_conditions(query_params)
    |> append_default_where_if_missing()
  end

  defp update_all_query(raven_query, query_params, updates) do
    raven_query
    |> append_conditions(query_params)
    |> append_default_where_if_missing()
    |> append_updates(updates)
  end

  defp from(%EctoQuery{from: %{source: {coll, model}}}) do
    {coll, model, RavenQuery.from(coll, String.first(coll)), primary_key(model)}
  end

  defp from(%EctoQuery{from: %{source: %Ecto.SubQuery{}}}) do
    raise ArgumentError, "Ravix Ecto does not support subqueries yet"
  end

  defp parse_param({field, nil}) do
    Ravix.RQL.Tokens.Condition.equal_to(field, nil)
  end

  defp parse_param([params | _]), do: parse_param(params)

  defp parse_param({bool_operation, operations}) when is_function(bool_operation) do
    operations
    |> Enum.flat_map(&parse_param/1)
    |> Enum.map(fn op -> bool_operation.(op) end)
  end

  defp parse_param({field, operations}) do
    operations
    |> Enum.map(fn {function, param} ->
      function.(field, param)
    end)
  end

  defp append_updates(raven_query, updates) do
    updates = Enum.reduce(updates, %Ravix.RQL.Tokens.Update{}, &parse_update_function/2)
    Ravix.RQL.Query.update(raven_query, updates)
  end

  defp parse_update_function({function, fields}, update_token) do
    Enum.reduce(fields, update_token, fn {field, value}, acc -> function.(acc, field, value) end)
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
          | or_tokens: query.or_tokens ++ [condition]
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
        |> Map.drop([:"@metadata"])
        |> Map.keys()
      )

  defp append_default_where_if_missing(%RavenQuery{} = query) do
    case query.where_token == nil do
      true -> transform_binary_op_into_where(query)
      false -> query
    end
  end

  defp parse_order(
         %RavenQuery{} = raven_query,
         %EctoQuery{order_bys: order_bys} = query,
         model,
         pk
       ) do
    case order_bys
         |> Enum.flat_map(fn %EctoQuery.QueryExpr{expr: expr} ->
           Enum.map(expr, &order_by_expr(&1, model, pk, query))
         end) do
      [] ->
        raven_query

      ordering ->
        RavenQuery.order_by(
          raven_query,
          ordering
        )
    end
  end

  defp parse_grouping(%RavenQuery{} = raven_query, %EctoQuery{group_bys: group_bys} = query, pk) do
    case group_bys
         |> Enum.flat_map(fn %EctoQuery.QueryExpr{expr: expr} ->
           Enum.map(expr, &field(&1, pk, query, "group by clause"))
         end) do
      [] ->
        raven_query

      grouping ->
        RavenQuery.group_by(raven_query, grouping)
    end
  end

  defp limit_skip(
         %RavenQuery{} = raven_query,
         nil
       ),
       do: raven_query

  defp limit_skip(
         %RavenQuery{} = raven_query,
         limit: limit,
         offset: offset
       ),
       do: RavenQuery.limit(raven_query, offset, limit)

  defp order_by_expr({:asc, expr}, model, pk, query),
    do: order_by_expr(expr, :asc, model, pk, query)

  defp order_by_expr({:desc, expr}, model, pk, query),
    do: order_by_expr(expr, :desc, model, pk, query)

  defp order_by_expr(expr, order, model, pk, query) do
    field_name = field(expr, pk, query, "order clause")

    %Tokens.Order.Field{
      name: field_name,
      order: order,
      type: orderby_type(model, field_name)
    }
  end

  defp check_params!(params) when is_list(params) do
    case Enum.any?(params, fn {_field, value} -> is_ecto_query(value) end) do
      true -> raise ArgumentError, "The RavenDB adapter does not support field queries yet!"
      false -> nil
    end
  end

  defp check_params!(_),
    do: raise(ArgumentError, "The RavenDB adapter does not support source queries yet!")

  defp is_ecto_query(fields) when is_tuple(fields) do
    [ecto | _] = Tuple.to_list(fields)
    is_struct(ecto, EctoQuery)
  end

  defp is_ecto_query(_), do: false

  defp transform_binary_op_into_where(%RavenQuery{} = raven_query)
       when raven_query.and_tokens != [] do
    and_token = Enum.at(raven_query.and_tokens, 0)
    raven_query = RavenQuery.where(raven_query, and_token.condition)

    put_in(raven_query.and_tokens, Enum.drop(raven_query.and_tokens, 1))
  end

  defp transform_binary_op_into_where(%RavenQuery{} = raven_query)
       when raven_query.or_tokens != [] do
    or_token = Enum.at(raven_query.or_tokens, 0)
    raven_query = RavenQuery.where(raven_query, or_token.condition)

    put_in(raven_query.or_tokens, Enum.drop(raven_query.or_tokens, 1))
  end

  defp transform_binary_op_into_where(query), do: query

  defp orderby_type(nil, _field), do: :lexicographically

  defp orderby_type(model, field) do
    case model.__schema__(:type, field) do
      :float -> :float
      :integer -> :number
      :id -> :number
      :decimal -> :float
      _ -> :lexicographically
    end
  end
end

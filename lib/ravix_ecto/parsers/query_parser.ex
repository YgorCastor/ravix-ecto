defmodule Ravix.Ecto.Parser.QueryParser do
  defmodule QueryInfo do
    defstruct kind: nil,
              fields: [],
              raven_query: nil
  end

  import Ravix.Ecto.Parser.Shared

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
          raven_query: find_all(raven_query, query_params, projection)
        }
    end
  end

  defp find_all(raven_query, query_params, _projection) do
    query_params
    |> Enum.reduce(raven_query, fn params, acc ->
      append_condition(acc, parse_param(params))
    end)
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
end

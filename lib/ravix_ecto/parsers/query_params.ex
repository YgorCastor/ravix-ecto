defmodule Ravix.Ecto.Parser.QueryParams do
  import Ravix.Ecto.Parser.{ConditionalTokens, Shared}

  alias Ecto.Query, as: EctoQuery

  def parse(%EctoQuery{wheres: wheres} = query, params, pk) do
    wheres
    |> Enum.map(fn %EctoQuery.BooleanExpr{expr: expr} ->
      pair(expr, params, pk, query, "where clause")
    end)
    |> :lists.flatten()
    |> merge_keys(query, "where clause")
    |> map_unless_empty
  end

  def parse([{_, _} | _] = fields, keys, pk) do
    fields
    |> Keyword.take(keys)
    |> parse(pk)
  end

  def parse(filter, pk) do
    filter |> value(pk, "where clause") |> map_unless_empty
  end

  def parse_update(%EctoQuery{updates: updates} = query, params, pk) do
    updates
    |> Enum.flat_map(fn %EctoQuery.QueryExpr{expr: expr} ->
      pair(expr, query, params, pk)
    end)
    |> :lists.flatten()
    |> merge_keys(query, "update clause")
  end

  defp merge_keys(keyword, query, place) do
    Enum.reduce(keyword, %{}, fn {key, value}, acc ->
      Map.update(acc, key, value, fn
        old when is_list(old) -> old ++ value
        _ -> error(query, place)
      end)
    end)
  end

  defp mapped_pair_or_value({op, _, _} = tuple, params, pk, query, place) when is_op(op) do
    List.wrap(pair(tuple, params, pk, query, place))
  end

  defp mapped_pair_or_value(value, params, pk, query, place) do
    value(value, params, pk, query, place)
  end

  defp pair(expr, query, params, pk) do
    Enum.map(expr, fn {key, value} ->
      check_update_op!(key, query)
      {key, value(value, params, pk, query, "update clause")}
    end)
  end

  defp pair({:not, _, [{:in, _, [left, right]}]}, params, pk, query, place) do
    {field(left, pk, query, place), [{binary_op(:nin), value(right, params, pk, query, place)}]}
  end

  defp pair({:is_nil, _, [expr]}, _, pk, query, place) do
    {field(expr, pk, query, place), nil}
  end

  defp pair({:in, _, [left, {:^, _, [0, 0]}]}, _params, pk, query, place) do
    {field(left, pk, query, place), [{binary_op(:in), []}]}
  end

  defp pair({:in, _, [left, {:^, _, [ix, len]}]}, params, pk, query, place) do
    args =
      ix..(ix + len - 1)
      |> Enum.map(&elem(params, &1))
      |> Enum.map(&value(&1, params, pk, query, place))

    {field(left, pk, query, place), [{binary_op(:in), args}]}
  end

  defp pair({:in, _, [lhs, {{:., _, _}, _, _} = rhs]}, params, pk, query, place) do
    {field(rhs, pk, query, place), value(lhs, params, pk, query, place)}
  end

  defp pair({:not, _, [{:in, _, [left, {:^, _, [ix, len]}]}]}, params, pk, query, place) do
    args =
      ix..(ix + len - 1)
      |> Enum.map(&elem(params, &1))
      |> Enum.map(&value(&1, params, pk, query, place))

    {field(left, pk, query, place), [{binary_op(:nin), args}]}
  end

  defp pair({:not, _, [{:in, _, [left, right]}]}, params, pk, query, place) do
    {field(left, pk, query, place), [{binary_op(:nin), value(right, params, pk, query, place)}]}
  end

  defp pair({:not, _, [{:is_nil, _, [expr]}]}, _, pk, query, place) do
    {field(expr, pk, query, place), [{binary_op(:ne), nil}]}
  end

  defp pair({:not, _, [{:==, _, [left, right]}]}, params, pk, query, place) do
    {field(left, pk, query, place), [{binary_op(:ne), value(right, params, pk, query, place)}]}
  end

  defp pair({:not, _, [expr]}, params, pk, query, place) do
    {bool_op(:not), [pair(expr, params, pk, query, place)]}
  end

  defp pair({:fragment, _, [args]}, params, pk, query, place)
       when is_list(args) or tuple_size(args) == 3 do
    value(args, params, pk, query, place)
  end

  defp pair({op, _, [left, right]}, params, pk, query, place) when op in ecto_binary_tokens() do
    {field(left, pk, query, place), [{binary_op(op), value(right, params, pk, query, place)}]}
  end

  defp pair({op, _, args}, params, pk, query, place) when op in ecto_boolean_tokens() do
    args = Enum.map(args, &mapped_pair_or_value(&1, params, pk, query, place))
    {bool_op(op), args}
  end

  defp pair(_expr, _params, _pk, query, place) do
    error(query, place)
  end
end

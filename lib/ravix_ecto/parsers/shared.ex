defmodule Ravix.Ecto.Parser.Shared do
  alias Ravix.Ecto.Conversions

  @spec is_op(any) ::
          {:and, [{:context, Ravix.Ecto.Parser.Shared} | {:import, Kernel}, ...],
           [{:!=, [...], [...]} | {:is_atom, [...], [...]}, ...]}
  defmacro is_op(op) do
    quote do
      is_atom(unquote(op)) and unquote(op) != :^
    end
  end

  def value(expr, pk, place) do
    case Conversions.from_ecto(expr, pk) do
      {:ok, value} -> value
      :error -> error(place)
    end
  end

  def value(expr, params, pk, query, place) do
    case Conversions.inject_params(expr, params, pk) do
      {:ok, value} -> value
      :error -> error(query, place)
    end
  end

  def field(pk, pk), do: "id()"
  def field(key, _), do: key

  def field({{:., _, [{:&, _, [0]}, field]}, _, []}, pk, _query, _place), do: field(field, pk)
  def field(_expr, _pk, query, place), do: error(query, place)

  def map_unless_empty([]), do: %{}
  def map_unless_empty(list), do: list

  def primary_key(nil), do: nil

  def primary_key(schema) do
    case schema.__schema__(:primary_key) do
      [] ->
        nil

      [pk] ->
        pk

      keys ->
        raise ArgumentError,
              "RavenDB adapter does not support multiple primary keys " <>
                "and #{inspect(keys)} were defined in #{inspect(schema)}."
    end
  end

  def error(query, place) do
    raise Ecto.QueryError,
      query: query,
      message: "Invalid expression for RavenDB adapter in #{place}"
  end

  defp error(place) do
    raise ArgumentError, "Invalid expression for RavenDB adapter in #{place}"
  end
end

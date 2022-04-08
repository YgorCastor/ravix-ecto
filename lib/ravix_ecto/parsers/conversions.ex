defmodule Ravix.Ecto.Conversions do
  @moduledoc false

  defmacro is_keyword(doc) do
    quote do
      unquote(doc) |> hd |> tuple_size == 2
    end
  end

  defmacro is_literal(value) do
    quote do
      is_atom(unquote(value)) or is_number(unquote(value)) or is_binary(unquote(value))
    end
  end

  def to_ecto(%Ecto.Query.Tagged{type: type, value: value}) do
    {:ok, dumped} = Ecto.Type.adapter_dump(Ravix.Ecto, type, value)
    dumped
  end

  def to_ecto(%{__struct__: _} = value, _pk), do: value

  def to_ecto(map, pk) when is_map(map) do
    Enum.into(map, %{}, fn
      {"@metadata", value} -> {Atom.to_string(pk), to_ecto(value["@id"], pk)}
      {key, value} -> {key, to_ecto(value, pk)}
    end)
  end

  def to_ecto(list, pk) when is_list(list), do: Enum.map(list, &to_ecto(&1, pk))
  def to_ecto(value, _pk), do: value

  def inject_params(doc, params, pk) when is_keyword(doc), do: document(doc, params, pk)

  def inject_params(list, params, pk) when is_list(list),
    do: map(list, &inject_params(&1, params, pk))

  def inject_params(
        %Ecto.Query.Tagged{tag: _tag, type: _type, value: {:^, _, [idx]} = _value},
        params,
        pk
      ) do
    elem(params, idx) |> inject_params(params, pk)
  end

  def inject_params({:^, _, [idx]}, params, pk),
    do: elem(params, idx) |> inject_params(params, pk)

  def inject_params(%{__struct__: _} = struct, _params, pk), do: from_ecto(struct, pk)
  def inject_params(map, params, pk) when is_map(map), do: document(map, params, pk)
  def inject_params(value, _params, pk), do: from_ecto(value, pk)

  def from_ecto(%Ecto.Query.Tagged{tag: :binary_id, value: value}, _pk),
    do: {:ok, value}

  def from_ecto(%Ecto.Query.Tagged{type: type, value: value}, _pk),
    do: Ecto.Type.adapter_dump(Ravix.Ecto, type, value)

  def from_ecto(%{__struct__: _} = value, _pk), do: {:ok, value}
  def from_ecto(map, pk) when is_map(map), do: document(map, pk)
  def from_ecto(keyword, pk) when is_keyword(keyword), do: document(keyword, pk)
  def from_ecto(list, pk) when is_list(list), do: map(list, &from_ecto(&1, pk))
  def from_ecto(value, _pk) when is_literal(value), do: {:ok, value}

  def from_ecto({{_, _, _}, {_, _, _, _}} = value, _pk),
    do: Ecto.Type.adapter_dump(Ravix.Ecto, :naive_datetime, value)

  def from_ecto({_, _, _} = value, _pk), do: Ecto.Type.adapter_dump(Ravix.Ecto, :date, value)

  def from_ecto({_, _, _, _} = value, _pk),
    do: Ecto.Type.adapter_dump(Ravix.Ecto, :time, value)

  def from_ecto(_value, _pk), do: :error

  defp document(doc, pk) do
    map(doc, fn {key, value} ->
      pair(key, value, pk, &from_ecto(&1, pk))
    end)
  end

  defp document(doc, params, pk) do
    map(doc, fn {key, value} ->
      pair(key, value, pk, &inject_params(&1, params, pk))
    end)
  end

  defp pair(key, value, pk, fun) do
    case fun.(value) do
      {:ok, {subkey, encoded}} -> {:ok, {"#{key}.#{subkey}", encoded}}
      {:ok, encoded} -> {:ok, {key(key, pk), encoded}}
      :error -> :error
    end
  end

  defp key(pk, pk), do: :_id

  defp key(key, _) do
    key
  end

  defp map(map, _fun) when is_map(map) and map_size(map) == 0 do
    {:ok, %{}}
  end

  defp map(list, fun) do
    return =
      Enum.flat_map_reduce(list, :ok, fn elem, :ok ->
        case fun.(elem) do
          {:ok, value} -> {[value], :ok}
          :error -> {:halt, :error}
        end
      end)

    case return do
      {values, :ok} -> {:ok, values}
      {_values, :error} -> :error
    end
  end
end

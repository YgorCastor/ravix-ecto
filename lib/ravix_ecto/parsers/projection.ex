defmodule Ravix.Ecto.Parser.Projection do
  alias Ecto.Query, as: EctoQuery

  import Ravix.Ecto.Parser.Shared

  @aggregate_ops [:sum, :avg, :min, :max]

  def project(%EctoQuery{select: nil}, _params, _from), do: {:find, %{}, []}

  def project(
         %EctoQuery{select: %EctoQuery.SelectExpr{fields: fields} = _select} = query,
         params,
         from
       ) do
    project(fields, params, from, query, %{}, [])
  end

  def project([], _params, _from, _query, pacc, facc), do: {:find, pacc, Enum.reverse(facc)}

  # TODO this project function is the same as the one below with a different pattern
  def project(
         [{:&, _, [0]} = field | rest],
         params,
         {_, nil, _} = from,
         query,
         _pacc,
         facc
       ) do
    facc =
      case project(rest, params, from, query, %{}, [field | facc]) do
        {:find, _, facc} ->
          facc

        _other ->
          error(
            query,
            "select clause supports only one of the special functions: `count`, `min`, `max`"
          )
      end

    {:find, %{}, facc}
  end

  def project(
         [{:&, _, [0, nil, _]} = field | rest],
         params,
         {_, nil, _} = from,
         query,
         _pacc,
         facc
       ) do
    # Model is nil, we want empty project, but still extract fields
    facc =
      case project(rest, params, from, query, %{}, [field | facc]) do
        {:find, _, facc} ->
          facc

        _other ->
          error(
            query,
            "select clause supports only one of the special functions: `count`, `min`, `max`"
          )
      end

    {:find, %{}, facc}
  end

  def project(
         [{:&, _, [0, nil, _]} = field | rest],
         params,
         {_, model, pk} = from,
         query,
         pacc,
         facc
       ) do
    pacc = Enum.into(model.__schema__(:fields), pacc, &{field(&1, pk), true})
    facc = [field | facc]

    project(rest, params, from, query, pacc, facc)
  end

  def project(
         [{:&, _, [0, fields, _]} = field | rest],
         params,
         {_, _model, pk} = from,
         query,
         pacc,
         facc
       ) do
    pacc = Enum.into(fields, pacc, &{field(&1, pk), true})
    facc = [field | facc]

    project(rest, params, from, query, pacc, facc)
  end

  def project([%Ecto.Query.Tagged{value: value} | rest], params, from, query, pacc, facc) do
    {_, model, pk} = from

    pacc = Enum.into(model.__schema__(:fields), pacc, &{field(&1, pk), true})
    facc = [{:field, pk, value} | facc]

    project(rest, params, from, query, pacc, facc)
  end

  def project([{{:., _, [_, name]}, _, _} = field | rest], params, from, query, pacc, facc) do
    {_, _, pk} = from

    # Projections use names as in database, fields as in models
    pacc = Map.put(pacc, field(name, pk), true)
    facc = [{:field, name, field} | facc]
    project(rest, params, from, query, pacc, facc)
  end

  # Keyword and interpolated fragments
  def project([{:fragment, _, [args]} = field | rest], params, from, query, pacc, facc)
       when is_list(args) or tuple_size(args) == 3 do
    {_, _, pk} = from

    pacc =
      args
      |> value(params, pk, query, "select clause")
      |> Enum.into(pacc)

    facc = [field | facc]

    project(rest, params, from, query, pacc, facc)
  end

  def project([{op, _, _} | _rest], _params, _from, query, _pacc, _facc)
       when op in @aggregate_ops do
    error(
      query,
      ": Aggregation operations aren't supported in the current version"
    )
  end

  def project([{op, _, _} | _rest], _params, _from, query, _pacc, _facc) when is_op(op) do
    error(query, "select clause")
  end
end

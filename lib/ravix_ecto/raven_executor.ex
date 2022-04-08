defmodule Ravix.Ecto.Executor do
  require OK

  alias Ravix.Documents.Session, as: RavixSession
  alias Ravix.RQL.Query, as: RavenQuery

  def insert(%{repo: repo}, document), do: insert(Keyword.get(repo.config, :store), document)

  def insert(store, document) do
    OK.for do
      session_id <- store.open_session()
      _ <- RavixSession.store(session_id, document)
      updated_store <- RavixSession.save_changes(session_id)
      results = to_keywords(updated_store["Results"])
      _ = store.close_session(session_id)
    after
      results
    end
  end

  def query(%RavenQuery{} = query, %{repo: repo}),
    do: query(query, Keyword.get(repo.config, :store))

  def query(%RavenQuery{} = query, store) do
    OK.try do
      session_id <- store.open_session()
      result <- RavenQuery.list_all(query, session_id)
      _ = store.close_session(session_id)
      parsed_result = parse_raven_result(result, :read)
    after
      parsed_result
    rescue
      err -> err
    end
  end

  defp parse_raven_result(result, :read) do
    rows = Map.get(result, "Results")
    count = Map.get(result, "TotalResults")

    {count, rows}
  end

  defp parse_raven_result(_result, _schema, :update) do
    {:ok, []}
  end

  defp map_to_struct_hack(results, schema) do
    results
    |> Enum.map(fn document ->
      morphed_doc = Morphix.atomorphiform!(document)
      struct(schema, morphed_doc) |> Map.drop([:__meta__])
    end)
  end

  defp remap_hack(results) do
    results
    |> Enum.map(&remap_not_loaded/1)
  end

  defp remap_not_loaded(fields) do
    fields
    |> Enum.map(fn field ->
      case field do
        %Ecto.Association.NotLoaded{} -> nil
        other -> other
      end
    end)
  end

  defp drop_key_names(results) do
    results
    |> Enum.map(&Map.values/1)
  end

  defp to_keywords(results) when is_list(results) do
    results
    |> Enum.map(&to_keywords/1)
  end

  defp to_keywords(result) when is_map(result) do
    result
    |> Morphix.atomorphiform!()
    |> Keyword.new()
  end
end

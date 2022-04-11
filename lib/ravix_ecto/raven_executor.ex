defmodule Ravix.Ecto.Executor do
  require OK

  alias Ravix.Documents.Session, as: RavixSession
  alias Ravix.RQL.Query, as: RavenQuery

  import Ravix.RQL.Query

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

  def update_one(%{repo: repo}, fields, filters),
    do: exec_update_one(Keyword.get(repo.config, :store), fields, filters)

  defp exec_update_one(store, fields, id: id) do
    OK.for do
      session_id <- store.open_session()
      result <- RavixSession.load(session_id, id)
      document_to_update = Enum.at(result["Results"], 0)

      updated_document =
        Enum.reduce(fields, document_to_update, fn {field, value}, document ->
          put_in(document[Atom.to_string(field)], value)
        end)

      _ <-
        RavixSession.store(
          session_id,
          updated_document,
          id,
          updated_document["@metadata"]["@change-vector"]
        )

      _ <- RavixSession.save_changes(session_id)
      _ = store.close_session(session_id)
    after
      updated_document
    end
  end

  def delete_one(%{repo: repo}, filters),
    do: exec_delete_one(Keyword.get(repo.config, :store), filters)

  defp exec_delete_one(store, id: id) do
    OK.for do
      session_id <- store.open_session()
      result <- RavixSession.load(session_id, id)
      document_to_delete = Enum.at(result["Results"], 0)
      _ <- RavixSession.delete(session_id, document_to_delete["@metadata"]["@id"])
      _ <- RavixSession.save_changes(session_id)
      _ = store.close_session(session_id)
    after
      document_to_delete
    end
  end

  def query(%RavenQuery{} = query, %{repo: repo}, kind \\ :read),
    do: exec_query(query, Keyword.get(repo.config, :store), kind)

  defp exec_query(%RavenQuery{} = query, store, kind) do
    OK.try do
      session_id <- store.open_session()

      result <-
        case kind do
          :read -> list_all(query, session_id)
          :delete -> delete_for(query, session_id)
          :update -> update_for(query, session_id)
        end

      _ = store.close_session(session_id)
      parsed_result = parse_raven_result(result, kind)
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

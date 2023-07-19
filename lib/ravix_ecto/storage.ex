defmodule Ravix.Ecto.Storage do
  @behaviour Ecto.Adapter.Storage

  require Logger

  alias Ravix.Operations.Database.Maintenance
  alias Ravix.Connection

  @impl true
  def storage_up(_opts) do
    Logger.debug("[RAVIX-ECTO] Storages are auto-created on RavenDB")
    :ok
  end

  @impl true
  def storage_down(opts) do
    {:ok, _apps} = Application.ensure_all_started(:ravix)
    store = Keyword.get(opts, :store)
    {:ok, state} = Connection.fetch_state(store)

    case Maintenance.delete_database(state) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  @impl true
  def storage_status(opts) do
    {:ok, _apps} = Application.ensure_all_started(:ravix)
    store = Keyword.get(opts, :store)
    {:ok, state} = Connection.fetch_state(store)

    case Maintenance.database_stats(state) do
      {:ok, _} -> :up
      _ -> :down
    end
  end
end

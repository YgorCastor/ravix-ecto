ExUnit.start(
  exclude: [
    :todo,
    :aggregations
  ]
)

Application.put_env(:ecto, :primary_key_type, :binary_id)
Application.put_env(:ecto, :async_integration_tests, false)

defmodule Ecto.Integration.Repo do
  defmacro __using__(opts) do
    quote do
      use Ecto.Repo, unquote(opts)

      @query_event __MODULE__
                   |> Module.split()
                   |> Enum.map(&(&1 |> Macro.underscore() |> String.to_atom()))
                   |> Kernel.++([:query])

      def init(_, opts) do
        fun = &Ecto.Integration.Repo.handle_event/4
        :telemetry.attach_many(__MODULE__, [[:custom], @query_event], fun, :ok)
        {:ok, opts}
      end
    end
  end

  def handle_event(event, latency, metadata, _config) do
    handler = Process.delete(:telemetry) || fn _, _, _ -> :ok end
    handler.(event, latency, metadata)
  end
end

defmodule Ecto.Integration.Case do
  use ExUnit.CaseTemplate

  alias Ecto.Integration.TestRepo
  alias Ravix.Ecto.TestStore

  import Ravix.RQL.Query

  setup_all do
    :ok
  end

  setup do
    _ = start_supervised!({Finch, name: Ravix.Finch})
    _ = start_supervised!(TestRepo)

    {:ok, session_id} = TestStore.open_session()
    {:ok, _} = from("@all_docs") |> delete_for(session_id)
    _ = TestStore.close_session(session_id)

    :ok
  end
end

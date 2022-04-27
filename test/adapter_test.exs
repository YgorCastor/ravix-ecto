defmodule Ravix.Ecto.AdapterTest do
  use ExUnit.Case

  alias Ecto.Integration.TestRepo

  describe "Instantiate a new Adapter" do
    test "the Adapter exists and can be started successfully" do
      _ = start_supervised!(TestRepo)
    end
  end
end

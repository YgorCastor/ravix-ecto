defmodule Ravix.Ecto.StorageTest do
  use Ecto.Integration.Case

  alias Ravix.Ecto.Storage
  alias Ecto.Integration.TestRepo

  test "storage_up/1" do
    assert :ok = Storage.storage_up(TestRepo.config())
  end

  test "storage_down/1" do
    assert :ok = Storage.storage_down(TestRepo.config())
  end

  test "storage_status/1" do
    assert :up = Storage.storage_status(TestRepo.config())
  end
end

defmodule Ecto.Integration.RepoTest do
  use Ecto.Integration.Case

  import Ecto.Query

  alias Ecto.Integration.{
    Post,
    TestRepo
  }

  test "returns already started for started repos" do
    assert {:error, {:already_started, _}} = TestRepo.start_link()
  end

  describe "Queries without joins" do
    test "Fetch all with in clause" do
      TestRepo.insert!(%Post{title: "hello"})

      :timer.sleep(1000)

      assert_raise Ecto.Query.CastError, fn ->
        TestRepo.all(from(p in Post, where: p.title in ^nil))
      end

      assert [] = TestRepo.all(from(p in Post, where: p.title in []))
      assert [] = TestRepo.all(from(p in Post, where: p.title in ["1", "2", "3"]))
      assert [] = TestRepo.all(from(p in Post, where: p.title in ^[]))

      assert TestRepo.all(from(p in Post, where: p.title not in []))
             |> Enum.any?(fn post -> post.title == "hello" end)

      assert TestRepo.all(from(p in Post, where: p.title in ["1", "hello", "3"]))
             |> Enum.any?(fn post -> post.title == "hello" end)

      assert TestRepo.all(from(p in Post, where: p.title in ["1", ^"hello", "3"]))
             |> Enum.any?(fn post -> post.title == "hello" end)

      assert TestRepo.all(from(p in Post, where: p.title in ^["1", "hello", "3"]))
             |> Enum.any?(fn post -> post.title == "hello" end)

      assert_raise Ecto.Query.CastError, fn ->
        TestRepo.all(from(p in Post, where: p.title in ^nil))
      end
    end
  end
end

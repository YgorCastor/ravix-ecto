defmodule Ecto.Integration.RepoTest do
  use Ecto.Integration.Case

  import Ecto.Query

  alias Ecto.Integration.{
    Post,
    CompositePk,
    Permalink,
    Barebone,
    TestRepo,
    Pallet,
    RAW
  }

  test "returns already started for started repos" do
    assert {:error, {:already_started, _}} = TestRepo.start_link()
  end

  describe "Queries without associations" do
    test "should fetch all with in clause" do
      TestRepo.insert!(%Post{title: "hello"})

      :timer.sleep(500)

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

    test "should fetch all using a named from" do
      TestRepo.insert!(%Post{title: "hello"})

      :timer.sleep(500)

      query =
        from(p in Post, as: :post)
        |> where([post: p], p.title == "hello")

      assert TestRepo.all(query)
             |> Enum.any?(fn post -> post.title == "hello" end)
    end

    test "should fetch all without schema" do
      %Post{} = TestRepo.insert!(%Post{title: "title1"})
      %Post{} = TestRepo.insert!(%Post{title: "title2"})

      :timer.sleep(500)

      assert ["title1", "title2"] =
               TestRepo.all(from(p in "posts", order_by: p.title, select: p.title))

      assert [_] = TestRepo.all(from(p in "posts", where: p.title == "title1", select: p.id))
    end

    test "should share metadata for the same collection" do
      TestRepo.insert!(%Post{title: "title1"})
      TestRepo.insert!(%Post{title: "title2"})

      :timer.sleep(500)

      [post1, post2] = TestRepo.all(Post)
      assert :erts_debug.same(post1.__meta__, post2.__meta__)

      [new_post1, new_post2] = TestRepo.all(Post)
      assert :erts_debug.same(post1.__meta__, new_post1.__meta__)
      assert :erts_debug.same(post2.__meta__, new_post2.__meta__)
    end

    test "should throw an error if the prefix is invalid" do
      assert catch_error(TestRepo.all("posts", prefix: "oops"))
    end

    test "should insert, update and delete" do
      post = %Post{title: "insert, update, delete", visits: 1}
      meta = post.__meta__

      assert %Post{} = inserted = TestRepo.insert!(post)
      assert %Post{} = updated = TestRepo.update!(Ecto.Changeset.change(inserted, visits: 2))

      deleted_meta = put_in(meta.state, :deleted)
      assert %Post{__meta__: ^deleted_meta} = TestRepo.delete!(updated)

      loaded_meta = put_in(meta.state, :loaded)
      assert %Post{__meta__: ^loaded_meta} = TestRepo.insert!(post)

      :timer.sleep(500)

      post = TestRepo.one(Post)
      assert post.__meta__.state == :loaded
      assert post.inserted_at
    end

    test "should raise an error if multiple primary keys were defined" do
      assert_raise ArgumentError,
                   "RavenDB adapter does not support multiple primary keys and [:a, :b] were defined in Ecto.Integration.CompositePk.",
                   fn ->
                     TestRepo.insert!(%CompositePk{a: 1, b: 2, name: "first"})
                   end
    end

    test "should insert, update and delete with field source" do
      permalink = %Permalink{url: "url"}
      assert %Permalink{url: "url"} = inserted = TestRepo.insert!(permalink)

      assert %Permalink{url: "new"} =
               updated = TestRepo.update!(Ecto.Changeset.change(inserted, url: "new"))

      assert %Permalink{url: "new"} = TestRepo.delete!(updated)
    end

    test "should ignore prefixes, as RavenDB does not support schemas" do
      post = TestRepo.insert!(%Post{})
      changeset = Ecto.Changeset.change(post, title: "foo")

      TestRepo.insert(%Post{}, prefix: "oops")
      TestRepo.update(changeset, prefix: "oops")
      TestRepo.delete(changeset, prefix: "oops")
    end

    test "should insert and update with changeset" do
      # On insert we merge the fields and changes
      changeset =
        Ecto.Changeset.cast(
          %Post{visits: 13, title: "wrong"},
          %{"title" => "hello", "temp" => "unknown"},
          ~w(title temp)a
        )

      post = TestRepo.insert!(changeset)

      :timer.sleep(500)

      assert %Post{visits: 13, title: "hello", temp: "unknown"} = post
      assert %Post{visits: 13, title: "hello", temp: "temp"} = TestRepo.get!(Post, post.id)

      # On update we merge only fields, direct schema changes are discarded
      changeset =
        Ecto.Changeset.cast(
          %{post | visits: 17},
          %{"title" => "world", "temp" => "unknown"},
          ~w(title temp)a
        )

      assert %Post{visits: 17, title: "world", temp: "unknown"} = TestRepo.update!(changeset)

      :timer.sleep(500)

      assert %Post{visits: 13, title: "world", temp: "temp"} = TestRepo.get!(Post, post.id)
    end

    test "should insert and update with empty changeset" do
      # On insert we merge the fields and changes
      changeset = Ecto.Changeset.cast(%Permalink{}, %{}, ~w())
      assert %Permalink{} = permalink = TestRepo.insert!(changeset)

      # Assert we can update the same value twice,
      # without changes, without triggering stale errors.
      changeset = Ecto.Changeset.cast(permalink, %{}, ~w())
      assert TestRepo.update!(changeset) == permalink
      assert TestRepo.update!(changeset) == permalink
    end

    test "should fail if no primary key is defined and a id field is not present" do
      assert_raise Ecto.ConstraintError, fn -> TestRepo.insert!(%Barebone{}) end
    end

    test "should insert if no primary key is defined and a id field is present" do
      assert %Pallet{} = _pallet = TestRepo.insert!(%Pallet{})
    end

    test "should insert and update with changeset read after writes" do
      assert %{id: cid, lock_version: 1} = raw = TestRepo.insert!(%RAW{lock_version: 1})

      # Set the counter to 11, so we can read it soon
      TestRepo.update_all(from(u in RAW, where: u.id == ^cid), set: [lock_version: 11])

      # We will read back on update too
      changeset = Ecto.Changeset.cast(raw, %{"text" => "0"}, ~w(text)a)
      assert %{id: ^cid, lock_version: 1, text: "0"} = TestRepo.update!(changeset)
    end

    test "should insert autogenerates for custom type" do
      post = TestRepo.insert!(%Post{uuid: nil})
      assert byte_size(post.uuid) == 36

      :timer.sleep(500)

      assert TestRepo.get_by(Post, [uuid: post.uuid]) == post
    end
  end
end

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
    RAW,
    User,
    Comment,
    Custom,
    Foo
  }

  test "returns already started for started repos" do
    assert {:error, {:already_started, _}} = TestRepo.start_link()
  end

  describe "Queries without associations" do
    test "should fetch all with in clause" do
      TestRepo.insert!(%Post{title: "hello"})

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
      TestRepo.insert!(%Post{title: "hello"}, returning: true)

      query =
        from(p in Post, as: :post)
        |> where([post: p], p.title == "hello")

      assert TestRepo.all(query)
             |> Enum.any?(fn post -> post.title == "hello" end)
    end

    test "should fetch all without schema" do
      %Post{} = TestRepo.insert!(%Post{title: "title1"})
      %Post{} = TestRepo.insert!(%Post{title: "title2"})

      assert ["title1", "title2"] =
               TestRepo.all(from(p in "posts", order_by: p.title, select: p.title))

      assert [_] = TestRepo.all(from(p in "posts", where: p.title == "title1", select: p.id))
    end

    test "should share metadata for the same collection" do
      TestRepo.insert!(%Post{title: "title1"})
      TestRepo.insert!(%Post{title: "title2"})

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
      {:ok, cost} = Decimal.cast("1234325.34324234")

      post = %Post{
        title: "insert, update, delete",
        visits: 1,
        cost: cost,
        post_time: ~T[23:00:07]
      }

      meta = post.__meta__

      assert %Post{cost: returned_cost, post_time: returned_time} =
               inserted = TestRepo.insert!(post)

      assert ^cost = returned_cost
      assert ~T[23:00:07] = returned_time

      assert %Post{} = updated = TestRepo.update!(Ecto.Changeset.change(inserted, visits: 2))

      deleted_meta = put_in(meta.state, :deleted)
      assert %Post{__meta__: ^deleted_meta} = TestRepo.delete!(updated)

      loaded_meta = put_in(meta.state, :loaded)
      assert %Post{__meta__: ^loaded_meta} = TestRepo.insert!(post)

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
      assert TestRepo.get_by(Post, uuid: post.uuid) == post
    end

    test "should insert with user-assigned primary key" do
      assert %Post{id: "noice"} = TestRepo.insert!(%Post{id: "noice"})
    end

    test "should insert and update with user-assigned primary key in changeset" do
      new_id = UUID.uuid4()

      changeset = Ecto.Changeset.cast(%Post{id: "old_id"}, %{"id" => new_id}, ~w(id)a)
      assert %Post{id: ^new_id} = post = TestRepo.insert!(changeset)

      new_id = UUID.uuid4()

      changeset = Ecto.Changeset.cast(post, %{"id" => new_id}, ~w(id)a)
      assert %Post{id: ^new_id} = TestRepo.update!(changeset)
    end

    test "should insert and fetch a schema with utc timestamps" do
      datetime = DateTime.from_unix!(System.os_time(:second), :second)
      TestRepo.insert!(%User{inserted_at: datetime})
      assert [%{inserted_at: ^datetime}] = TestRepo.all(User)
    end

    test "should support optimistic locking in update/delete operations" do
      import Ecto.Changeset, only: [cast: 3, optimistic_lock: 2]
      base_comment = TestRepo.insert!(%Comment{})

      changeset_ok =
        base_comment
        |> cast(%{"text" => "foo.bar"}, ~w(text)a)
        |> optimistic_lock(:lock_version)

      TestRepo.update!(changeset_ok)

      changeset_stale =
        base_comment
        |> cast(%{"text" => "foo.bat"}, ~w(text)a)
        |> optimistic_lock(:lock_version)

      assert_raise Ecto.StaleEntryError, fn -> TestRepo.update!(changeset_stale) end
      assert_raise Ecto.StaleEntryError, fn -> TestRepo.delete!(changeset_stale) end
    end

    test "should dupport optimistic locking in update operation with nil field" do
      import Ecto.Changeset, only: [cast: 3, optimistic_lock: 3]

      base_comment =
        %Comment{}
        |> cast(%{lock_version: nil}, [:lock_version])
        |> TestRepo.insert!()

      incrementer = fn
        nil -> 1
        old_value -> old_value + 1
      end

      changeset_ok =
        base_comment
        |> cast(%{"text" => "foo.bar"}, ~w(text)a)
        |> optimistic_lock(:lock_version, incrementer)

      updated = TestRepo.update!(changeset_ok)
      assert updated.text == "foo.bar"
      assert updated.lock_version == 1
    end

    test "should support optimistic locking in delete operation with nil field" do
      import Ecto.Changeset, only: [cast: 3, optimistic_lock: 3]

      base_comment =
        %Comment{}
        |> cast(%{lock_version: nil}, [:lock_version])
        |> TestRepo.insert!()

      incrementer = fn
        nil -> 1
        old_value -> old_value + 1
      end

      changeset_ok = optimistic_lock(base_comment, :lock_version, incrementer)
      TestRepo.delete!(changeset_ok)

      refute TestRepo.get(Comment, base_comment.id)
    end

    test "should not raise on unique constraints, RavenDB does not support it" do
      changeset = Ecto.Changeset.change(%Post{}, uuid: Ecto.UUID.generate())
      {:ok, _} = TestRepo.insert(changeset)

      {:ok, _} =
        changeset
        |> Ecto.Changeset.unique_constraint(:uuid, name: :posts_email_changeset)
        |> TestRepo.insert()
    end

    test "should get(!) successfully" do
      post1 = TestRepo.insert!(%Post{title: "1"})
      post2 = TestRepo.insert!(%Post{title: "2"})

      assert post1 == TestRepo.get(Post, post1.id)
      # With casting
      assert post2 == TestRepo.get(Post, to_string(post2.id))

      assert post1 == TestRepo.get!(Post, post1.id)
      # With casting
      assert post2 == TestRepo.get!(Post, to_string(post2.id))

      TestRepo.delete!(post1)

      assert TestRepo.get(Post, post1.id) == nil

      assert_raise Ecto.NoResultsError, fn ->
        TestRepo.get!(Post, post1.id)
      end
    end

    @tag :todo
    test "should get(!) with custom source" do
      custom = Ecto.put_meta(%Custom{}, source: "posts")
      custom = TestRepo.insert!(custom)
      bid = custom.bid

      assert %Custom{bid: ^bid, __meta__: %{source: "posts"}} =
               TestRepo.get(from(c in {"posts", Custom}), bid)
    end

    test "should get(!) with binary_id" do
      custom = TestRepo.insert!(%Custom{})
      bid = custom.bid
      assert %Custom{bid: ^bid} = TestRepo.get(Custom, bid)
    end

    test "should get_by(!) successfully" do
      post1 = TestRepo.insert!(%Post{title: "1", visits: 1})
      post2 = TestRepo.insert!(%Post{title: "2", visits: 2})

      # assert post1 == TestRepo.get_by(Post, id: post1.id)
      # assert post1 == TestRepo.get_by(Post, title: post1.title)
      assert post1 == TestRepo.get_by(Post, id: post1.id, title: post1.title)

      # With casting
      assert post2 == TestRepo.get_by(Post, id: to_string(post2.id))
      assert nil == TestRepo.get_by(Post, title: "hey")
      assert nil == TestRepo.get_by(Post, id: post2.id, visits: 3)

      assert post1 == TestRepo.get_by!(Post, id: post1.id)
      assert post1 == TestRepo.get_by!(Post, title: post1.title)
      assert post1 == TestRepo.get_by!(Post, id: post1.id, visits: 1)
      # With casting
      assert post2 == TestRepo.get_by!(Post, id: to_string(post2.id))

      assert post1 == TestRepo.get_by!(Post, %{id: post1.id})

      assert_raise Ecto.NoResultsError, fn ->
        TestRepo.get_by!(Post, id: post2.id, title: "hey")
      end
    end

    test "should reload successfully" do
      post1 = TestRepo.insert!(%Post{title: "1", visits: 1})
      post2 = TestRepo.insert!(%Post{title: "2", visits: 2})
      non_existent_id = UUID.uuid4()

      assert post1 == TestRepo.reload(post1)
      assert [post1, post2] == TestRepo.reload([post1, post2])

      assert [post1, post2, nil] == TestRepo.reload([post1, post2, %Post{id: non_existent_id}])

      assert nil == TestRepo.reload(%Post{id: non_existent_id})

      # keeps order as received in the params
      assert [post2, post1] == TestRepo.reload([post2, post1])

      TestRepo.update_all(Post, inc: [visits: 1])

      :timer.sleep(500)

      assert [%{visits: 2}, %{visits: 3}] = TestRepo.reload([post1, post2])
    end

    test "reload should ignore preloads" do
      post = TestRepo.insert!(%Post{title: "1", visits: 1}) |> TestRepo.preload(:comments)

      assert %{comments: %Ecto.Association.NotLoaded{}} = TestRepo.reload(post)
    end

    test "reload! should throw exceptions" do
      post1 = TestRepo.insert!(%Post{title: "1", visits: 1})
      post2 = TestRepo.insert!(%Post{title: "2", visits: 2})
      non_existent_id = UUID.uuid4()

      assert post1 == TestRepo.reload!(post1)
      assert [post1, post2] == TestRepo.reload!([post1, post2])

      assert_raise RuntimeError, ~r"could not reload", fn ->
        TestRepo.reload!([post1, post2, %Post{id: non_existent_id}])
      end

      assert_raise Ecto.NoResultsError, fn ->
        TestRepo.reload!(%Post{id: non_existent_id})
      end

      assert [post2, post1] == TestRepo.reload([post2, post1])

      TestRepo.update_all(Post, inc: [visits: 1])

      :timer.sleep(500)

      assert [%{visits: 2}, %{visits: 3}] = TestRepo.reload!([post1, post2])
    end

    test "first, last and one(!)" do
      post1 = TestRepo.insert!(%Post{title: "1"})
      post2 = TestRepo.insert!(%Post{title: "2"})

      assert post1 == Post |> first(:title) |> TestRepo.one()
      assert post2 == Post |> last(:title) |> TestRepo.one()

      query = from(p in Post, order_by: p.title)
      assert post1 == query |> first |> TestRepo.one()
      assert post2 == query |> last |> TestRepo.one()

      query = from(p in Post, order_by: [desc: p.title], limit: 10)
      assert post2 == query |> first |> TestRepo.one()
      assert post1 == query |> last |> TestRepo.one()

      query = from(p in Post, where: is_nil(p.id))
      refute query |> first |> TestRepo.one()
      refute query |> last |> TestRepo.one()
      assert_raise Ecto.NoResultsError, fn -> query |> first |> TestRepo.one!() end
      assert_raise Ecto.NoResultsError, fn -> query |> last |> TestRepo.one!() end
    end

    test "limit and offset" do
      post1 = TestRepo.insert!(%Post{title: "1"})
      post2 = TestRepo.insert!(%Post{title: "2"})

      query = from(p in Post)
      assert post1 == query |> limit(1) |> offset(0) |> TestRepo.one()
      assert post2 == query |> limit(1) |> offset(1) |> TestRepo.one()
    end

    test "exists? should work" do
      TestRepo.insert!(%Post{title: "1", visits: 2})
      TestRepo.insert!(%Post{title: "2", visits: 1})

      query = from(p in Post, where: not is_nil(p.title), limit: 2)
      assert query |> TestRepo.exists?() == true

      query = from(p in Post, where: p.title == "1", select: p.title)
      assert query |> TestRepo.exists?() == true

      query = from(p in Post, where: is_nil(p.id))
      assert query |> TestRepo.exists?() == false

      query = from(p in Post, where: is_nil(p.id))
      assert query |> TestRepo.exists?() == false
    end

    test "exists? with group_by" do
      TestRepo.insert!(%Post{title: "1", visits: 2})
      TestRepo.insert!(%Post{title: "2", visits: 1})

      query =
        from(p in Post,
          select: p.visits,
          group_by: p.visits,
          where: p.visits > 1
        )

      assert query |> TestRepo.exists?() == true
    end

    test "should allow group by id" do
      TestRepo.insert!(%Post{title: "1", visits: 2})
      TestRepo.insert!(%Post{title: "2", visits: 1})

      query =
        from(p in Post,
          select: p.visits,
          group_by: [p.visits, p.id],
          where: p.visits > 1
        )

      assert query |> TestRepo.exists?() == true
    end

    test "havings should throw an exception, RavenDB does not support it" do
      TestRepo.insert!(%Post{title: "1", visits: 2})

      query =
        from(p in Post,
          select: {p.visits, avg(p.visits)},
          group_by: p.visits,
          having: avg(p.visits) > 1
        )

      assert_raise Ecto.QueryError, fn -> query |> TestRepo.exists?() end
    end

    test "should insert all" do
      assert {2, nil} =
               TestRepo.insert_all("comments", [
                 [id: UUID.uuid4(), text: "1"],
                 %{id: UUID.uuid4(), text: "2", lock_version: 2}
               ])

      assert {2, nil} =
               TestRepo.insert_all({"comments", Comment}, [
                 [text: "3"],
                 %{text: "4", lock_version: 2}
               ])

      assert [
               %Comment{text: "1", lock_version: 1},
               %Comment{text: "2", lock_version: 2},
               %Comment{text: "3", lock_version: 1},
               %Comment{text: "4", lock_version: 2}
             ] = TestRepo.all(Comment) |> Enum.sort(&(&1.text <= &2.text))

      assert {2, nil} = TestRepo.insert_all(Post, [[], []])
      assert [%Post{}, %Post{}] = TestRepo.all(Post)

      assert {0, nil} = TestRepo.insert_all("posts", [])
      assert {0, nil} = TestRepo.insert_all({"posts", Post}, [])
    end

    @tag :todo
    test "should insert all with query for single fields" do
      comment = TestRepo.insert!(%Comment{text: "1", lock_version: 1})

      :timer.sleep(500)

      text_query = from(c in Comment, select: c.text, where: [id: ^comment.id, lock_version: 1])

      lock_version_query = from(c in Comment, select: c.lock_version, where: [id: ^comment.id])

      rows = [
        [text: "2", lock_version: lock_version_query],
        [lock_version: lock_version_query, text: "3"],
        [text: text_query],
        [text: text_query, lock_version: lock_version_query],
        [lock_version: 6, text: "6"]
      ]

      assert {5, nil} = TestRepo.insert_all(Comment, rows, [])

      inserted_rows =
        Comment
        |> where([c], c.id != ^comment.id)
        |> TestRepo.all()
        |> Enum.sort(&(&1.text <= &2.text))

      assert [
               %Comment{text: "1"},
               %Comment{text: "1", lock_version: 1},
               %Comment{text: "2", lock_version: 1},
               %Comment{text: "3", lock_version: 1},
               %Comment{text: "6", lock_version: 6}
             ] = inserted_rows
    end

    @tag :todo
    test "insert_all with query and conflict target" do
      {:ok, %Post{id: id}} =
        TestRepo.insert(%Post{
          title: "A generic title"
        })

      source =
        from(p in Post,
          select: %{
            title: fragment("concat(?, ?, ?)", p.title, type(^" suffix ", :string), p.id)
          }
        )

      assert {1, _} =
               TestRepo.insert_all(Post, source, conflict_target: [:id], on_conflict: :replace_all)

      expected_id = id + 1
      expected_title = "A generic title suffix #{id}"

      assert %Post{title: ^expected_title} = TestRepo.get(Post, expected_id)
    end

    @tag :todo
    test "should insert_all with query and returning" do
      {:ok, %Post{id: id}} =
        TestRepo.insert(%Post{
          title: "A generic title"
        })

      source =
        from(p in Post,
          select: %{
            title: fragment("concat(?, ?, ?)", p.title, type(^" suffix ", :string), p.id)
          }
        )

      assert {1, returns} = TestRepo.insert_all(Post, source, returning: [:id, :title])

      expected_id = id + 1
      expected_title = "A generic title suffix #{id}"
      assert [%Post{id: ^expected_id, title: ^expected_title}] = returns
    end

    @tag :todo
    test "insert_all with query and on_conflict" do
      {:ok, %Post{id: id}} =
        TestRepo.insert(%Post{
          title: "A generic title"
        })

      source =
        from(p in Post,
          select: %{
            title: fragment("concat(?, ?, ?)", p.title, type(^" suffix ", :string), p.id)
          }
        )

      assert {1, _} = TestRepo.insert_all(Post, source, on_conflict: :replace_all)

      expected_id = id + 1
      expected_title = "A generic title suffix #{id}"

      assert %Post{title: ^expected_title} = TestRepo.get(Post, expected_id)
    end

    @tag :todo
    test "insert_all with query" do
      {:ok, %Post{id: id}} =
        TestRepo.insert(%Post{
          title: "A generic title"
        })

      source =
        from(p in Post,
          select: %{
            title: fragment("concat(?, ?, ?)", p.title, type(^" suffix ", :string), p.id)
          }
        )

      assert {1, _} = TestRepo.insert_all(Post, source)

      expected_id = id + 1
      expected_title = "A generic title suffix #{id}"

      assert %Post{title: ^expected_title} = TestRepo.get(Post, expected_id)
    end

    test "should insert all with returning with schema" do
      assert {0, []} = TestRepo.insert_all(Comment, [], returning: true)
      assert {0, nil} = TestRepo.insert_all(Comment, [], returning: false)

      {2, results} =
        TestRepo.insert_all(Comment, [[text: "1"], [text: "2"]], returning: [:text, :id])

      [c1, c2] = results |> Enum.sort(&(&1.text <= &2.text))

      assert %Comment{text: "1", __meta__: %{state: :loaded}} = c1
      assert %Comment{text: "2", __meta__: %{state: :loaded}} = c2

      {2, results} = TestRepo.insert_all(Comment, [[text: "3"], [text: "4"]], returning: true)

      [c1, c2] = results |> Enum.sort(&(&1.text <= &2.text))

      assert %Comment{text: "3", __meta__: %{state: :loaded}} = c1
      assert %Comment{text: "4", __meta__: %{state: :loaded}} = c2
    end

    test "should insert all with returning without schema" do
      {2, results} =
        TestRepo.insert_all(
          "comments",
          [[id: UUID.uuid4(), text: "1"], [id: UUID.uuid4(), text: "2"]],
          returning: [:id, :text]
        )

      [c1, c2] = results |> Enum.sort(&(&1.text <= &2.text))

      assert %{id: _, text: "1"} = c1
      assert %{id: _, text: "2"} = c2

      assert_raise ArgumentError, fn ->
        TestRepo.insert_all("comments", [[text: "1"], [text: "2"]], returning: true)
      end
    end

    test "should insert all with dumping" do
      uuid = Ecto.UUID.generate()
      assert {1, nil} = TestRepo.insert_all(Post, [%{uuid: uuid}])
      assert [%Post{uuid: ^uuid, title: nil}] = TestRepo.all(Post)
    end

    test "insert all autogenerates for binary_id type" do
      custom = TestRepo.insert!(%Custom{bid: nil})
      assert custom.bid
      assert TestRepo.get(Custom, custom.bid)
      assert TestRepo.delete!(custom)
      refute TestRepo.get(Custom, custom.bid)

      uuid = Ecto.UUID.generate()
      assert {2, nil} = TestRepo.insert_all(Custom, [%{uuid: uuid}, %{bid: custom.bid}])

      assert [%Custom{bid: bid2, uuid: nil}, %Custom{bid: bid1, uuid: ^uuid}] =
               Enum.sort_by(TestRepo.all(Custom), & &1.uuid)

      assert bid1 && bid2
      assert custom.bid != bid1
      assert custom.bid == bid2
    end

    test "should update all" do
      assert post1 = TestRepo.insert!(%Post{title: "1"})
      assert post2 = TestRepo.insert!(%Post{title: "2"})
      assert post3 = TestRepo.insert!(%Post{title: "3"})

      # RavenDB does not return the amount of affected docs, need to check
      assert {-1, nil} = TestRepo.update_all(Post, set: [title: "x"])

      :timer.sleep(500)

      assert %Post{title: "x"} = TestRepo.reload(post1)
      assert %Post{title: "x"} = TestRepo.reload(post2)
      assert %Post{title: "x"} = TestRepo.reload(post3)

      assert {-1, nil} = TestRepo.update_all("posts", set: [title: nil])

      :timer.sleep(500)

      assert %Post{title: nil} = TestRepo.reload(post1)
      assert %Post{title: nil} = TestRepo.reload(post2)
      assert %Post{title: nil} = TestRepo.reload(post3)
    end

    @tag :todo
    test "should update all with returning with schema" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
      assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
      assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

      assert {3, posts} = TestRepo.update_all(select(Post, [p], p), set: [title: "x"])

      [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
      assert %Post{id: ^id1, title: "x"} = p1
      assert %Post{id: ^id2, title: "x"} = p2
      assert %Post{id: ^id3, title: "x"} = p3

      assert {3, posts} = TestRepo.update_all(select(Post, [:id, :visits]), set: [visits: 11])

      [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
      assert %Post{id: ^id1, title: nil, visits: 11} = p1
      assert %Post{id: ^id2, title: nil, visits: 11} = p2
      assert %Post{id: ^id3, title: nil, visits: 11} = p3
    end

    @tag :todo
    test "should update all with returning without schema" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
      assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
      assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

      assert {3, posts} = TestRepo.update_all(select("posts", [:id, :title]), set: [title: "x"])

      [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
      assert p1 == %{id: id1, title: "x"}
      assert p2 == %{id: id2, title: "x"}
      assert p3 == %{id: id3, title: "x"}
    end

    test "should update all with filter" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
      assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
      assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

      query =
        from(p in Post,
          where: p.title == "1" or p.title == "2",
          update: [set: [visits: ^17]]
        )

      :timer.sleep(500)

      assert {-1, nil} = TestRepo.update_all(query, set: [title: "x"])

      :timer.sleep(500)

      assert %Post{title: "x", visits: 17} = TestRepo.get(Post, id1)
      assert %Post{title: "x", visits: 17} = TestRepo.get(Post, id2)
      assert %Post{title: "3", visits: nil} = TestRepo.get(Post, id3)
    end

    test "should update all no entries" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
      assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
      assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

      query = from(p in Post, where: p.title == "4")
      assert {-1, nil} = TestRepo.update_all(query, set: [title: "x"])

      assert %Post{title: "1"} = TestRepo.get(Post, id1)
      assert %Post{title: "2"} = TestRepo.get(Post, id2)
      assert %Post{title: "3"} = TestRepo.get(Post, id3)
    end

    test "should update all increment syntax" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1", visits: 0})
      assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2", visits: 1})

      :timer.sleep(500)

      # Positive
      query = from(p in Post, where: not is_nil(p.id), update: [inc: [visits: 2]])
      assert {-1, nil} = TestRepo.update_all(query, [])

      :timer.sleep(500)

      assert %Post{visits: 2} = TestRepo.get(Post, id1)
      assert %Post{visits: 3} = TestRepo.get(Post, id2)

      # Negative
      query = from(p in Post, where: not is_nil(p.id), update: [inc: [visits: -1]])
      assert {-1, nil} = TestRepo.update_all(query, [])

      :timer.sleep(500)

      assert %Post{visits: 1} = TestRepo.get(Post, id1)
      assert %Post{visits: 2} = TestRepo.get(Post, id2)
    end

    test "should update all with casting and dumping on id type field" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{})
      assert {-1, nil} = TestRepo.update_all(Post, set: [counter: to_string(1)])

      :timer.sleep(500)

      assert %Post{counter: 1} = TestRepo.get(Post, id1)
    end

    test "should update all with casting and dumping" do
      visits = 13
      datetime = ~N[2014-01-16 20:26:51]
      assert %Post{id: id} = TestRepo.insert!(%Post{})

      assert {-1, nil} = TestRepo.update_all(Post, set: [visits: visits, inserted_at: datetime])

      :timer.sleep(500)

      assert %Post{visits: 13, inserted_at: ^datetime} = TestRepo.get(Post, id)
    end

    test "should delete all" do
      assert %Post{} = TestRepo.insert!(%Post{title: "1"})
      assert %Post{} = TestRepo.insert!(%Post{title: "2"})
      assert %Post{} = TestRepo.insert!(%Post{title: "3"})

      assert {-1, nil} = TestRepo.delete_all(Post)

      :timer.sleep(500)

      assert [] = TestRepo.all(Post)
    end

    @tag :todo
    test "delete all with returning with schema" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
      assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
      assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

      assert {3, posts} = TestRepo.delete_all(select(Post, [p], p))

      [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
      assert %Post{id: ^id1, title: "1"} = p1
      assert %Post{id: ^id2, title: "2"} = p2
      assert %Post{id: ^id3, title: "3"} = p3
    end

    @tag :todo
    test "delete all with returning without schema" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
      assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
      assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

      assert {3, posts} = TestRepo.delete_all(select("posts", [:id, :title]))

      [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
      assert p1 == %{id: id1, title: "1"}
      assert p2 == %{id: id2, title: "2"}
      assert p3 == %{id: id3, title: "3"}
    end

    test "should delete all with filter" do
      assert %Post{} = TestRepo.insert!(%Post{title: "1"})
      assert %Post{} = TestRepo.insert!(%Post{title: "2"})
      assert %Post{} = TestRepo.insert!(%Post{title: "3"})

      :timer.sleep(500)

      query = from(p in Post, where: p.title == "1" or p.title == "2")
      assert {-1, nil} = TestRepo.delete_all(query)

      :timer.sleep(500)

      assert [%Post{}] = TestRepo.all(Post)
    end

    test "should delete all no entries" do
      assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
      assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
      assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

      query = from(p in Post, where: p.title == "4")

      assert {-1, nil} = TestRepo.delete_all(query)

      :timer.sleep(500)

      assert %Post{title: "1"} = TestRepo.get(Post, id1)
      assert %Post{title: "2"} = TestRepo.get(Post, id2)
      assert %Post{title: "3"} = TestRepo.get(Post, id3)
    end

    test "virtual field should work" do
      assert %Post{id: id} = TestRepo.insert!(%Post{title: "1"})
      assert TestRepo.get(Post, id).temp == "temp"
    end

    test "should query successfully" do
      %Post{} = TestRepo.insert!(%Post{title: "1", visits: 13})

      :timer.sleep(500)

      assert [{"1", 13}] ==
               TestRepo.all(from(p in Post, select: {p.title, p.visits}))

      assert [["1", 13]] ==
               TestRepo.all(from(p in Post, select: [p.title, p.visits]))

      assert [%{:title => "1", 3 => 13, "visits" => 13}] ==
               TestRepo.all(
                 from(p in Post,
                   select: %{
                     :title => p.title,
                     "visits" => p.visits,
                     3 => p.visits
                   }
                 )
               )

      assert [%{:title => "1", "1" => 13, "visits" => 13}] ==
               TestRepo.all(
                 from(p in Post,
                   select: %{
                     :title => p.title,
                     p.title => p.visits,
                     "visits" => p.visits
                   }
                 )
               )

      assert [%Foo{title: "1"}] ==
               TestRepo.all(from(p in Post, select: %Foo{title: p.title}))
    end

    test "should map update" do
      %Post{} = TestRepo.insert!(%Post{title: "1", visits: 13})

      :timer.sleep(500)

      assert [%Post{:title => "new title", visits: 13}] =
               TestRepo.all(from(p in Post, select: %{p | title: "new title"}))

      assert [%Post{title: "new title", visits: 13}] =
               TestRepo.all(from(p in Post, select: %Post{p | title: "new title"}))

      assert_raise KeyError, fn ->
        TestRepo.all(from(p in Post, select: %{p | unknown: "new title"}))
      end

      assert_raise BadMapError, fn ->
        TestRepo.all(from(p in Post, select: %{p.title | title: "new title"}))
      end

      assert_raise BadStructError, fn ->
        TestRepo.all(from(p in Post, select: %Foo{p | title: p.title}))
      end
    end

    test "should take with structs" do
      %{id: pid1} = TestRepo.insert!(%Post{title: "1"})
      %{id: pid2} = TestRepo.insert!(%Post{title: "2"})
      %{id: pid3} = TestRepo.insert!(%Post{title: "3"})

      :timer.sleep(500)

      [p1, p2, p3] =
        Post |> select([p], struct(p, [:title])) |> order_by([:title]) |> TestRepo.all()

      refute p1.id
      assert p1.title == "1"
      assert match?(%Post{}, p1)
      refute p2.id
      assert p2.title == "2"
      assert match?(%Post{}, p2)
      refute p3.id
      assert p3.title == "3"
      assert match?(%Post{}, p3)

      [p1, p2, p3] = Post |> select([:id]) |> order_by([:title]) |> TestRepo.all()
      assert %Post{id: ^pid1} = p1
      assert %Post{id: ^pid2} = p2
      assert %Post{id: ^pid3} = p3
    end

    test "should take with maps" do
      TestRepo.insert!(%Post{title: "1"})
      TestRepo.insert!(%Post{title: "2"})
      TestRepo.insert!(%Post{title: "3"})

      [p1, p2, p3] =
        "posts" |> select([p], map(p, [:title])) |> order_by([:title]) |> TestRepo.all()

      assert p1 == %{title: "1"}
      assert p2 == %{title: "2"}
      assert p3 == %{title: "3"}
    end

    test "should take with single nil column" do
      %Post{} = TestRepo.insert!(%Post{title: "1", counter: nil})

      :timer.sleep(500)

      assert %{counter: nil} =
               TestRepo.one(from(p in Post, where: p.title == "1", select: [:counter]))
    end

    test "should support field source" do
      TestRepo.insert!(%Permalink{url: "url"})

      :timer.sleep(500)

      assert ["url"] = Permalink |> select([p], p.url) |> TestRepo.all()
    end

    @tag :todo
    test "should query count distinct" do
      TestRepo.insert!(%Post{title: "1"})
      TestRepo.insert!(%Post{title: "1"})
      TestRepo.insert!(%Post{title: "2"})

      :timer.sleep(500)

      assert [3] == Post |> select([p], count(p.title)) |> TestRepo.all()
      assert [2] == Post |> select([p], count(p.title, :distinct)) |> TestRepo.all()
    end

    test "should query where interpolation" do
      post1 = TestRepo.insert!(%Post{title: "1"})
      post2 = TestRepo.insert!(%Post{title: "2"})

      :timer.sleep(500)

      assert [post1, post2] == Post |> where([], []) |> TestRepo.all() |> Enum.sort_by(& &1.title)
      assert [post1] == Post |> where([], title: "1") |> TestRepo.all()
      assert [post1] == Post |> where([], title: "1", id: ^post1.id) |> TestRepo.all()

      params0 = []
      params1 = [title: "1"]
      params2 = [title: "1", id: post1.id]

      assert [post1, post2] ==
               from(Post, where: ^params0) |> TestRepo.all() |> Enum.sort_by(& &1.title)

      assert [post1] == from(Post, where: ^params1) |> TestRepo.all()
      assert [post1] == from(Post, where: ^params2) |> TestRepo.all()

      post3 = TestRepo.insert!(%Post{title: "2", uuid: nil})
      params3 = [title: "2", uuid: post3.uuid]
      assert [post3] == from(Post, where: ^params3) |> TestRepo.all()
    end
  end

  describe "Queries with associations" do
    @describetag :todo

    test "take with preload assocs" do
      %{id: pid} = TestRepo.insert!(%Post{title: "post"})
      TestRepo.insert!(%Comment{post_id: pid, text: "comment"})
      fields = [:id, :title, comments: [:text, :post_id]]

      [p] = Post |> preload(:comments) |> select([p], ^fields) |> TestRepo.all()
      assert %Post{title: "post"} = p
      assert [%Comment{text: "comment"}] = p.comments

      [p] = Post |> preload(:comments) |> select([p], struct(p, ^fields)) |> TestRepo.all()
      assert %Post{title: "post"} = p
      assert [%Comment{text: "comment"}] = p.comments

      [p] = Post |> preload(:comments) |> select([p], map(p, ^fields)) |> TestRepo.all()
      assert p == %{id: pid, title: "post", comments: [%{text: "comment", post_id: pid}]}
    end

    test "take with nil preload assoc" do
      %{id: cid} = TestRepo.insert!(%Comment{text: "comment"})
      fields = [:id, :text, post: [:title]]

      [c] = Comment |> preload(:post) |> select([c], ^fields) |> TestRepo.all()
      assert %Comment{id: ^cid, text: "comment", post: nil} = c

      [c] = Comment |> preload(:post) |> select([c], struct(c, ^fields)) |> TestRepo.all()
      assert %Comment{id: ^cid, text: "comment", post: nil} = c

      [c] = Comment |> preload(:post) |> select([c], map(c, ^fields)) |> TestRepo.all()
      assert c == %{id: cid, text: "comment", post: nil}
    end

    test "take with join assocs" do
      %{id: pid} = TestRepo.insert!(%Post{title: "post"})
      %{id: cid} = TestRepo.insert!(%Comment{post_id: pid, text: "comment"})
      fields = [:id, :title, comments: [:text, :post_id, :id]]

      query =
        from(p in Post,
          where: p.id == ^pid,
          join: c in assoc(p, :comments),
          preload: [comments: c]
        )

      p = TestRepo.one(from(q in query, select: ^fields))
      assert %Post{title: "post"} = p
      assert [%Comment{text: "comment"}] = p.comments

      p = TestRepo.one(from(q in query, select: struct(q, ^fields)))
      assert %Post{title: "post"} = p
      assert [%Comment{text: "comment"}] = p.comments

      p = TestRepo.one(from(q in query, select: map(q, ^fields)))
      assert p == %{id: pid, title: "post", comments: [%{text: "comment", post_id: pid, id: cid}]}
    end

    test "take with join assocs and single nil column" do
      %{id: post_id} = TestRepo.insert!(%Post{title: "1"}, counter: nil)
      TestRepo.insert!(%Comment{post_id: post_id, text: "comment"})

      assert %{counter: nil} ==
               TestRepo.one(
                 from(p in Post,
                   join: c in assoc(p, :comments),
                   where: p.title == "1",
                   select: map(p, [:counter])
                 )
               )
    end

    test "merge" do
      date = Date.utc_today()

      %Post{id: post_id} =
        TestRepo.insert!(%Post{title: "1", counter: nil, posted: date, public: false})

      # Merge on source
      assert [%Post{title: "2"}] = Post |> select([p], merge(p, %{title: "2"})) |> TestRepo.all()

      assert [%Post{title: "2"}] =
               Post |> select([p], p) |> select_merge([p], %{title: "2"}) |> TestRepo.all()

      # Merge on struct
      assert [%Post{title: "2"}] =
               Post |> select([p], merge(%Post{title: p.title}, %{title: "2"})) |> TestRepo.all()

      assert [%Post{title: "2"}] =
               Post
               |> select([p], %Post{title: p.title})
               |> select_merge([p], %{title: "2"})
               |> TestRepo.all()

      # Merge on map
      assert [%{title: "2"}] =
               Post |> select([p], merge(%{title: p.title}, %{title: "2"})) |> TestRepo.all()

      assert [%{title: "2"}] =
               Post
               |> select([p], %{title: p.title})
               |> select_merge([p], %{title: "2"})
               |> TestRepo.all()

      # Merge on outer join with map
      %Permalink{} = TestRepo.insert!(%Permalink{post_id: post_id, url: "Q", title: "Z"})

      # left join record is present
      assert [%{url: "Q", title: "1", posted: _date}] =
               Permalink
               |> join(:left, [l], p in Post, on: l.post_id == p.id)
               |> select([l, p], merge(l, map(p, ^~w(title posted)a)))
               |> TestRepo.all()

      assert [%{url: "Q", title: "1", posted: _date}] =
               Permalink
               |> join(:left, [l], p in Post, on: l.post_id == p.id)
               |> select_merge([_l, p], map(p, ^~w(title posted)a))
               |> TestRepo.all()

      # left join record is not present
      assert [%{url: "Q", title: "Z", posted: nil}] =
               Permalink
               |> join(:left, [l], p in Post, on: l.post_id == p.id and p.public == true)
               |> select([l, p], merge(l, map(p, ^~w(title posted)a)))
               |> TestRepo.all()

      assert [%{url: "Q", title: "Z", posted: nil}] =
               Permalink
               |> join(:left, [l], p in Post, on: l.post_id == p.id and p.public == true)
               |> select_merge([_l, p], map(p, ^~w(title posted)a))
               |> TestRepo.all()
    end

    test "merge with update on self" do
      %Post{} = TestRepo.insert!(%Post{title: "1", counter: 1})

      assert [%Post{title: "1", counter: 2}] =
               Post |> select([p], merge(p, %{p | counter: 2})) |> TestRepo.all()

      assert [%Post{title: "1", counter: 2}] =
               Post |> select([p], p) |> select_merge([p], %{p | counter: 2}) |> TestRepo.all()
    end

    test "merge within subquery" do
      %Post{} = TestRepo.insert!(%Post{title: "1", counter: 1})

      subquery =
        Post
        |> select_merge([p], %{p | counter: 2})
        |> subquery()

      assert [%Post{title: "1", counter: 2}] = TestRepo.all(subquery)
    end
  end

  @tag :not_supported_yet
  test "Aggregations are not supported" do
    assert_raise Ecto.QueryError, fn ->
      assert TestRepo.aggregate(Post, :max, :visits) == 14
    end

    assert_raise Ecto.QueryError, fn ->
      assert TestRepo.aggregate(Post, :min, :visits) == 10
    end

    assert_raise Ecto.QueryError, fn ->
      assert TestRepo.aggregate(Post, :count, :visits) == 4
    end

    assert_raise Ecto.QueryError, fn ->
      assert "50" = to_string(TestRepo.aggregate(Post, :sum, :visits))
    end
  end

  @tag :not_supported_yet
  test "selects on fields should thrown an exception, the adapter does not support it yet" do
    comment = TestRepo.insert!(%Comment{text: "1", lock_version: 1})
    lock_version_query = from(c in Comment, select: c.lock_version, where: [id: ^comment.id])

    rows = [
      [text: "2", lock_version: lock_version_query]
    ]

    assert_raise ArgumentError, fn -> TestRepo.insert_all(Comment, rows, []) end
  end

  @tag :not_supported_yet
  test "replace_all conflicts are not supported yet" do
    source =
      from(p in Post,
        select: %{
          title: fragment("concat(?, ?, ?)", p.title, type(^" suffix ", :string), p.id)
        }
      )

    assert_raise ArgumentError, fn ->
      TestRepo.insert_all(Post, source, conflict_target: [:id], on_conflict: :replace_all)
    end
  end

  @tag :not_supported_yet
  test "source queries not supported yet" do
    source =
      from(p in Post,
        select: %{
          title: fragment("concat(?, ?, ?)", p.title, type(^" suffix ", :string), p.id)
        }
      )

    assert_raise ArgumentError, fn ->
      TestRepo.insert_all(Post, source, returning: [:id, :title])
    end
  end

  describe "Aggregations on simple queries" do
    @describetag :aggregations

    test "aggregate" do
      assert_raise Ecto.NoResultsError, fn ->
        assert TestRepo.aggregate(Post, :max, :visits) == nil
      end

      TestRepo.insert!(%Post{visits: 10})
      TestRepo.insert!(%Post{visits: 12})
      TestRepo.insert!(%Post{visits: 14})
      TestRepo.insert!(%Post{visits: 14})

      # Barebones
      assert TestRepo.aggregate(Post, :max, :visits) == 14
      assert TestRepo.aggregate(Post, :min, :visits) == 10
      assert TestRepo.aggregate(Post, :count, :visits) == 4
      assert "50" = to_string(TestRepo.aggregate(Post, :sum, :visits))

      # With order_by
      query = from(Post, order_by: [asc: :visits])
      assert TestRepo.aggregate(query, :max, :visits) == 14
    end

    test "aggregate with order_by and limit" do
      TestRepo.insert!(%Post{visits: 10})
      TestRepo.insert!(%Post{visits: 12})
      TestRepo.insert!(%Post{visits: 14})
      TestRepo.insert!(%Post{visits: 14})

      # With order_by and limit
      query = from(Post, order_by: [asc: :visits], limit: 2)
      assert TestRepo.aggregate(query, :max, :visits) == 12
    end

    test "aggregate avg" do
      TestRepo.insert!(%Post{visits: 10})
      TestRepo.insert!(%Post{visits: 12})
      TestRepo.insert!(%Post{visits: 14})
      TestRepo.insert!(%Post{visits: 14})

      assert "12.5" <> _ = to_string(TestRepo.aggregate(Post, :avg, :visits))
    end

    test "aggregate with distinct" do
      TestRepo.insert!(%Post{visits: 10})
      TestRepo.insert!(%Post{visits: 12})
      TestRepo.insert!(%Post{visits: 14})
      TestRepo.insert!(%Post{visits: 14})

      query = from(Post, order_by: [asc: :visits], distinct: true)
      assert TestRepo.aggregate(query, :count, :visits) == 3
    end
  end

  describe "placeholders" do
    @describetag :todo

    test "Repo.insert_all fills in placeholders" do
      placeholders = %{foo: 100, bar: "test"}
      bar_ph = {:placeholder, :bar}
      foo_ph = {:placeholder, :foo}

      entries =
        [
          %{intensity: 1.0, title: bar_ph, posted: ~D[2020-12-21], visits: foo_ph},
          %{intensity: 2.0, title: bar_ph, posted: ~D[2000-12-21], visits: foo_ph}
        ]
        |> Enum.map(&Map.put(&1, :uuid, Ecto.UUID.generate()))

      TestRepo.insert_all(Post, entries, placeholders: placeholders)

      query = from(p in Post, select: {p.intensity, p.title, p.visits})
      assert [{1.0, "test", 100}, {2.0, "test", 100}] == TestRepo.all(query)
    end

    test "Repo.insert_all accepts non-atom placeholder keys" do
      placeholders = %{10 => "integer key", {:foo, :bar} => "tuple key"}
      entries = [%{text: {:placeholder, 10}}, %{text: {:placeholder, {:foo, :bar}}}]
      TestRepo.insert_all(Comment, entries, placeholders: placeholders)

      query = from(c in Comment, select: c.text)
      assert ["integer key", "tuple key"] == TestRepo.all(query)
    end

    test "Repo.insert_all fills in placeholders with keyword list entries" do
      TestRepo.insert_all(Barebone, [[num: {:placeholder, :foo}]], placeholders: %{foo: 100})

      query = from(b in Barebone, select: b.num)
      assert [100] == TestRepo.all(query)
    end
  end
end

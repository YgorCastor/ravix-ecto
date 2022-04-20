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
    Custom
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
      post = %Post{title: "insert, update, delete", visits: 1}
      meta = post.__meta__

      assert %Post{} = inserted = TestRepo.insert!(post)
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

    test "should insert autogenerates for custom id type" do
      id_entity = TestRepo.insert!(struct(IdTest))

      assert id_entity.id
      assert TestRepo.get_by(IdTest, id: id_entity.id) == id_entity
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

  @tag :aggregations
  describe "Aggregations on simple queries" do
    @tag :aggregations
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

    @tag :aggregations
    test "aggregate with order_by and limit" do
      TestRepo.insert!(%Post{visits: 10})
      TestRepo.insert!(%Post{visits: 12})
      TestRepo.insert!(%Post{visits: 14})
      TestRepo.insert!(%Post{visits: 14})

      # With order_by and limit
      query = from(Post, order_by: [asc: :visits], limit: 2)
      assert TestRepo.aggregate(query, :max, :visits) == 12
    end

    @tag :aggregations
    test "aggregate avg" do
      TestRepo.insert!(%Post{visits: 10})
      TestRepo.insert!(%Post{visits: 12})
      TestRepo.insert!(%Post{visits: 14})
      TestRepo.insert!(%Post{visits: 14})

      assert "12.5" <> _ = to_string(TestRepo.aggregate(Post, :avg, :visits))
    end

    @tag :aggregations
    test "aggregate with distinct" do
      TestRepo.insert!(%Post{visits: 10})
      TestRepo.insert!(%Post{visits: 12})
      TestRepo.insert!(%Post{visits: 14})
      TestRepo.insert!(%Post{visits: 14})

      query = from(Post, order_by: [asc: :visits], distinct: true)
      assert TestRepo.aggregate(query, :count, :visits) == 3
    end
  end
end

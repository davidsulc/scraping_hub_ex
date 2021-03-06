defmodule ScrapyCloudEx.Endpoints.Storage.ActivityTest do
  use ExUnit.Case, async: true

  @api_key "API_KEY"

  alias ScrapyCloudEx.Endpoints.Storage.Activity
  alias Test.Support.URI

  setup_all do
    opts = [http_adapter: Test.Support.HttpAdapters.Passthrough, decoder: & &1]
    [opts: opts]
  end

  describe "list/4" do
    test "uses the proper API endpoint", %{opts: opts} do
      %{url: url} = Activity.list(@api_key, "1", [], opts)
      assert String.starts_with?(url, "https://storage.scrapinghub.com/activity/1")
    end

    test "contains the api key", %{opts: opts} do
      assert %{api_key: @api_key} = Activity.list(@api_key, "123", [], opts)
    end

    test "makes a GET request", %{opts: opts} do
      assert %{method: :get} = Activity.list(@api_key, "123", [], opts)
    end

    test "rejects invalid params", %{opts: opts} do
      error = Activity.list(@api_key, "123", [foo: :bar], opts)
      assert {:error, {:invalid_param, {:foo, _}}} = error
    end

    test "puts params in the query string", %{opts: opts} do
      params = [
        pagination: [count: 3],
        format: :xml
      ]

      %{url: url} = Activity.list(@api_key, "1", params, opts)

      query_string = url |> URI.get_query()
      assert URI.equivalent?(query_string, params)
    end

    test "accepts json, jl, and xml formats", %{opts: opts} do
      for format <- [:json, :jl, :xml] do
        assert %{} = Activity.list(@api_key, "123", [format: format], opts)
      end
    end

    test "forwards the given options", %{opts: opts} do
      given_opts = [{:foo, :bar} | opts]
      %{opts: opts} = Activity.list(@api_key, "123", [], given_opts)
      merged_opts = Keyword.merge(opts, given_opts)
      assert Keyword.equal?(merged_opts, opts)
    end
  end

  describe "projects/3" do
    test "uses the proper API endpoint", %{opts: opts} do
      %{url: url} = Activity.projects(@api_key, [], opts)
      assert String.starts_with?(url, "https://storage.scrapinghub.com/activity/projects")
    end

    test "contains the api key", %{opts: opts} do
      assert %{api_key: @api_key} = Activity.projects(@api_key, [], opts)
    end

    test "makes a GET request", %{opts: opts} do
      assert %{method: :get} = Activity.projects(@api_key, [], opts)
    end

    test "rejects invalid params", %{opts: opts} do
      error = Activity.projects(@api_key, [foo: :bar], opts)
      assert {:error, {:invalid_param, {:foo, _}}} = error
    end

    test "puts params in the query string", %{opts: opts} do
      params = [
        p: 1,
        p: 2,
        p: 3,
        pcount: 10,
        pagination: [count: 15],
        format: :xml,
        meta: [:_ts, :_project]
      ]

      %{url: url} = Activity.projects(@api_key, params, opts)

      query_string = url |> URI.get_query()
      assert URI.equivalent?(query_string, params)
    end

    test "accepts json, jl, and xml formats", %{opts: opts} do
      for format <- [:json, :jl, :xml] do
        assert %{} = Activity.projects(@api_key, [format: format], opts)
      end
    end

    test "forwards the given options", %{opts: opts} do
      given_opts = [{:foo, :bar} | opts]
      %{opts: opts} = Activity.projects(@api_key, [], given_opts)
      merged_opts = Keyword.merge(opts, given_opts)
      assert Keyword.equal?(merged_opts, opts)
    end
  end
end

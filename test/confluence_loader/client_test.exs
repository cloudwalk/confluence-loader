defmodule ConfluenceLoader.ClientTest do
  use ExUnit.Case, async: true

  alias ConfluenceLoader.Client

  describe "new/4" do
    test "creates a client with required parameters" do
      client = Client.new("https://example.atlassian.net", "user@example.com", "api_token")

      assert %Client{
               base_url: "https://example.atlassian.net",
               username: "user@example.com",
               api_token: "api_token",
               timeout: 30_000
             } = client
    end

    test "creates a client with custom timeout" do
      client =
        Client.new("https://example.atlassian.net", "user@example.com", "api_token",
          timeout: 60_000
        )

      assert client.timeout == 60_000
    end

    test "trims trailing slash from base_url" do
      client = Client.new("https://example.atlassian.net/", "user@example.com", "api_token")

      assert client.base_url == "https://example.atlassian.net"
    end
  end

  describe "HTTP methods with Bypass" do
    setup do
      bypass = Bypass.open()
      client = Client.new("http://localhost:#{bypass.port}", "user@example.com", "api_token")
      {:ok, bypass: bypass, client: client}
    end

    test "get/3 makes successful GET request", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages", fn conn ->
        assert conn.req_headers
               |> Enum.any?(fn {k, v} ->
                 k == "authorization" && String.starts_with?(v, "Basic ")
               end)

        assert conn.req_headers
               |> Enum.any?(fn {k, v} ->
                 k == "accept" && v == "application/json; charset=utf-8"
               end)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"results": [{"id": "123", "title": "Test Page"}]}))
      end)

      assert {:ok, %{"results" => [%{"id" => "123", "title" => "Test Page"}]}} =
               Client.get(client, "/pages")
    end

    test "get/3 handles query parameters", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages", fn conn ->
        assert conn.query_string == "limit=10&space-id=123"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"results": []}))
      end)

      assert {:ok, %{"results" => []}} =
               Client.get(client, "/pages", [{"limit", "10"}, {"space-id", "123"}])
    end

    test "get/3 handles API errors", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, ~s({"message": "Not found"}))
      end)

      assert {:error, {:api_error, 404, %{"message" => "Not found"}}} =
               Client.get(client, "/pages")
    end

    test "get/3 handles network errors", %{bypass: bypass, client: client} do
      # Shut down the bypass to simulate a connection error
      Bypass.down(bypass)

      assert {:error, {:http_error, :econnrefused}} = Client.get(client, "/pages")
    end
  end

  describe "authentication" do
    test "builds correct authorization header" do
      bypass = Bypass.open()
      client = Client.new("http://localhost:#{bypass.port}", "user@example.com", "my-api-token")

      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/test", fn conn ->
        auth_header = conn.req_headers |> Enum.find(fn {k, _} -> k == "authorization" end)
        assert {_, "Basic " <> encoded} = auth_header
        assert Base.decode64!(encoded) == "user@example.com:my-api-token"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"ok": true}))
      end)

      assert {:ok, %{"ok" => true}} = Client.get(client, "/test")
    end
  end
end

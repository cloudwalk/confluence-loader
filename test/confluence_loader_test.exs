defmodule ConfluenceLoaderTest do
  use ExUnit.Case, async: true
  doctest ConfluenceLoader

  alias ConfluenceLoader.{Client, Document}

  setup do
    bypass = Bypass.open()

    client =
      ConfluenceLoader.new_client(
        "http://localhost:#{bypass.port}",
        "user@example.com",
        "api_token"
      )

    {:ok, bypass: bypass, client: client}
  end

  describe "new_client/4" do
    test "creates a new client" do
      client =
        ConfluenceLoader.new_client("https://example.atlassian.net", "user@example.com", "token")

      assert %Client{} = client
      assert client.base_url == "https://example.atlassian.net"
      assert client.username == "user@example.com"
      assert client.api_token == "token"
    end
  end

  describe "load_documents/2" do
    test "loads all pages as documents", %{bypass: bypass, client: client} do
      # First expect the list pages request
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {
                "id": "123",
                "title": "Test Page"
              }
            ]
          }))
      end)

      # Then expect the individual page fetch
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "123",
            "title": "Test Page",
            "body": {"storage": {"value": "<p>Test content</p>"}}
          }))
      end)

      assert {:ok, documents} = ConfluenceLoader.load_documents(client)
      assert [%Document{id: "123", text: "Test content"}] = documents
    end
  end

  describe "load_space_documents/3" do
    test "loads pages from a specific space", %{bypass: bypass, client: client} do
      space_key = "PROJ"
      space_id = "12345"

      # First expect the space lookup
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces", fn conn ->
        assert conn.query_string == "keys=#{space_key}&limit=1"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "#{space_id}", "key": "#{space_key}", "name": "Project Space"}
            ]
          }))
      end)

      # Then expect the pages request
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces/#{space_id}/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {
                "id": "456",
                "title": "Space Page",
                "spaceId": "#{space_id}"
              }
            ]
          }))
      end)

      # Finally expect the individual page fetch
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/456", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "456",
            "title": "Space Page",
            "spaceId": "#{space_id}",
            "body": {"storage": {"value": "<p>Space content</p>"}}
          }))
      end)

      assert {:ok, documents} = ConfluenceLoader.load_space_documents(client, space_key)
      assert [%Document{id: "456", text: "Space content"}] = documents
    end
  end

  describe "get_pages/2" do
    test "gets pages with filtering", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages", fn conn ->
        assert conn.query_string == "limit=5"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"results": [{"id": "1", "title": "Page"}]}))
      end)

      assert {:ok, response} = ConfluenceLoader.get_pages(client, %{limit: 5})
      assert response["results"] == [%{"id" => "1", "title" => "Page"}]
    end
  end

  describe "get_page/3" do
    test "gets a specific page", %{bypass: bypass, client: client} do
      page_id = "789"

      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/#{page_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"id": "#{page_id}", "title": "Specific Page"}))
      end)

      assert {:ok, page} = ConfluenceLoader.get_page(client, page_id)
      assert page["id"] == page_id
      assert page["title"] == "Specific Page"
    end
  end

  describe "get_pages_in_space/3" do
    test "gets pages in a specific space", %{bypass: bypass, client: client} do
      space_key = "TEST"
      space_id = "99999"

      # First expect the space lookup
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces", fn conn ->
        assert conn.query_string == "keys=#{space_key}&limit=1"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "#{space_id}", "key": "#{space_key}", "name": "Test Space"}
            ]
          }))
      end)

      # Then expect the pages request
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces/#{space_id}/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [{"id": "111", "title": "Space Page"}]
          }))
      end)

      assert {:ok, response} = ConfluenceLoader.get_pages_in_space(client, space_key)
      assert [page] = response["results"]
      assert page["title"] == "Space Page"
    end
  end

  describe "get_pages_for_label/3" do
    test "gets pages for a specific label", %{bypass: bypass, client: client} do
      label_id = "label123"

      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/labels/#{label_id}/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [{"id": "222", "title": "Labeled Page"}]
          }))
      end)

      assert {:ok, response} = ConfluenceLoader.get_pages_for_label(client, label_id)
      assert [page] = response["results"]
      assert page["title"] == "Labeled Page"
    end
  end

  describe "load_documents_since/4" do
    test "delegates to Pages.load_documents_since", %{bypass: bypass, client: client} do
      space_key = "TEST"
      space_id = "12345"
      timestamp = "2024-01-01T00:00:00Z"

      # Space lookup
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "#{space_id}", "key": "#{space_key}", "name": "Test Space"}
            ]
          }))
      end)

      # Pages request
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces/#{space_id}/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {
                "id": "999",
                "title": "Recent Page",
                "spaceId": "#{space_id}",
                "version": {"createdAt": "2024-01-15T10:00:00Z"}
              }
            ]
          }))
      end)

      # Individual page fetch
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/999", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "999",
            "title": "Recent Page",
            "spaceId": "#{space_id}",
            "version": {"createdAt": "2024-01-15T10:00:00Z"},
            "body": {"storage": {"value": "<p>Recent content</p>"}}
          }))
      end)

      assert {:ok, documents} = ConfluenceLoader.load_documents_since(client, space_key, timestamp)
      assert length(documents) == 1
      assert hd(documents).id == "999"
    end

    test "delegates error handling", %{client: client} do
      assert {:error, :invalid_timestamp} = ConfluenceLoader.load_documents_since(client, "SPACE", "invalid")
    end
  end

  describe "stream_space_documents/3" do
    test "delegates to Pages.stream_space_documents and returns a Stream", %{client: client} do
      # Test that it returns a Stream/function
      stream = ConfluenceLoader.stream_space_documents(client, "TEST")
      assert is_function(stream)
    end

    test "stream can be enumerated", %{bypass: bypass, client: client} do
      space_key = "STREAM"
      space_id = "88888"

      # Space lookup
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "#{space_id}", "key": "#{space_key}", "name": "Stream Space"}
            ]
          }))
      end)

      # Pages request - return empty to test edge case
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces/#{space_id}/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": []
          }))
      end)

      stream = ConfluenceLoader.stream_space_documents(client, space_key)
      result = Enum.to_list(stream)

      # With no pages, stream should be empty
      assert result == []
    end
  end
end

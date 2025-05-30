defmodule ConfluenceLoader.PagesTest do
  use ExUnit.Case, async: true

  alias ConfluenceLoader.{Client, Pages, Document}

  setup do
    bypass = Bypass.open()
    client = Client.new("http://localhost:#{bypass.port}", "user@example.com", "api_token")
    {:ok, bypass: bypass, client: client}
  end

  describe "get_pages/2" do
    test "fetches pages successfully", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages", fn conn ->
        assert conn.query_string == ""

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "123", "title": "Page 1"},
              {"id": "456", "title": "Page 2"}
            ],
            "_links": {"base": "http://localhost"}
          }))
      end)

      assert {:ok, response} = Pages.get_pages(client)
      assert length(response["results"]) == 2
    end

    test "fetches pages with parameters", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages", fn conn ->
        query_params = URI.decode_query(conn.query_string)
        assert query_params["space-id"] == "123,456"
        assert query_params["limit"] == "10"
        assert query_params["body-format"] == "storage"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"results": []}))
      end)

      params = %{
        space_id: [123, 456],
        limit: 10,
        body_format: "storage"
      }

      assert {:ok, _} = Pages.get_pages(client, params)
    end
  end

  describe "get_page/3" do
    test "fetches a specific page", %{bypass: bypass, client: client} do
      page_id = "12345"

      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/#{page_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "#{page_id}",
            "title": "Test Page",
            "body": {
              "storage": {"value": "<p>Content</p>"}
            }
          }))
      end)

      assert {:ok, page} = Pages.get_page(client, page_id)
      assert page["id"] == page_id
      assert page["title"] == "Test Page"
    end
  end

  describe "get_pages_in_space/3" do
    test "fetches pages in a specific space using space key", %{bypass: bypass, client: client} do
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

      # Then expect the pages request with the space ID
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces/#{space_id}/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "111", "title": "Space Page 1", "spaceId": "#{space_id}"}
            ]
          }))
      end)

      assert {:ok, response} = Pages.get_pages_in_space(client, space_key)
      assert [page] = response["results"]
      assert page["spaceId"] == space_id
    end

    test "fetches pages in a specific space using numeric space ID", %{
      bypass: bypass,
      client: client
    } do
      space_id = 12345

      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces/#{space_id}/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "111", "title": "Space Page 1", "spaceId": "#{space_id}"}
            ]
          }))
      end)

      assert {:ok, response} = Pages.get_pages_in_space(client, space_id)
      assert [page] = response["results"]
      assert page["spaceId"] == "#{space_id}"
    end
  end

  describe "get_pages_for_label/3" do
    test "fetches pages for a specific label", %{bypass: bypass, client: client} do
      label_id = "999"

      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/labels/#{label_id}/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "222", "title": "Labeled Page"}
            ]
          }))
      end)

      assert {:ok, response} = Pages.get_pages_for_label(client, label_id)
      assert [page] = response["results"]
      assert page["title"] == "Labeled Page"
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
                "title": "Test Page",
                "spaceId": "SPACE1",
                "status": "current",
                "createdAt": "2024-01-01T10:00:00Z",
                "authorId": "user123"
              }
            ]
          }))
      end)

      # Then expect the individual page fetch with body content
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/123", fn conn ->
        query_params = URI.decode_query(conn.query_string)
        assert query_params["body-format"] == "storage"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "123",
            "title": "Test Page",
            "spaceId": "SPACE1",
            "status": "current",
            "createdAt": "2024-01-01T10:00:00Z",
            "authorId": "user123",
            "body": {
              "storage": {"value": "<p>This is <strong>test</strong> content</p>"}
            },
            "_links": {
              "webui": "http://example.com/page/123",
              "editui": "http://example.com/page/123/edit"
            }
          }))
      end)

      assert {:ok, documents} = Pages.load_documents(client)
      assert [doc] = documents
      assert %Document{} = doc
      assert doc.id == "123"
      assert doc.text == "This is test content"
      assert doc.metadata.title == "Test Page"
      assert doc.metadata.space_id == "SPACE1"
      assert doc.metadata.web_url == "http://example.com/page/123"
    end

    test "handles pagination when loading documents", %{bypass: bypass, client: client} do
      # Set up a counter to track requests
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, "GET", "/wiki/api/v2/pages", fn conn ->
        count = Agent.get_and_update(agent, fn state -> {state, state + 1} end)
        query_params = URI.decode_query(conn.query_string)

        case count do
          0 ->
            # First page request
            assert query_params["cursor"] == nil

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({
                "results": [
                  {"id": "1", "title": "Page 1"}
                ],
                "_links": {
                  "next": "http://localhost:#{bypass.port}/wiki/api/v2/pages?cursor=abc123"
                }
              }))

          1 ->
            # Second page request
            assert query_params["cursor"] == "abc123"

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({
                "results": [
                  {"id": "2", "title": "Page 2"}
                ]
              }))
        end
      end)

      # Expect individual page fetches
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "1",
            "title": "Page 1",
            "body": {"storage": {"value": "<p>Content 1</p>"}}
          }))
      end)

      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/2", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "2",
            "title": "Page 2",
            "body": {"storage": {"value": "<p>Content 2</p>"}}
          }))
      end)

      assert {:ok, documents} = Pages.load_documents(client)
      assert length(documents) == 2
      assert Enum.map(documents, & &1.id) == ["1", "2"]

      Agent.stop(agent)
    end
  end

  describe "load_space_documents/3" do
    test "loads pages from a specific space as documents", %{bypass: bypass, client: client} do
      space_key = "TEAM"
      space_id = "67890"

      # First expect the space lookup
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces", fn conn ->
        assert conn.query_string == "keys=#{space_key}&limit=1"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "#{space_id}", "key": "#{space_key}", "name": "Team Space"}
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
        query_params = URI.decode_query(conn.query_string)
        assert query_params["body-format"] == "storage"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "456",
            "title": "Space Page",
            "spaceId": "#{space_id}",
            "body": {
              "storage": {"value": "<p>Space content</p>"}
            }
          }))
      end)

      assert {:ok, documents} = Pages.load_space_documents(client, space_key)
      assert [doc] = documents
      assert doc.text == "Space content"
      assert doc.metadata.space_id == space_id
    end

    test "loads documents since a specific timestamp", %{bypass: bypass, client: client} do
      space_key = "PROJ"
      space_id = "12345"
      test_timestamp = "2024-01-01T00:00:00Z"

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
                "id": "123",
                "title": "Old Page",
                "spaceId": "#{space_id}",
                "version": {"createdAt": "2023-12-01T10:00:00Z"}
              },
              {
                "id": "456",
                "title": "New Page",
                "spaceId": "#{space_id}",
                "version": {"createdAt": "2024-01-15T10:00:00Z"}
              }
            ]
          }))
      end)

      # Expect individual page fetches
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "123",
            "title": "Old Page",
            "spaceId": "#{space_id}",
            "version": {"createdAt": "2023-12-01T10:00:00Z"},
            "body": {"storage": {"value": "<p>Old content</p>"}}
          }))
      end)

      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/456", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "456",
            "title": "New Page",
            "spaceId": "#{space_id}",
            "version": {"createdAt": "2024-01-15T10:00:00Z"},
            "body": {"storage": {"value": "<p>New content</p>"}}
          }))
      end)

      assert {:ok, documents} = Pages.load_documents_since(client, space_key, test_timestamp)
      assert length(documents) == 1
      assert hd(documents).id == "456"
      assert hd(documents).metadata.title == "New Page"
    end

    test "load_documents_since with DateTime struct", %{bypass: bypass, client: client} do
      space_key = "TEST"
      space_id = "99999"

      {:ok, test_datetime} = DateTime.new(~D[2024-01-01], ~T[00:00:00], "Etc/UTC")

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
                "title": "Future Page",
                "spaceId": "#{space_id}",
                "version": {"createdAt": "2024-06-01T10:00:00Z"}
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
            "title": "Future Page",
            "spaceId": "#{space_id}",
            "version": {"createdAt": "2024-06-01T10:00:00Z"},
            "body": {"storage": {"value": "<p>Future content</p>"}}
          }))
      end)

      assert {:ok, documents} = Pages.load_documents_since(client, space_key, test_datetime)
      assert length(documents) == 1
      assert hd(documents).id == "999"
    end

    test "load_documents_since with invalid timestamp string", %{client: client} do
      assert {:error, :invalid_timestamp} = Pages.load_documents_since(client, "SPACE", "invalid-date")
    end

    test "load_documents_since with invalid timestamp type", %{client: client} do
      assert {:error, :invalid_timestamp} = Pages.load_documents_since(client, "SPACE", 12345)
    end

    test "load_documents_since filters out pages without version.createdAt", %{bypass: bypass, client: client} do
      space_key = "FILTER"
      space_id = "88888"

      # Space lookup
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "#{space_id}", "key": "#{space_key}", "name": "Filter Space"}
            ]
          }))
      end)

      # Pages request with missing createdAt
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces/#{space_id}/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {
                "id": "111",
                "title": "Page Without Date",
                "spaceId": "#{space_id}",
                "version": {}
              }
            ]
          }))
      end)

      # Individual page fetch
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/111", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "111",
            "title": "Page Without Date",
            "spaceId": "#{space_id}",
            "version": {},
            "body": {"storage": {"value": "<p>No date content</p>"}}
          }))
      end)

      assert {:ok, documents} = Pages.load_documents_since(client, space_key, "2024-01-01T00:00:00Z")
      assert length(documents) == 0
    end

    test "load_documents_since filters out pages with invalid createdAt format", %{bypass: bypass, client: client} do
      space_key = "INVALID"
      space_id = "77777"

      # Space lookup
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "#{space_id}", "key": "#{space_key}", "name": "Invalid Space"}
            ]
          }))
      end)

      # Pages request with invalid createdAt
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces/#{space_id}/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {
                "id": "222",
                "title": "Page Invalid Date",
                "spaceId": "#{space_id}",
                "version": {"createdAt": "not-a-date"}
              }
            ]
          }))
      end)

      # Individual page fetch
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/222", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "222",
            "title": "Page Invalid Date",
            "spaceId": "#{space_id}",
            "version": {"createdAt": "not-a-date"},
            "body": {"storage": {"value": "<p>Invalid date content</p>"}}
          }))
      end)

      assert {:ok, documents} = Pages.load_documents_since(client, space_key, "2024-01-01T00:00:00Z")
      assert length(documents) == 0
    end

    test "load_documents_since handles space lookup error", %{bypass: bypass, client: client} do
      space_key = "NOTFOUND"

      # Space lookup returns empty
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"results": []}))
      end)

      assert {:error, {:not_found, "Space with key 'NOTFOUND' not found"}} =
        Pages.load_documents_since(client, space_key, "2024-01-01T00:00:00Z")
    end

    test "load_documents_since with numeric space ID", %{bypass: bypass, client: client} do
      space_id = 12345

      # Pages request directly with numeric ID
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces/#{space_id}/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {
                "id": "333",
                "title": "Numeric Space Page",
                "spaceId": "#{space_id}",
                "version": {"createdAt": "2024-01-15T10:00:00Z"}
              }
            ]
          }))
      end)

      # Individual page fetch
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/333", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "333",
            "title": "Numeric Space Page",
            "spaceId": "#{space_id}",
            "version": {"createdAt": "2024-01-15T10:00:00Z"},
            "body": {"storage": {"value": "<p>Numeric space content</p>"}}
          }))
      end)

      assert {:ok, documents} = Pages.load_documents_since(client, space_id, "2024-01-01T00:00:00Z")
      assert length(documents) == 1
      assert hd(documents).id == "333"
    end
  end

  describe "HTML stripping" do
    test "strips HTML tags correctly", %{bypass: bypass, client: client} do
      html_content =
        """
        <p>Hello &amp; welcome!</p><script>alert('test')</script><style>body{color:red;}</style><div>Multiple<br/>lines</div>
        """
        |> String.trim()

      # First expect the list pages request
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "results" => [
              %{
                "id" => "1",
                "title" => "HTML Test"
              }
            ]
          })
        )
      end)

      # Then expect the individual page fetch
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "id" => "1",
            "title" => "HTML Test",
            "body" => %{
              "storage" => %{"value" => html_content}
            }
          })
        )
      end)

      assert {:ok, [doc]} = Pages.load_documents(client)
      assert doc.text == "Hello & welcome! Multiple lines"
    end

    test "handles different body formats", %{bypass: bypass, client: client} do
      # First expect the list pages request
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "1", "title": "View Format"},
              {"id": "2", "title": "Atlas Format"},
              {"id": "3", "title": "No Body"}
            ]
          }))
      end)

      # Then expect individual page fetches
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "1",
            "title": "View Format",
            "body": {
              "view": {"value": "<p>View content</p>"}
            }
          }))
      end)

      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/2", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "2",
            "title": "Atlas Format",
            "body": {
              "atlas_doc_format": {"value": "Atlas content"}
            }
          }))
      end)

      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/3", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "3",
            "title": "No Body",
            "body": {}
          }))
      end)

      assert {:ok, documents} = Pages.load_documents(client)
      assert length(documents) == 3

      [doc1, doc2, doc3] = documents
      assert doc1.text == "View content"
      assert doc2.text == "Atlas content"
      assert doc3.text == ""
    end
  end

  describe "page_to_document/1" do
    test "converts a page response to a Document" do
      page = %{
        "id" => "123",
        "title" => "Test Page",
        "spaceId" => "SPACE1",
        "parentId" => "456",
        "status" => "current",
        "createdAt" => "2024-01-01T10:00:00Z",
        "authorId" => "user123",
        "version" => %{"number" => 5},
        "body" => %{
          "storage" => %{"value" => "<p>Hello <strong>world</strong>!</p>"}
        },
        "_links" => %{
          "webui" => "http://example.com/page/123",
          "editui" => "http://example.com/page/123/edit"
        }
      }

      doc = Pages.page_to_document(page)

      assert %Document{} = doc
      assert doc.id == "123"
      assert doc.text == "Hello world !"
      assert doc.metadata.title == "Test Page"
      assert doc.metadata.space_id == "SPACE1"
      assert doc.metadata.parent_id == "456"
      assert doc.metadata.status == "current"
      assert doc.metadata.created_at == "2024-01-01T10:00:00Z"
      assert doc.metadata.author_id == "user123"
      assert doc.metadata.version == %{"number" => 5}
      assert doc.metadata.web_url == "http://example.com/page/123"
      assert doc.metadata.edit_url == "http://example.com/page/123/edit"
    end

    test "handles pages with Portuguese HTML entities" do
      page = %{
        "id" => "123",
        "title" => "Portuguese Page",
        "body" => %{
          "storage" => %{
            "value" => "<p>Ol&aacute; &ccedil;omo est&atilde;s? &Eacute; &oacute;timo!</p>"
          }
        }
      }

      doc = Pages.page_to_document(page)
      assert doc.text == "Olá çomo estãs? É ótimo!"
    end

    test "handles pages without body content" do
      page = %{
        "id" => "123",
        "title" => "No Body",
        "body" => nil
      }

      doc = Pages.page_to_document(page)
      assert doc.text == ""
    end

    test "handles numeric HTML entities" do
      page = %{
        "id" => "123",
        "title" => "Numeric Entities",
        "body" => %{
          "storage" => %{
            "value" => "<p>Hello &#8211; world &#8364; &#65; &#invalid;</p>"
          }
        }
      }

      doc = Pages.page_to_document(page)
      assert doc.text == "Hello – world € A &#invalid;"
    end

    test "handles edge case HTML content" do
      page = %{
        "id" => "123",
        "title" => "Edge Cases",
        "body" => %{
          "storage" => %{
            "value" => "<script>alert('test')</script><style>body{color:red}</style><p>Clean text</p>"
          }
        }
      }

      doc = Pages.page_to_document(page)
      assert doc.text == "Clean text"
    end

    test "handles empty page metadata gracefully" do
      page = %{
        "id" => "123"
        # Missing most fields
      }

      doc = Pages.page_to_document(page)
      assert doc.id == "123"
      assert doc.text == ""
      assert doc.metadata.title == nil
      assert doc.metadata.space_id == nil
    end
  end

  describe "error handling" do
    test "handles space not found error", %{bypass: bypass, client: client} do
      space_key = "NOTFOUND"

      # Expect the space lookup to return empty results
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/spaces", fn conn ->
        assert conn.query_string == "keys=#{space_key}&limit=1"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": []
          }))
      end)

      assert {:error, {:not_found, "Space with key 'NOTFOUND' not found"}} =
               Pages.get_pages_in_space(client, space_key)
    end

    test "handles API error in get_pages", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, ~s({"error": "Internal Server Error"}))
      end)

      assert {:error, {:api_error, 500, _}} = Pages.get_pages(client)
    end

    test "handles pagination with limit", %{bypass: bypass, client: client} do
      # First page
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages", fn conn ->
        query_params = URI.decode_query(conn.query_string)
        assert query_params["limit"] == "2"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "1", "title": "Page 1"},
              {"id": "2", "title": "Page 2"}
            ],
            "_links": {
              "next": "http://localhost:#{bypass.port}/wiki/api/v2/pages?cursor=abc"
            }
          }))
      end)

      # Expect individual page fetches (only 2 because of limit)
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "1",
            "title": "Page 1",
            "body": {"storage": {"value": "Content 1"}}
          }))
      end)

      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/2", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "id": "2",
            "title": "Page 2",
            "body": {"storage": {"value": "Content 2"}}
          }))
      end)

      assert {:ok, documents} = Pages.load_documents(client, %{limit: 2})
      assert length(documents) == 2
    end

    test "handles failed individual page fetch gracefully", %{bypass: bypass, client: client} do
      # First expect the list pages request
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
            "results": [
              {"id": "123", "title": "Test Page"}
            ]
          }))
      end)

      # Then expect the individual page fetch to fail
      Bypass.expect_once(bypass, "GET", "/wiki/api/v2/pages/123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, ~s({"error": "Not found"}))
      end)

      # Should still return the document but without body content
      assert {:ok, [doc]} = Pages.load_documents(client)
      # Falls back to empty text
      assert doc.text == ""
    end
  end
end

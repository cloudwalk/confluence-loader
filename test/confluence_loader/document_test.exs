defmodule ConfluenceLoader.DocumentTest do
  use ExUnit.Case, async: true

  alias ConfluenceLoader.Document

  describe "new/3" do
    test "creates a document with required fields" do
      doc = Document.new("123", "This is the content")

      assert %Document{
               id: "123",
               text: "This is the content",
               metadata: %{}
             } = doc
    end

    test "creates a document with metadata" do
      metadata = %{title: "My Page", space_id: "SPACE1"}
      doc = Document.new("123", "This is the content", metadata)

      assert doc.id == "123"
      assert doc.text == "This is the content"
      assert doc.metadata == metadata
    end
  end

  describe "to_map/1" do
    test "converts document to map" do
      doc = Document.new("123", "Content", %{title: "Page"})
      map = Document.to_map(doc)

      assert map == %{
               id: "123",
               text: "Content",
               metadata: %{title: "Page"}
             }
    end

    test "converts document without metadata to map" do
      doc = Document.new("456", "Some text")
      map = Document.to_map(doc)

      assert map == %{
               id: "456",
               text: "Some text",
               metadata: %{}
             }
    end
  end

  describe "from_map/1" do
    test "creates document from map with string keys" do
      map = %{
        "id" => "123",
        "text" => "Content",
        "metadata" => %{"title" => "Page"}
      }

      assert {:ok, doc} = Document.from_map(map)
      assert doc.id == "123"
      assert doc.text == "Content"
      assert doc.metadata == %{"title" => "Page"}
    end

    test "creates document from map with atom keys" do
      map = %{
        id: "456",
        text: "Other content",
        metadata: %{space_id: "SPACE1"}
      }

      assert {:ok, doc} = Document.from_map(map)
      assert doc.id == "456"
      assert doc.text == "Other content"
      assert doc.metadata == %{space_id: "SPACE1"}
    end

    test "creates document from map without metadata" do
      map = %{"id" => "789", "text" => "No metadata"}

      assert {:ok, doc} = Document.from_map(map)
      assert doc.id == "789"
      assert doc.text == "No metadata"
      assert doc.metadata == %{}
    end

    test "returns error for invalid map - missing id" do
      map = %{"text" => "Content"}

      assert {:error, "Invalid document format: missing required fields 'id' and 'text'"} =
               Document.from_map(map)
    end

    test "returns error for invalid map - missing text" do
      map = %{"id" => "123"}

      assert {:error, "Invalid document format: missing required fields 'id' and 'text'"} =
               Document.from_map(map)
    end

    test "returns error for empty map" do
      assert {:error, "Invalid document format: missing required fields 'id' and 'text'"} =
               Document.from_map(%{})
    end
  end

  describe "format_for_llm/1" do
    test "formats document for LLM consumption" do
      doc =
        Document.new("123", "This is the main content of the page.", %{
          title: "My Page Title",
          space_id: "SPACE1",
          author_id: "user123",
          created_at: "2024-01-01T10:00:00Z"
        })

      formatted = Document.format_for_llm(doc)

      assert formatted =~ "Document ID: 123"
      assert formatted =~ "Metadata:"
      assert formatted =~ "title: My Page Title"
      assert formatted =~ "space_id: SPACE1"
      assert formatted =~ "author_id: user123"
      assert formatted =~ "created_at: 2024-01-01T10:00:00Z"
      assert formatted =~ "Content:\nThis is the main content of the page."
    end

    test "formats document without metadata" do
      doc = Document.new("456", "Simple content")
      formatted = Document.format_for_llm(doc)

      assert formatted =~ "Document ID: 456"
      assert formatted =~ "Metadata:\n\n"
      assert formatted =~ "Content:\nSimple content"
    end

    test "formats document with empty text" do
      doc = Document.new("789", "", %{title: "Empty Page"})
      formatted = Document.format_for_llm(doc)

      assert formatted =~ "Document ID: 789"
      assert formatted =~ "title: Empty Page"
      assert formatted =~ "Content:\n\n"
    end

    test "handles complex metadata types" do
      doc =
        Document.new("123", "Test content", %{
          "title" => "Test",
          "tags" => ["tag1", "tag2", "tag3"],
          "version" => %{"number" => 5, "when" => "2024-01-01"},
          "nested" => %{"key" => "value", "deep" => %{"level" => 2}},
          "nil_value" => nil,
          "empty_list" => []
        })

      formatted = Document.format_for_llm(doc)

      assert formatted =~ "title: Test"
      assert formatted =~ "tags: [\"tag1\", \"tag2\", \"tag3\"]"
      assert formatted =~ "version: %{\"number\" => 5, \"when\" => \"2024-01-01\"}"
      assert formatted =~ "nested: %{\"deep\" => %{\"level\" => 2}, \"key\" => \"value\"}"
      assert formatted =~ "nil_value: "
      assert formatted =~ "empty_list: []"
    end

    test "handles boolean and atom values" do
      doc =
        Document.new("123", "Test", %{
          "active" => true,
          "archived" => false,
          "status" => :published
        })

      formatted = Document.format_for_llm(doc)

      assert formatted =~ "active: true"
      assert formatted =~ "archived: false"
      assert formatted =~ "status: published"
    end
  end
end

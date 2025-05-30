# Test script to debug body content fetching

# Get configuration from environment variables
confluence_url = System.get_env("CONFLUENCE_URL") || raise "Please set CONFLUENCE_URL environment variable"
username = System.get_env("CONFLUENCE_USERNAME") || raise "Please set CONFLUENCE_USERNAME environment variable"
api_token = System.get_env("CONFLUENCE_API_TOKEN") || raise "Please set CONFLUENCE_API_TOKEN environment variable"

# Create a client with the correct API base path
client = ConfluenceLoader.new_client(
  confluence_url,
  username,
  api_token,
  api_base_path: "/api/v2"
)

IO.puts("Testing body content fetching...")
IO.puts("")

# Test 1: Get a single page with body content
IO.puts("=== Test 1: Get pages with body content ===")
case ConfluenceLoader.get_pages(client, %{limit: 1, body_format: "storage"}) do
  {:ok, response} ->
    if response["results"] && length(response["results"]) > 0 do
      page = hd(response["results"])
      IO.puts("Page ID: #{page["id"]}")
      IO.puts("Page title: #{page["title"]}")
      IO.puts("Has body? #{page["body"] != nil}")

      if page["body"] do
        IO.inspect(page["body"], label: "Body structure")
      end
    end

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("\n")

# Test 2: Get a specific page by ID with body
IO.puts("=== Test 2: Get specific page with body ===")
IO.puts("Enter a page ID to test (or press Enter to skip): ")
page_id = IO.gets("") |> String.trim()

if page_id != "" do
  case ConfluenceLoader.get_page(client, page_id, %{body_format: "storage"}) do
    {:ok, page} ->
      IO.puts("Page title: #{page["title"]}")
      IO.puts("Has body? #{page["body"] != nil}")

      if page["body"] do
        IO.inspect(page["body"], label: "Body structure")

        # Try to extract text
        case page["body"] do
          %{"storage" => %{"value" => html}} ->
            IO.puts("\nRaw HTML content (first 500 chars):")
            IO.puts(String.slice(html, 0, 500))

          _ ->
            IO.puts("Body is in unexpected format")
        end
      end

    {:error, reason} ->
      IO.puts("Error: #{inspect(reason)}")
  end
else
  IO.puts("Skipped specific page test")
end

IO.puts("\n")

# Test 3: Load documents and check content
IO.puts("=== Test 3: Load documents with body ===")
case ConfluenceLoader.load_documents(client, %{limit: 1}) do
  {:ok, [doc | _]} ->
    IO.puts("Document ID: #{doc.id}")
    IO.puts("Title: #{doc.metadata.title}")
    IO.puts("Text length: #{String.length(doc.text)} characters")
    IO.puts("Text preview: #{String.slice(doc.text, 0, 200)}")

  {:ok, []} ->
    IO.puts("No documents found")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

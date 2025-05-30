# Debug Usage Example for ConfluenceLoader
# This version has more logging to help diagnose issues

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

IO.puts("Connected to Confluence at: #{confluence_url}")
IO.puts("")

# Test 1: Get a single page directly
IO.puts("=== Test 1: Getting pages with limit 1 ===")
case ConfluenceLoader.get_pages(client, %{limit: 1}) do
  {:ok, response} ->
    IO.puts("✓ Success! Got response:")
    IO.puts("  Total results: #{length(response["results"] || [])}")
    if response["results"] && length(response["results"]) > 0 do
      page = hd(response["results"])
      IO.puts("  First page ID: #{page["id"]}")
      IO.puts("  First page title: #{page["title"]}")
    end
    IO.puts("  Has more pages: #{response["_links"]["next"] != nil}")

  {:error, reason} ->
    IO.puts("✗ Error: #{inspect(reason)}")
end

IO.puts("\n")

# Test 2: Load documents with very small limit
IO.puts("=== Test 2: Loading documents with limit 2 ===")
IO.puts("Starting at: #{DateTime.utc_now()}")

case ConfluenceLoader.load_documents(client, %{limit: 2}) do
  {:ok, documents} ->
    IO.puts("Finished at: #{DateTime.utc_now()}")
    IO.puts("✓ Success! Found #{length(documents)} documents")

    Enum.each(documents, fn doc ->
      IO.puts("\n  Document ID: #{doc.id}")
      IO.puts("  Title: #{doc.metadata.title}")
      IO.puts("  Space ID: #{doc.metadata.space_id}")
      IO.puts("  Text length: #{String.length(doc.text)} characters")
    end)

  {:error, reason} ->
    IO.puts("✗ Error: #{inspect(reason)}")
end

IO.puts("\n")

# Test 3: Test space lookup
IO.puts("=== Test 3: Testing space lookup ===")
IO.puts("Enter a space key (e.g., JKB) or press Enter to skip: ")
space_key = IO.gets("") |> String.trim()

if space_key != "" do
  IO.puts("Looking up space '#{space_key}'...")

  # First, let's see if we can get the space info
  case ConfluenceLoader.Client.get(client, "/spaces", [{"keys", space_key}, {"limit", "1"}]) do
    {:ok, %{"results" => [space | _]}} ->
      IO.puts("✓ Found space:")
      IO.puts("  Space ID: #{space["id"]}")
      IO.puts("  Space name: #{space["name"]}")
      IO.puts("  Space key: #{space["key"]}")

      # Now try to get just 1 page from this space
      IO.puts("\nGetting 1 page from this space...")
      case ConfluenceLoader.get_pages_in_space(client, space_key, %{limit: 1}) do
        {:ok, response} ->
          IO.puts("✓ Got #{length(response["results"] || [])} pages")

        {:error, reason} ->
          IO.puts("✗ Error getting pages: #{inspect(reason)}")
      end

    {:ok, %{"results" => []}} ->
      IO.puts("✗ Space not found")

    {:error, reason} ->
      IO.puts("✗ Error looking up space: #{inspect(reason)}")
  end
else
  IO.puts("Skipping space test...")
end

IO.puts("\n")
IO.puts("Debug completed!")

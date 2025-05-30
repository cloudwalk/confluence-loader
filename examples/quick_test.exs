# Quick test example for ConfluenceLoader

# Get configuration from environment variables
confluence_url = System.get_env("CONFLUENCE_URL") || raise "Please set CONFLUENCE_URL environment variable"
username = System.get_env("CONFLUENCE_USERNAME") || raise "Please set CONFLUENCE_USERNAME environment variable"
api_token = System.get_env("CONFLUENCE_API_TOKEN") || raise "Please set CONFLUENCE_API_TOKEN environment variable"

# Create a client with the correct API base path
client = ConfluenceLoader.new_client(
  confluence_url,
  username,
  api_token,
  api_base_path: "/api/v2"  # Your Confluence uses /api/v2
)

IO.puts("Connected to Confluence at: #{confluence_url}")
IO.puts("")

# Test 1: Load exactly 2 documents
IO.puts("Loading 2 documents...")
case ConfluenceLoader.load_documents(client, %{limit: 2}) do
  {:ok, documents} ->
    IO.puts("✓ Successfully loaded #{length(documents)} documents")

    Enum.each(documents, fn doc ->
      IO.puts("\n  - #{doc.metadata.title}")
      IO.puts("    ID: #{doc.id}")
      IO.puts("    Space: #{doc.metadata.space_id}")
    end)

  {:error, reason} ->
    IO.puts("✗ Error: #{inspect(reason)}")
end

IO.puts("\n")

# Test 2: Load 1 page from a specific space
IO.puts("Enter a space key (e.g., JKB) to test: ")
space_key = IO.gets("") |> String.trim()

if space_key != "" do
  IO.puts("Loading 1 document from space '#{space_key}'...")

  case ConfluenceLoader.load_space_documents(client, space_key, %{limit: 1}) do
    {:ok, documents} ->
      IO.puts("✓ Successfully loaded #{length(documents)} document(s)")

      Enum.each(documents, fn doc ->
        IO.puts("\n  - #{doc.metadata.title}")
        IO.puts("    Text preview: #{String.slice(doc.text, 0, 100)}...")
      end)

    {:error, {:not_found, message}} ->
      IO.puts("✗ #{message}")

    {:error, reason} ->
      IO.puts("✗ Error: #{inspect(reason)}")
  end
else
  IO.puts("Skipped space test")
end

IO.puts("\nDone!")

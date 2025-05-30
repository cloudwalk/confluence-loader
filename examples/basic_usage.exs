# Basic Usage Example for ConfluenceLoader
#
# This example demonstrates how to use the ConfluenceLoader library
# to fetch and process Confluence pages.
#
# Before running this example, make sure to set the following environment variables:
# - CONFLUENCE_URL: Your Confluence instance URL (e.g., https://your-domain.atlassian.net)
# - CONFLUENCE_USERNAME: Your Atlassian username (email)
# - CONFLUENCE_API_TOKEN: Your Atlassian API token

# Get configuration from environment variables
confluence_url = System.get_env("CONFLUENCE_URL") || raise "Please set CONFLUENCE_URL environment variable"
username = System.get_env("CONFLUENCE_USERNAME") || raise "Please set CONFLUENCE_USERNAME environment variable"
api_token = System.get_env("CONFLUENCE_API_TOKEN") || raise "Please set CONFLUENCE_API_TOKEN environment variable"

# Create a client with the correct API base path for your Confluence instance
client = ConfluenceLoader.new_client(
  confluence_url,
  username,
  api_token,
  api_base_path: "/api/v2"  # Your Confluence uses /api/v2 instead of /wiki/api/v2
)

IO.puts("Connected to Confluence at: #{confluence_url}")
IO.puts("")

# Example 1: Load all pages as documents
IO.puts("=== Example 1: Loading all pages as documents ===")
case ConfluenceLoader.load_documents(client, %{limit: 5}) do
  {:ok, documents} ->
    IO.puts("Found #{length(documents)} pages")

    Enum.each(documents, fn doc ->
      IO.puts("\nDocument ID: #{doc.id}")
      IO.puts("Title: #{doc.metadata.title}")
      IO.puts("Space ID: #{doc.metadata.space_id}")
      IO.puts("Text preview: #{String.slice(doc.text, 0, 100)}...")
    end)

  {:error, reason} ->
    IO.puts("Error loading documents: #{inspect(reason)}")
end

IO.puts("\n")

# Example 2: Load pages from a specific space
IO.puts("=== Example 2: Loading pages from a specific space ===")
IO.puts("Enter a space key (e.g., PROJ, TEAM) or press Enter to skip: ")
space_key = IO.gets("") |> String.trim()

if space_key != "" do
  case ConfluenceLoader.load_space_documents(client, space_key, %{limit: 3}) do
    {:ok, documents} ->
      IO.puts("Found #{length(documents)} pages in space #{space_key}")

      Enum.each(documents, fn doc ->
        IO.puts("- #{doc.metadata.title}")
      end)

    {:error, reason} ->
      IO.puts("Error loading space documents: #{inspect(reason)}")
  end
else
  IO.puts("Skipping space example...")
end

IO.puts("\n")

# Example 3: Format document for LLM
IO.puts("=== Example 3: Format document for LLM ===")
case ConfluenceLoader.load_documents(client, %{limit: 1}) do
  {:ok, [doc | _]} ->
    formatted = ConfluenceLoader.Document.format_for_llm(doc)
    IO.puts("Formatted document:")
    IO.puts(formatted)

  {:ok, []} ->
    IO.puts("No documents found")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("\n")
IO.puts("Example completed!")

# Example 4: Format multiple space pages for LLM
IO.puts("=== Example 4: Format multiple space pages for LLM ===")
IO.puts("Enter a space key (e.g., PROJ, TEAM) or press Enter to skip: ")
space_key = IO.gets("") |> String.trim()

if space_key != "" do
  case ConfluenceLoader.load_space_documents(client, space_key, %{limit: 3}) do
    {:ok, documents} ->
      IO.puts("Found #{length(documents)} pages in space #{space_key}")
      IO.puts("\nFormatted documents for LLM:")

      Enum.each(documents, fn doc ->
        formatted = ConfluenceLoader.Document.format_for_llm(doc)
        IO.puts("\n--- Document ---")
        IO.puts(formatted)
      end)

    {:error, reason} ->
      IO.puts("Error loading space documents: #{inspect(reason)}")
  end
else
  IO.puts("Skipping space pages example...")
end

IO.puts("\n")

# Example 5: Get specific page by ID and format for LLM
IO.puts("=== Example 5: Get specific page by ID and format for LLM ===")
IO.puts("Enter a page ID or press Enter to skip: ")
page_id = IO.gets("") |> String.trim()

if page_id != "" do
  # Request the page with body content
  case ConfluenceLoader.get_page(client, page_id, %{body_format: "storage"}) do
    {:ok, page} ->
      IO.puts("\n✅ Successfully fetched page: #{page["title"]}")

      doc = ConfluenceLoader.Pages.page_to_document(page)
      IO.puts("Document: #{inspect(doc)}")
      IO.puts("Document ID: #{doc.id}")
      IO.puts("Content preview: #{String.slice(doc.text, 0, 200)}...")
      formatted = ConfluenceLoader.Document.format_for_llm(doc)
      IO.puts("\nFormatted document:")
      IO.puts(formatted)

    {:error, reason} ->
      IO.puts("Error loading page: #{inspect(reason)}")
  end
else
  IO.puts("Skipping specific page example...")
end

IO.puts("\n")

# Example 6: Load documents since a specific timestamp
IO.puts("=== Example 6: Load documents since a specific timestamp ===")
IO.puts("Enter a space key (e.g., PROJ, TEAM) or press Enter to skip: ")
space_key = IO.gets("") |> String.trim()

if space_key != "" do
  # Example with a timestamp from 30 days ago
  thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)

  IO.puts("Loading documents from space '#{space_key}' created since #{DateTime.to_date(thirty_days_ago)}...")

  case ConfluenceLoader.load_documents_since(client, space_key, thirty_days_ago, %{limit: 15}) do
    {:ok, documents} ->
      IO.puts("✅ Found #{length(documents)} documents created in the last 30 days")

      if length(documents) > 0 do
        IO.puts("\nRecent documents:")
        Enum.each(documents, fn doc ->
          created_date = case get_in(doc.metadata, [:version, "createdAt"]) do
            nil -> "Unknown"
            date_str ->
              case DateTime.from_iso8601(date_str) do
                {:ok, dt, _} -> DateTime.to_date(dt) |> Date.to_string()
                _ -> date_str
              end
          end
          IO.puts("  - #{doc.metadata.title} (created: #{created_date})")
        end)
      else
        IO.puts("No documents found in the specified timeframe")
      end

      # Example with ISO string timestamp
      IO.puts("\n--- Alternative: Using ISO string timestamp ---")
      case ConfluenceLoader.load_documents_since(client, space_key, "2024-01-01T00:00:00Z", %{limit: 5}) do
        {:ok, documents} ->
          IO.puts("Found #{length(documents)} documents created since 2024-01-01")
        {:error, reason} ->
          IO.puts("Error with ISO timestamp: #{inspect(reason)}")
      end

    {:error, reason} ->
      IO.puts("✗ Error loading recent documents: #{inspect(reason)}")
  end
else
  IO.puts("Skipping timestamp filtering example...")
end

IO.puts("\n")

# Example 8: Stream processing documents in batches of 4 using the native streaming function
IO.puts("=== Example 7: Stream processing with native streaming function ===")
IO.puts("Enter a space key (e.g., PROJ, TEAM) or press Enter to skip: ")
space_key = IO.gets("") |> String.trim()

if space_key != "" do
  IO.puts("✅ Streaming documents from space '#{space_key}' in batches of 4...")

  try do
    client
    |> ConfluenceLoader.stream_space_documents(space_key, %{})
    |> Enum.with_index(1)
    |> Enum.each(fn {batch, batch_number} ->
      IO.puts("\n--- Batch #{batch_number} (#{length(batch)} documents) ---")
      Enum.each(batch, fn doc ->
        IO.puts("  - #{doc.metadata.title} (#{String.length(doc.text)} chars)")
      end)
    end)

    IO.puts("\n✅ Streaming completed successfully!")

    # Example with async processing using Task.async_stream
    IO.puts("\n--- Async streaming with Task.async_stream ---")
    results =
      client
      |> ConfluenceLoader.stream_space_documents(space_key, %{})
      |> Task.async_stream(fn batch ->
        # Process each batch concurrently
        batch_size = length(batch)
        total_chars = batch |> Enum.map(fn doc -> String.length(doc.text) end) |> Enum.sum()
        {batch_size, total_chars}
      end, max_concurrency: 2, timeout: 30_000)
      |> Enum.with_index(1)
      |> Enum.map(fn {{:ok, {batch_size, total_chars}}, index} ->
        IO.puts("Async batch #{index}: #{batch_size} docs, #{total_chars} total characters")
        {batch_size, total_chars}
      end)

    total_docs = results |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    total_chars = results |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    IO.puts("Total processed: #{total_docs} documents, #{total_chars} characters")

  rescue
    error ->
      IO.puts("✗ Error during streaming: #{inspect(error)}")
  end
else
  IO.puts("Skipping streaming example...")
end

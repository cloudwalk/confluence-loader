# ConfluenceLoader

An Elixir library for fetching and reading Confluence pages, inspired by the Python llama-index-readers-confluence library.

## Features

- Fetch pages from Confluence Cloud and Server instances
- Support for both REST API v1 and v2
- Convert Confluence pages to a document format suitable for LLMs
- Pagination support for large result sets
- Flexible authentication (API tokens for Cloud, username/password for Server)

## Installation

Add `confluence_loader` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:confluence_loader, "~> 0.1.0"}
  ]
end
```

## Configuration

You'll need:
- Your Confluence instance URL (e.g., `https://your-domain.atlassian.net`)
- Authentication credentials:
  - For Confluence Cloud: Email address and API token
  - For Confluence Server: Username and password

## Usage

### Creating a Client

```elixir
# For Confluence Cloud (default)
client = ConfluenceLoader.new_client(
  "https://your-domain.atlassian.net",
  "your-email@example.com",
  "your-api-token"
)

# For Confluence Server with custom API path
client = ConfluenceLoader.new_client(
  "https://confluence.company.com",
  "username",
  "password",
  api_base_path: "/rest/api"  # v1 API path
)
```

### Loading Documents

```elixir
# Load all pages as documents
{:ok, documents} = ConfluenceLoader.load_documents(client)

# Load pages from a specific space
{:ok, documents} = ConfluenceLoader.load_space_documents(client, "PROJ")

# Load with specific parameters
{:ok, documents} = ConfluenceLoader.load_documents(client, %{
  space_id: ["123", "456"],  # Multiple space IDs
  limit: 50,                 # Number of pages per request
  status: ["current"],       # Page status (default: ["current"])
  body_format: "storage"     # Format of the content body
})

# Load documents created since a specific timestamp
{:ok, since_date} = DateTime.new(~D[2024-01-01], ~T[00:00:00], "Etc/UTC")
{:ok, recent_docs} = ConfluenceLoader.load_documents_since(client, "PROJ", since_date)

# Or using an ISO timestamp string
{:ok, recent_docs} = ConfluenceLoader.load_documents_since(client, "PROJ", "2024-01-01T00:00:00Z")
```

### Document Structure

Each document contains:
- `id`: The page ID
- `text`: The page content (HTML stripped)
- `metadata`: Additional information including:
  - `title`: Page title
  - `space_id`: Space ID
  - `space_key`: Space key
  - `status`: Page status
  - `created_at`: Creation timestamp
  - `updated_at`: Last update timestamp
  - `url`: Web URL of the page
  - `parent_id`: Parent page ID (if applicable)

### Working with Documents

```elixir
# Load documents
{:ok, documents} = ConfluenceLoader.load_documents(client)

# Access document properties
Enum.each(documents, fn doc ->
  IO.puts("Title: #{doc.metadata.title}")
  IO.puts("Content: #{String.slice(doc.text, 0, 100)}...")
  
  # Format for LLM consumption
  formatted = ConfluenceLoader.Document.format_for_llm(doc)
  IO.puts(formatted)
end)
```

### Timestamp-Based Filtering

Load documents from a specific space that were created at or after a given timestamp. This is useful for incremental updates or processing only recent content changes:

```elixir
# Using DateTime struct
{:ok, since_date} = DateTime.new(~D[2024-01-01], ~T[00:00:00], "Etc/UTC")
{:ok, recent_docs} = ConfluenceLoader.load_documents_since(client, "PROJ", since_date)

# Using ISO 8601 timestamp string
{:ok, recent_docs} = ConfluenceLoader.load_documents_since(client, "PROJ", "2024-01-01T00:00:00Z")

# With additional parameters
{:ok, recent_docs} = ConfluenceLoader.load_documents_since(client, "PROJ", since_date, %{limit: 50})

# Load documents from the last 30 days
thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)
{:ok, recent_docs} = ConfluenceLoader.load_documents_since(client, "SPACE_KEY", thirty_days_ago)
```

### Low-Level API Access

You can also use the lower-level API functions directly:

```elixir
# Get pages with specific parameters
{:ok, response} = ConfluenceLoader.get_pages(client)

# Get pages with query parameters
{:ok, response} = ConfluenceLoader.get_pages(client, %{
  space_id: ["123"],
  limit: 25,
  sort: "-created-date"
})

# Get a specific page
{:ok, page} = ConfluenceLoader.get_page(client, "page_id")

# Get pages in a space
{:ok, response} = ConfluenceLoader.get_pages_in_space(client, "PROJ")

# Get pages by label
{:ok, response} = ConfluenceLoader.get_pages_for_label(client, "label_id")
```

### Pagination

The library handles pagination automatically when using `load_documents` functions. For manual pagination with the low-level API:

```elixir
# Create client
client = ConfluenceLoader.new_client(
  "https://your-domain.atlassian.net",
  "email@example.com",
  "api-token"
)

# Function to fetch all pages
def fetch_all_pages(client, cursor \\ nil, accumulated \\ []) do
  params = %{limit: 25}
  params = if cursor, do: Map.put(params, :cursor, cursor), else: params
  
  case ConfluenceLoader.get_pages(client, params) do
    {:ok, response} ->
      pages = response["results"] || []
      accumulated = accumulated ++ pages
      
      case response["_links"]["next"] do
        nil -> 
          {:ok, accumulated}
        _ ->
          # Extract cursor from next link
          alias ConfluenceLoader.Pages
          next_cursor = Pages.extract_cursor_from_next_link(response)
          fetch_all_pages(client, next_cursor, accumulated)
      end
      
    {:error, reason} ->
      {:error, reason}
  end
end

# Use it
{:ok, first_page} = ConfluenceLoader.get_pages(client, %{limit: 25})
```

### Status Filtering

You can filter documents by their status. The library supports the following page statuses:

- `current` - Published pages (default)
- `archived` - Archived pages  
- `deleted` - Deleted pages
- `trashed` - Pages in trash

```elixir
# Load only current pages (default behavior)
{:ok, documents} = ConfluenceLoader.load_documents(client)

# Load only archived pages
{:ok, documents} = ConfluenceLoader.load_documents(client, %{status: ["archived"]})

# Load current and deleted pages
{:ok, documents} = ConfluenceLoader.load_documents(client, %{status: ["current", "deleted"]})

# Load from specific space with status filtering
{:ok, documents} = ConfluenceLoader.load_space_documents(client, "PROJ", %{status: ["archived"]})

# Load documents since timestamp with status filtering
{:ok, documents} = ConfluenceLoader.load_documents_since(
  client, 
  "PROJ", 
  "2024-01-01T00:00:00Z", 
  %{status: ["current", "archived"]}
)

# Stream documents with status filtering
client
|> ConfluenceLoader.stream_space_documents("PROJ", %{status: ["current"]})
|> Enum.each(fn batch ->
  # Process batch of current documents
  process_documents(batch)
end)
```

## Testing

The library includes comprehensive test coverage using Bypass for mocking HTTP requests:

```bash
mix test
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create a new Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

This library is inspired by the Python [llama-index-readers-confluence](https://pypi.org/project/llama-index-readers-confluence/) library and provides similar functionality for the Elixir ecosystem.


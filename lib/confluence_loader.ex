defmodule ConfluenceLoader do
  @moduledoc """
  ConfluenceLoader is an Elixir library for fetching and reading Confluence pages.

  It provides a simple interface to interact with Confluence's REST API and
  convert pages into a format suitable for use with language models.

  ## Installation

  Add `confluence_loader` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:confluence_loader, "~> 0.1.0"}
        ]
      end

  ## Basic Usage

      # Create a client
      client = ConfluenceLoader.new_client(
        "https://your-domain.atlassian.net",
        "your-email@example.com",
        "your-api-token"
      )

      # Load all documents
      {:ok, documents} = ConfluenceLoader.load_documents(client)

      # Load documents from a specific space
      {:ok, documents} = ConfluenceLoader.load_space_documents(client, "SPACE_KEY")

      # Get a specific page
      {:ok, page} = ConfluenceLoader.get_page(client, "123456")
  """

  alias ConfluenceLoader.{Client, Pages, Document}

  @doc """
  Creates a new Confluence client.

  ## Parameters
    - base_url: The base URL of your Confluence instance
    - username: Your Atlassian username (email)
    - api_token: Your Atlassian API token
    - opts: Optional configuration (e.g., timeout)
  """
  @spec new_client(String.t(), String.t(), String.t(), keyword()) :: Client.t()
  defdelegate new_client(base_url, username, api_token, opts \\ []), to: Client, as: :new

  @doc """
  Load all pages from Confluence as documents.

  ## Parameters
    - client: The Confluence client
    - params: Optional filtering parameters
  """
  @spec load_documents(Client.t(), map()) :: {:ok, list(Document.t())} | {:error, term()}
  defdelegate load_documents(client, params \\ %{}), to: Pages

  @doc """
  Load pages from a specific space as documents.

  ## Parameters
    - client: The Confluence client
    - space_key: The key of the space (e.g., "PROJ", "TEAM")
    - params: Optional filtering parameters
  """
  @spec load_space_documents(Client.t(), String.t() | integer(), map()) ::
          {:ok, list(Document.t())} | {:error, term()}
  defdelegate load_space_documents(client, space_key, params \\ %{}), to: Pages

  @doc """
  Load documents from a specific space created at or after a given timestamp.

  This method filters pages by namespace (space) and creation timestamp, useful for
  incremental updates or getting only recent content changes.

  ## Parameters
    - client: The Confluence client
    - space_key: The key of the space (e.g., "PROJ", "TEAM")
    - since_timestamp: DateTime struct or ISO 8601 string (e.g., "2024-01-01T00:00:00Z")
    - params: Optional filtering parameters
  """
  @spec load_documents_since(Client.t(), String.t() | integer(), DateTime.t() | String.t(), map()) ::
          {:ok, list(Document.t())} | {:error, term()}
  defdelegate load_documents_since(client, space_key, since_timestamp, params \\ %{}), to: Pages

  @doc """
  Get all pages with optional filtering.

  ## Parameters
    - client: The Confluence client
    - params: Optional filtering parameters
  """
  @spec get_pages(Client.t(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate get_pages(client, params \\ %{}), to: Pages

  @doc """
  Get a specific page by ID.

  ## Parameters
    - client: The Confluence client
    - page_id: The ID of the page
    - params: Optional parameters
  """
  @spec get_page(Client.t(), String.t() | integer(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate get_page(client, page_id, params \\ %{}), to: Pages

  @doc """
  Get pages in a specific space.

  ## Parameters
    - client: The Confluence client
    - space_key: The key of the space (e.g., "PROJ", "TEAM")
    - params: Optional filtering parameters
  """
  @spec get_pages_in_space(Client.t(), String.t() | integer(), map()) ::
          {:ok, map()} | {:error, term()}
  defdelegate get_pages_in_space(client, space_key, params \\ %{}), to: Pages

  @doc """
  Get pages for a specific label.

  ## Parameters
    - client: The Confluence client
    - label_id: The ID of the label
    - params: Optional filtering parameters
  """
  @spec get_pages_for_label(Client.t(), String.t() | integer(), map()) ::
          {:ok, map()} | {:error, term()}
  defdelegate get_pages_for_label(client, label_id, params \\ %{}), to: Pages
end

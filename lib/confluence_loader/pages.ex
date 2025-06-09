defmodule ConfluenceLoader.Pages do
  @moduledoc """
  Functions for fetching and processing Confluence pages.
  """

  alias ConfluenceLoader.Client
  alias ConfluenceLoader.Document

  @type page_params :: %{
          optional(:id) => list(integer()),
          optional(:space_id) => list(integer()),
          optional(:sort) => String.t(),
          optional(:status) => list(String.t()),
          optional(:title) => String.t(),
          optional(:body_format) => String.t(),
          optional(:cursor) => String.t(),
          optional(:limit) => integer()
        }

  @doc """
  Get all pages with optional filtering.

  ## Parameters
    - client: The Confluence client
    - params: Optional parameters for filtering pages

  ## Examples
      iex> {:ok, pages} = ConfluenceLoader.Pages.get_pages(client, %{space_id: [123], limit: 10})
  """
  @spec get_pages(Client.t(), page_params()) :: {:ok, map()} | {:error, term()}
  def get_pages(%Client{} = client, params \\ %{}) do
    params
    |> build_query_params()
    |> then(&Client.get(client, "/pages", &1))
  end

  @doc """
  Get a specific page by ID.

  ## Parameters
    - client: The Confluence client
    - page_id: The ID of the page to retrieve
    - params: Optional parameters (e.g., body_format)

  ## Examples
      iex> {:ok, page} = ConfluenceLoader.Pages.get_page(client, "123456")
  """
  @spec get_page(Client.t(), String.t() | integer(), map()) :: {:ok, map()} | {:error, term()}
  def get_page(%Client{} = client, page_id, params \\ %{}) do
    params
    |> build_query_params()
    |> then(&Client.get(client, "/pages/#{page_id}", &1))
  end

  @doc """
  Get pages in a specific space.

  ## Parameters
    - client: The Confluence client
    - space_key: The key of the space (e.g., "PROJ", "TEAM") or numeric space ID
    - params: Optional parameters for filtering

  ## Examples
      iex> {:ok, pages} = ConfluenceLoader.Pages.get_pages_in_space(client, "PROJ", %{limit: 20})
  """
  @spec get_pages_in_space(Client.t(), String.t() | integer(), map()) ::
          {:ok, map()} | {:error, term()}
  def get_pages_in_space(%Client{} = client, space_key, params \\ %{}) do
    space_key
    |> to_string()
    |> Integer.parse()
    |> handle_space_key(client, params, space_key)
  end

  # Handle numeric space ID
  defp handle_space_key({space_id, ""}, client, params, _original_key) do
    params
    |> build_query_params()
    |> then(&Client.get(client, "/spaces/#{space_id}/pages", &1))
  end

  # Handle space key
  defp handle_space_key(_, client, params, space_key) do
    with {:ok, space} <- get_space_by_key(client, space_key) do
      params
      |> build_query_params()
      |> then(&Client.get(client, "/spaces/#{space["id"]}/pages", &1))
    end
  end

  @doc """
  Get pages for a specific label.

  ## Parameters
    - client: The Confluence client
    - label_id: The ID of the label
    - params: Optional parameters for filtering

  ## Examples
      iex> {:ok, pages} = ConfluenceLoader.Pages.get_pages_for_label(client, "456", %{limit: 10})
  """
  @spec get_pages_for_label(Client.t(), String.t() | integer(), map()) ::
          {:ok, map()} | {:error, term()}
  def get_pages_for_label(%Client{} = client, label_id, params \\ %{}) do
    params
    |> build_query_params()
    |> then(&Client.get(client, "/labels/#{label_id}/pages", &1))
  end

  @doc """
  Load all pages from Confluence and convert them to Document format.
  This function mimics the behavior of the Python llama-index-readers-confluence library.

  ## Parameters
    - client: The Confluence client
    - params: Optional parameters for filtering pages
      - `:status` - List of page statuses to filter by. Default: `["current"]`
        Valid values: `["current", "archived", "deleted", "trashed"]`
      - `:space_id` - List of space IDs to filter by
      - `:limit` - Maximum number of documents to return
      - `:body_format` - Format for page body (default: "storage")

  ## Examples
      iex> {:ok, documents} = ConfluenceLoader.Pages.load_documents(client, %{space_id: [123]})

      # Load only archived pages
      iex> {:ok, documents} = ConfluenceLoader.Pages.load_documents(client, %{status: ["archived"]})

      # Load current and deleted pages
      iex> {:ok, documents} = ConfluenceLoader.Pages.load_documents(client, %{status: ["current", "deleted"]})
  """
  @spec load_documents(Client.t(), map()) :: {:ok, list(Document.t())} | {:error, term()}
  def load_documents(%Client{} = client, params \\ %{}) do
    total_limit = Map.get(params, :limit)
    params_with_defaults =
      params
      |> Map.put_new(:status, ["current"])
      |> Map.put_new(:body_format, "storage")

    with {:ok, pages} <- get_all_pages_paginated(client, params_with_defaults, [], total_limit) do
      documents = Enum.map(pages, &page_to_document/1)
      {:ok, documents}
    end
  end

  @doc """
  Load pages from a specific space and convert them to Document format.

  ## Parameters
    - client: The Confluence client
    - space_key: The key of the space (e.g., "PROJ", "TEAM") or numeric space ID
    - params: Optional parameters for filtering
      - `:status` - List of page statuses to filter by. Default: `["current"]`
        Valid values: `["current", "archived", "deleted", "trashed"]`
      - `:limit` - Maximum number of documents to return
      - `:body_format` - Format for page body (default: "storage")

  ## Examples
      iex> {:ok, documents} = ConfluenceLoader.Pages.load_space_documents(client, "PROJ")

      # Load only archived pages from space
      iex> {:ok, documents} = ConfluenceLoader.Pages.load_space_documents(client, "PROJ", %{status: ["archived"]})

      # Load current and trashed pages from space
      iex> {:ok, documents} = ConfluenceLoader.Pages.load_space_documents(client, "PROJ", %{status: ["current", "trashed"]})
  """
  @spec load_space_documents(Client.t(), String.t() | integer(), map()) ::
          {:ok, list(Document.t())} | {:error, term()}
  def load_space_documents(%Client{} = client, space_key, params \\ %{}) do
    total_limit = Map.get(params, :limit)
    params_with_defaults =
      params
      |> Map.put_new(:status, ["current"])
      |> Map.put_new(:body_format, "storage")

    space_key
    |> to_string()
    |> Integer.parse()
    |> handle_space_documents(client, params_with_defaults, total_limit, space_key)
  end

  @doc """
  Load documents from a specific space created at or after a given timestamp.

  This method filters pages by namespace (space) and creation timestamp. Since the
  Confluence API doesn't directly support timestamp filtering, this method fetches
  all pages from the space and filters them client-side.

  ## Parameters
    - client: The Confluence client
    - space_key: The key of the space (e.g., "PROJ", "TEAM") or numeric space ID
    - since_timestamp: DateTime struct or ISO 8601 string (e.g., "2024-01-01T00:00:00Z")
    - params: Optional parameters for filtering (limit, body_format, etc.)
      - `:status` - List of page statuses to filter by. Default: `["current"]`
        Valid values: `["current", "archived", "deleted", "trashed"]`
      - `:limit` - Maximum number of documents to return
      - `:body_format` - Format for page body (default: "storage")

  ## Examples
      # Using DateTime
      {:ok, since_date} = DateTime.new(~D[2024-01-01], ~T[00:00:00], "Etc/UTC")
      {:ok, documents} = ConfluenceLoader.Pages.load_documents_since(client, "PROJ", since_date)

      # Using ISO string
      {:ok, documents} = ConfluenceLoader.Pages.load_documents_since(client, "PROJ", "2024-01-01T00:00:00Z")

      # With additional parameters including status
      {:ok, documents} = ConfluenceLoader.Pages.load_documents_since(client, "PROJ", since_date, %{limit: 50, status: ["current", "archived"]})
  """
  @spec load_documents_since(Client.t(), String.t() | integer(), DateTime.t() | String.t(), map()) ::
          {:ok, list(Document.t())} | {:error, term()}
  def load_documents_since(%Client{} = client, space_key, since_timestamp, params \\ %{}) do
    params_with_defaults = Map.put_new(params, :status, ["current"])

    with {:ok, since_datetime} <- parse_timestamp(since_timestamp),
         {:ok, all_documents} <- load_space_documents(client, space_key, params_with_defaults) do
      filtered_documents =
        all_documents
        |> Enum.filter(&created_at_or_after?(&1, since_datetime))

      {:ok, filtered_documents}
    end
  end

  @doc """
  Stream documents from a specific space in batches of 4.

  This function returns a Stream that yields batches of 4 documents at a time
  until all documents from the space have been processed. It's memory efficient
  as it doesn't load all documents into memory at once.

  ## Parameters
    - client: The Confluence client
    - space_key: The key of the space (e.g., "PROJ", "TEAM") or numeric space ID
    - params: Optional parameters for filtering (body_format, etc.)
      - `:status` - List of page statuses to filter by. Default: `["current"]`
        Valid values: `["current", "archived", "deleted", "trashed"]`
      - `:body_format` - Format for page body (default: "storage")

  ## Examples
      # Stream and process documents in batches of 4
      client
      |> ConfluenceLoader.Pages.stream_space_documents("PROJ")
      |> Enum.each(fn batch ->
        IO.puts("Processing batch of \#{length(batch)} documents")
        Enum.each(batch, fn doc -> IO.puts("  - \#{doc.metadata.title}") end)
      end)

      # Stream only archived documents
      client
      |> ConfluenceLoader.Pages.stream_space_documents("PROJ", %{status: ["archived"]})
      |> Enum.each(fn batch ->
        # Process each batch of archived documents
        process_archived_batch(batch)
      end)

      # With async processing using Task.async_stream
      client
      |> ConfluenceLoader.Pages.stream_space_documents("PROJ")
      |> Task.async_stream(fn batch ->
        # Process each batch concurrently
        Enum.map(batch, &process_document/1)
      end, max_concurrency: 2)
      |> Enum.to_list()
  """
  @spec stream_space_documents(Client.t(), String.t() | integer(), map()) :: Enumerable.t()
  def stream_space_documents(%Client{} = client, space_key, params \\ %{}) do
    params_with_defaults =
      params
      |> Map.put_new(:status, ["current"])
      |> Map.put_new(:body_format, "storage")

    Stream.resource(
      fn -> initialize_stream_state(client, space_key, params_with_defaults) end,
      &fetch_next_batch/1,
      fn _ -> :ok end
    )
  end

  # Handle numeric space ID for documents
  defp handle_space_documents({space_id, ""}, client, params, total_limit, _original_key) do
    with {:ok, pages} <- get_all_space_pages_paginated(client, space_id, params, [], total_limit) do
      {:ok, Enum.map(pages, &page_to_document/1)}
    end
  end

  # Handle space key for documents
  defp handle_space_documents(_, client, params, total_limit, space_key) do
    with {:ok, space} <- get_space_by_key(client, space_key),
         {:ok, pages} <-
           get_all_space_pages_paginated(client, space["id"], params, [], total_limit) do
      {:ok, Enum.map(pages, &page_to_document/1)}
    end
  end

  @doc """
  Convert a page response to a Document struct.

  This is useful when you fetch a page directly and want to convert it to a Document.

  ## Parameters
    - page: The page response from the API

  ## Examples
      iex> {:ok, page} = ConfluenceLoader.get_page(client, "123", %{body_format: "storage"})
      iex> doc = ConfluenceLoader.Pages.page_to_document(page)
  """
  @spec page_to_document(map()) :: Document.t()
  def page_to_document(page) do
    Document.new(
      page["id"],
      extract_text_from_page(page),
      build_page_metadata(page)
    )
  end

  # Private functions

  defp build_page_metadata(page) do
    %{
      title: page["title"],
      space_id: page["spaceId"],
      parent_id: page["parentId"],
      status: page["status"],
      created_at: page["createdAt"],
      author_id: page["authorId"],
      version: page["version"],
      web_url: get_in(page, ["_links", "webui"]),
      edit_url: get_in(page, ["_links", "editui"])
    }
  end

  defp build_query_params(params) do
    params
    |> Enum.map(&transform_param/1)
    |> Enum.into([])
  end

  defp transform_param({:space_id, values}) when is_list(values),
    do: {"space-id", Enum.join(values, ",")}

  defp transform_param({:status, values}) when is_list(values),
    do: {"status", Enum.join(values, ",")}

  defp transform_param({:body_format, value}),
    do: {"body-format", value}

  defp transform_param({key, value}),
    do: {to_string(key), to_string(value)}

  @spec get_space_by_key(Client.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defp get_space_by_key(client, space_key) do
    case Client.get(client, "/spaces", [{"keys", space_key}, {"limit", "1"}]) do
      {:ok, %{"results" => [space | _]}} ->
        {:ok, space}

      {:ok, %{"results" => []}} ->
        {:error, {:not_found, "Space with key '#{space_key}' not found"}}

      {:error, _} = error ->
        error

      unexpected ->
        {:error, {:invalid_response, unexpected}}
    end
  end

  defp get_all_pages_paginated(_client, _params, accumulated, total_limit)
       when is_integer(total_limit) and length(accumulated) >= total_limit do
    {:ok, Enum.take(accumulated, total_limit)}
  end

  defp get_all_pages_paginated(client, params, accumulated, total_limit) do
    case get_pages(client, params) do
      {:ok, response} ->
        handle_paginated_response(
          response,
          client,
          params,
          accumulated,
          total_limit,
          &get_all_pages_paginated/4
        )

      error ->
        error
    end
  end

  defp get_all_space_pages_paginated(_client, _space_id, _params, accumulated, total_limit)
       when is_integer(total_limit) and length(accumulated) >= total_limit do
    {:ok, Enum.take(accumulated, total_limit)}
  end

  defp get_all_space_pages_paginated(client, space_id, params, accumulated, total_limit) do
    case get_pages_in_space(client, space_id, params) do
      {:ok, response} ->
        handle_paginated_response(
          response,
          client,
          params,
          accumulated,
          total_limit,
          fn c, p, a, l -> get_all_space_pages_paginated(c, space_id, p, a, l) end
        )

      error ->
        error
    end
  end

  defp handle_paginated_response(response, client, params, accumulated, total_limit, continue_fn) do
    results = Map.get(response, "results", [])
    links = Map.get(response, "_links", %{})

    results_with_body = fetch_pages_with_body(client, results, params)
    new_accumulated = accumulated ++ results_with_body

    handle_pagination_logic(
      {total_limit, new_accumulated, links},
      {client, params, continue_fn}
    )
  end

  # When limit is reached
  defp handle_pagination_logic(
         {total_limit, accumulated, _links},
         _continuation_params
       )
       when is_integer(total_limit) and length(accumulated) >= total_limit do
    {:ok, Enum.take(accumulated, total_limit)}
  end

  # When there's a next page
  defp handle_pagination_logic(
         {total_limit, accumulated, %{"next" => next_url}},
         {client, params, continue_fn}
       ) do
    cursor = extract_cursor_from_url(next_url)
    new_params = Map.put(params, :cursor, cursor)
    continue_fn.(client, new_params, accumulated, total_limit)
  end

  # When no more pages
  defp handle_pagination_logic({_total_limit, accumulated, _links}, _continuation_params) do
    {:ok, accumulated}
  end

  defp fetch_pages_with_body(client, pages, params) do
    body_format = Map.get(params, :body_format, "storage")

    pages
    |> Enum.map(fn page ->
      case get_page(client, page["id"], %{body_format: body_format}) do
        {:ok, full_page} -> full_page
        {:error, _} -> page
      end
    end)
  end

  defp extract_cursor_from_url(url) do
    url
    |> URI.parse()
    |> Map.get(:query, "")
    |> URI.decode_query()
    |> Map.get("cursor")
  end

  defp extract_text_from_page(%{"body" => body}) when is_map(body) do
    extract_body_content(body)
  end

  defp extract_text_from_page(_), do: ""

  defp extract_body_content(%{"storage" => %{"value" => html}}) when is_binary(html),
    do: strip_html_tags(html)

  defp extract_body_content(%{"view" => %{"value" => html}}) when is_binary(html),
    do: strip_html_tags(html)

  defp extract_body_content(%{"atlas_doc_format" => %{"value" => content}})
       when is_binary(content),
       do: content

  defp extract_body_content(_), do: ""

  defp strip_html_tags(html) do
    html
    |> String.replace(~r/<script.*?<\/script>/s, "")
    |> String.replace(~r/<style.*?<\/style>/s, "")
    |> String.replace(~r/<[^>]+>/, " ")
    |> decode_html_entities()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @html_entities %{
    # Basic HTML entities
    "&nbsp;" => " ",
    "&lt;" => "<",
    "&gt;" => ">",
    "&amp;" => "&",
    "&quot;" => "\"",
    "&#39;" => "'",
    "&apos;" => "'",
    # Portuguese characters
    "&ccedil;" => "ç",
    "&Ccedil;" => "Ç",
    "&atilde;" => "ã",
    "&Atilde;" => "Ã",
    "&otilde;" => "õ",
    "&Otilde;" => "Õ",
    "&aacute;" => "á",
    "&Aacute;" => "Á",
    "&eacute;" => "é",
    "&Eacute;" => "É",
    "&iacute;" => "í",
    "&Iacute;" => "Í",
    "&oacute;" => "ó",
    "&Oacute;" => "Ó",
    "&uacute;" => "ú",
    "&Uacute;" => "Ú",
    "&agrave;" => "à",
    "&Agrave;" => "À",
    "&acirc;" => "â",
    "&Acirc;" => "Â",
    "&ecirc;" => "ê",
    "&Ecirc;" => "Ê",
    "&ocirc;" => "ô",
    "&Ocirc;" => "Ô",
    # Common typographic entities
    "&mdash;" => "—",
    "&ndash;" => "–",
    "&hellip;" => "...",
    "&euro;" => "€",
    "&pound;" => "£",
    "&copy;" => "©",
    "&reg;" => "®",
    "&trade;" => "™"
  }

  defp decode_html_entities(text) do
    text
    |> replace_named_entities()
    |> decode_numeric_entities()
  end

  defp replace_named_entities(text) do
    Enum.reduce(@html_entities, text, fn {entity, replacement}, acc ->
      String.replace(acc, entity, replacement)
    end)
  end

  defp decode_numeric_entities(text) do
    Regex.replace(~r/&#(\d+);/, text, fn _, code_str ->
      case Integer.parse(code_str) do
        {code, ""} when code > 0 and code < 1_114_112 ->
          <<code::utf8>>

        _ ->
          "&##{code_str};"
      end
    end)
  end

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _} -> {:ok, datetime}
      _ -> {:error, :invalid_timestamp}
    end
  end

  defp parse_timestamp(%DateTime{} = datetime) do
    {:ok, datetime}
  end

  defp parse_timestamp(_) do
    {:error, :invalid_timestamp}
  end

  defp created_at_or_after?(%Document{metadata: metadata}, since_datetime) do
    with created_at_str when is_binary(created_at_str) <- extract_created_at(metadata),
         {:ok, created_at, _} <- DateTime.from_iso8601(created_at_str) do
      DateTime.compare(created_at, since_datetime) != :lt
    else
      _ -> false
    end
  end

  defp extract_created_at(metadata) do
    get_in(metadata, [:version, "createdAt"]) ||
      get_in(metadata, ["version", "createdAt"]) ||
      get_in(metadata, [:version, :createdAt])
  end

  # Private helper functions for streaming

  defp initialize_stream_state(client, space_key, params) do
    case resolve_space_id(client, space_key) do
      {:ok, space_id} ->
        %{
          client: client,
          space_id: space_id,
          params: params,
          cursor: nil,
          buffer: [],
          finished: false
        }

      {:error, _} = error ->
        %{error: error, finished: true}
    end
  end

  defp fetch_more_documents(
         %{client: client, space_id: space_id, params: params, cursor: cursor} = state
       ) do
    request_params = if cursor, do: Map.put(params, :cursor, cursor), else: params

    case get_pages_in_space(client, space_id, request_params) do
      {:ok, response} ->
        results = Map.get(response, "results", [])
        links = Map.get(response, "_links", %{})

        # Don't fetch bodies yet - just store page metadata
        new_buffer = state.buffer ++ results

        next_cursor =
          if Map.has_key?(links, "next"),
            do: extract_cursor_from_url(links["next"]),
            else: nil

        finished = is_nil(next_cursor)

        {:ok, %{state | buffer: new_buffer, cursor: next_cursor, finished: finished}}

      {:error, _} = error ->
        error
    end
  end

  # New function to fetch bodies for a batch of pages
  defp fetch_batch_bodies(client, pages, params) do
    body_format = Map.get(params, :body_format, "storage")

    pages
    |> Task.async_stream(
      fn page ->
        case get_page(client, page["id"], %{body_format: body_format}) do
          {:ok, full_page} -> page_to_document(full_page)
          {:error, _} -> page_to_document(page)
        end
      end,
      max_concurrency: 4,
      timeout: 30_000
    )
    |> Enum.map(fn
      {:ok, doc} -> doc
      {:exit, _} -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_next_batch(%{error: error, finished: true}), do: {:halt, error}
  defp fetch_next_batch(%{finished: true}), do: {:halt, nil}

  defp fetch_next_batch(%{buffer: buffer, client: client, params: params} = state)
       when length(buffer) >= 4 do
    {batch_pages, remaining} = Enum.split(buffer, 4)
    # Fetch bodies only for this batch
    batch_documents = fetch_batch_bodies(client, batch_pages, params)
    {[batch_documents], %{state | buffer: remaining}}
  end

  defp fetch_next_batch(%{buffer: buffer, finished: true, client: client, params: params} = state)
       when buffer != [] do
    # Yield remaining items when finished but buffer has items
    batch_documents = fetch_batch_bodies(client, buffer, params)
    {[batch_documents], %{state | buffer: []}}
  end

  defp fetch_next_batch(%{buffer: [], finished: true}), do: {:halt, nil}

  defp fetch_next_batch(state) do
    case fetch_more_documents(state) do
      {:ok, new_state} -> fetch_next_batch(new_state)
      {:error, _} = error -> {:halt, error}
    end
  end

  defp resolve_space_id(client, space_key) do
    space_key
    |> to_string()
    |> Integer.parse()
    |> handle_space_id_resolution(client, space_key)
  end

  defp handle_space_id_resolution({space_id, ""}, _client, _space_key), do: {:ok, space_id}

  defp handle_space_id_resolution(_, client, space_key) do
    case get_space_by_key(client, space_key) do
      {:ok, space} -> {:ok, space["id"]}
      error -> error
    end
  end
end

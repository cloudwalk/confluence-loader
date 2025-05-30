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

  ## Examples
      iex> {:ok, documents} = ConfluenceLoader.Pages.load_documents(client, %{space_id: [123]})
  """
  @spec load_documents(Client.t(), map()) :: {:ok, list(Document.t())} | {:error, term()}
  def load_documents(%Client{} = client, params \\ %{}) do
    total_limit = Map.get(params, :limit)
    params_with_body = Map.put_new(params, :body_format, "storage")

    with {:ok, pages} <- get_all_pages_paginated(client, params_with_body, [], total_limit) do
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

  ## Examples
      iex> {:ok, documents} = ConfluenceLoader.Pages.load_space_documents(client, "PROJ")
  """
  @spec load_space_documents(Client.t(), String.t() | integer(), map()) ::
          {:ok, list(Document.t())} | {:error, term()}
  def load_space_documents(%Client{} = client, space_key, params \\ %{}) do
    total_limit = Map.get(params, :limit)
    params_with_body = Map.put_new(params, :body_format, "storage")

    space_key
    |> to_string()
    |> Integer.parse()
    |> handle_space_documents(client, params_with_body, total_limit, space_key)
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

  ## Examples
      # Using DateTime
      {:ok, since_date} = DateTime.new(~D[2024-01-01], ~T[00:00:00], "Etc/UTC")
      {:ok, documents} = ConfluenceLoader.Pages.load_documents_since(client, "PROJ", since_date)

      # Using ISO string
      {:ok, documents} = ConfluenceLoader.Pages.load_documents_since(client, "PROJ", "2024-01-01T00:00:00Z")

      # With additional parameters
      {:ok, documents} = ConfluenceLoader.Pages.load_documents_since(client, "PROJ", since_date, %{limit: 50})
  """
  @spec load_documents_since(Client.t(), String.t() | integer(), DateTime.t() | String.t(), map()) ::
          {:ok, list(Document.t())} | {:error, term()}
  def load_documents_since(%Client{} = client, space_key, since_timestamp, params \\ %{}) do
    with {:ok, since_datetime} <- parse_timestamp(since_timestamp),
         {:ok, all_documents} <- load_space_documents(client, space_key, params) do

      filtered_documents =
        all_documents
        |> Enum.filter(&created_at_or_after?(&1, since_datetime))

      {:ok, filtered_documents}
    end
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

  defp transform_param({:body_format, value}),
    do: {"body-format", value}

  defp transform_param({key, value}),
    do: {to_string(key), to_string(value)}

  defp get_space_by_key(client, space_key) do
    case Client.get(client, "/spaces", [{"keys", space_key}, {"limit", "1"}]) do
      {:ok, %{"results" => [space | _]}} ->
        {:ok, space}

      {:ok, %{"results" => []}} ->
        {:error, {:not_found, "Space with key '#{space_key}' not found"}}

      error ->
        error
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

    cond do
      is_integer(total_limit) and length(new_accumulated) >= total_limit ->
        {:ok, Enum.take(new_accumulated, total_limit)}

      Map.has_key?(links, "next") ->
        cursor = extract_cursor_from_url(links["next"])
        new_params = Map.put(params, :cursor, cursor)
        continue_fn.(client, new_params, new_accumulated, total_limit)

      true ->
        {:ok, new_accumulated}
    end
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

  defp decode_html_entities(text) do
    text
    # Basic HTML entities that are structural, not encoding-related
    |> String.replace(~r/&nbsp;/, " ")
    |> String.replace(~r/&lt;/, "<")
    |> String.replace(~r/&gt;/, ">")
    |> String.replace(~r/&amp;/, "&")
    |> String.replace(~r/&quot;/, "\"")
    |> String.replace(~r/&#39;/, "'")
    |> String.replace(~r/&apos;/, "'")
    # Portuguese characters
    |> String.replace(~r/&ccedil;/, "ç")
    |> String.replace(~r/&Ccedil;/, "Ç")
    |> String.replace(~r/&atilde;/, "ã")
    |> String.replace(~r/&Atilde;/, "Ã")
    |> String.replace(~r/&otilde;/, "õ")
    |> String.replace(~r/&Otilde;/, "Õ")
    |> String.replace(~r/&aacute;/, "á")
    |> String.replace(~r/&Aacute;/, "Á")
    |> String.replace(~r/&eacute;/, "é")
    |> String.replace(~r/&Eacute;/, "É")
    |> String.replace(~r/&iacute;/, "í")
    |> String.replace(~r/&Iacute;/, "Í")
    |> String.replace(~r/&oacute;/, "ó")
    |> String.replace(~r/&Oacute;/, "Ó")
    |> String.replace(~r/&uacute;/, "ú")
    |> String.replace(~r/&Uacute;/, "Ú")
    |> String.replace(~r/&agrave;/, "à")
    |> String.replace(~r/&Agrave;/, "À")
    |> String.replace(~r/&acirc;/, "â")
    |> String.replace(~r/&Acirc;/, "Â")
    |> String.replace(~r/&ecirc;/, "ê")
    |> String.replace(~r/&Ecirc;/, "Ê")
    |> String.replace(~r/&ocirc;/, "ô")
    |> String.replace(~r/&Ocirc;/, "Ô")
    # Common typographic entities
    |> String.replace(~r/&mdash;/, "—")
    |> String.replace(~r/&ndash;/, "–")
    |> String.replace(~r/&hellip;/, "...")
    |> String.replace(~r/&euro;/, "€")
    |> String.replace(~r/&pound;/, "£")
    |> String.replace(~r/&copy;/, "©")
    |> String.replace(~r/&reg;/, "®")
    |> String.replace(~r/&trade;/, "™")
    # Generic numeric entity fallback
    |> decode_numeric_entities()
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
    # Try to get createdAt from version object (could be atom or string keys)
    created_at_str = get_in(metadata, [:version, "createdAt"]) ||
                     get_in(metadata, ["version", "createdAt"]) ||
                     get_in(metadata, [:version, :createdAt])

    case created_at_str do
      nil -> false
      created_at_str when is_binary(created_at_str) ->
        case DateTime.from_iso8601(created_at_str) do
          {:ok, created_at, _} -> DateTime.compare(created_at, since_datetime) != :lt
          _ -> false
        end
      _ -> false
    end
  end
end

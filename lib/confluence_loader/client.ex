defmodule ConfluenceLoader.Client do
  @moduledoc """
  HTTP client for interacting with the Confluence REST API.

  This module handles authentication and request formatting for the Confluence API.
  It supports both cloud and server instances of Confluence.

  ## Configuration

  The client requires:
  - `base_url`: Your Confluence instance URL (e.g., "https://example.atlassian.net")
  - `username`: Your email address (for cloud) or username (for server)
  - `api_token`: Your API token (for cloud) or password (for server)

  ## Options

  - `:api_base_path` - The base path for the API (default: "/wiki/api/v2")
  - `:timeout` - Request timeout in milliseconds (default: 30_000)
  - `:recv_timeout` - Receive timeout in milliseconds (default: 30_000)

  ## Examples

      # For Confluence Cloud
      client = ConfluenceLoader.Client.new("https://example.atlassian.net", "user@example.com", "api_token")
      %ConfluenceLoader.Client{...}

      # For Confluence Server with custom API path
      client = ConfluenceLoader.Client.new("https://example.atlassian.net", "user@example.com", "api_token", api_base_path: "/api/v2")
      %ConfluenceLoader.Client{...}

  """

  @default_base_path "/wiki/api/v2"
  @default_timeout 30_000

  defstruct [:base_url, :username, :api_token, :timeout, :api_base_path]

  @type t :: %__MODULE__{
          base_url: String.t(),
          username: String.t(),
          api_token: String.t(),
          timeout: non_neg_integer(),
          api_base_path: String.t()
        }

  @doc """
  Creates a new Confluence client.

  ## Parameters
    - base_url: The base URL of your Confluence instance (e.g., "https://your-domain.atlassian.net")
    - username: Your Atlassian username (email)
    - api_token: Your Atlassian API token
    - opts: Optional keyword list with:
      - timeout: Request timeout in milliseconds (default: 30000)
      - api_base_path: Custom API base path (default: "/wiki/api/v2")

  ## Examples
      iex> client = ConfluenceLoader.Client.new("https://example.atlassian.net", "user@example.com", "api_token")
      %ConfluenceLoader.Client{...}

      # For Confluence Cloud with different API path
      iex> client = ConfluenceLoader.Client.new("https://example.atlassian.net", "user@example.com", "api_token", api_base_path: "/api/v2")
      %ConfluenceLoader.Client{...}
  """
  @spec new(String.t(), String.t(), String.t(), keyword()) :: t()
  def new(base_url, username, api_token, opts \\ []) do
    %__MODULE__{
      base_url: base_url |> String.trim_trailing("/"),
      username: username,
      api_token: api_token,
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      api_base_path: Keyword.get(opts, :api_base_path, @default_base_path)
    }
  end

  @doc """
  Makes a GET request to the Confluence API.
  """
  @spec get(t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get(%__MODULE__{} = client, path, params \\ []) do
    client
    |> build_request_config(path, params)
    |> execute_request()
    |> handle_response()
  end

  # Private functions using pattern matching

  defp build_request_config(client, path, params) do
    %{
      url: build_url(client, path),
      headers: build_headers(client),
      options: build_options(client, params)
    }
  end

  defp execute_request(%{url: url, headers: headers, options: options}) do
    HTTPoison.get(url, headers, options)
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: status, body: body}})
       when status in 200..299 do
    Jason.decode(body)
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: status, body: body}}) do
    with {:ok, error_body} <- Jason.decode(body) do
      {:error, {:api_error, status, error_body}}
    else
      {:error, _} -> {:error, {:api_error, status, body}}
    end
  end

  defp handle_response({:error, %HTTPoison.Error{reason: reason}}) do
    {:error, {:http_error, reason}}
  end

  defp build_url(%__MODULE__{base_url: base_url, api_base_path: api_base_path}, path) do
    "#{base_url}#{api_base_path}#{path}"
  end

  defp build_headers(%__MODULE__{username: username, api_token: api_token}) do
    auth = "#{username}:#{api_token}" |> Base.encode64()

    [
      {"Authorization", "Basic #{auth}"},
      {"Accept", "application/json; charset=utf-8"},
      {"Accept-Charset", "utf-8"},
      {"Content-Type", "application/json; charset=utf-8"}
    ]
  end

  defp build_options(%__MODULE__{timeout: timeout}, params) do
    [
      timeout: timeout,
      recv_timeout: timeout,
      params: params
    ]
  end
end

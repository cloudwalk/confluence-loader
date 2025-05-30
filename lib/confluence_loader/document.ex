defmodule ConfluenceLoader.Document do
  @moduledoc """
  Document struct that represents a Confluence page in a format similar to llama-index documents.
  """

  @enforce_keys [:id, :text]
  defstruct [:id, :text, :metadata]

  @type t :: %__MODULE__{
          id: String.t(),
          text: String.t(),
          metadata: map()
        }

  @doc """
  Creates a new Document.

  ## Parameters
    - id: The unique identifier of the document
    - text: The text content of the document
    - metadata: Optional metadata map

  ## Examples
      iex> doc = ConfluenceLoader.Document.new("123", "This is the content", %{title: "My Page"})
      %ConfluenceLoader.Document{id: "123", text: "This is the content", metadata: %{title: "My Page"}}
  """
  @spec new(String.t(), String.t(), map()) :: t()
  def new(id, text, metadata \\ %{}) do
    %__MODULE__{
      id: id,
      text: text,
      metadata: metadata
    }
  end

  @doc """
  Converts the document to a map format suitable for JSON serialization.

  ## Examples
      iex> doc = ConfluenceLoader.Document.new("123", "Content", %{title: "Page"})
      iex> ConfluenceLoader.Document.to_map(doc)
      %{id: "123", text: "Content", metadata: %{title: "Page"}}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{id: id, text: text, metadata: metadata}) do
    %{
      id: id,
      text: text,
      metadata: metadata
    }
  end

  @doc """
  Creates a Document from a map.

  ## Examples
      iex> ConfluenceLoader.Document.from_map(%{id: "123", text: "Content", metadata: %{title: "Page"}})
      {:ok, %ConfluenceLoader.Document{id: "123", text: "Content", metadata: %{title: "Page"}}}
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with {:ok, id} <- extract_field(map, :id),
         {:ok, text} <- extract_field(map, :text) do
      metadata = extract_metadata(map)
      {:ok, new(id, text, metadata)}
    else
      :error -> {:error, "Invalid document format: missing required fields 'id' and 'text'"}
    end
  end

  @doc """
  Returns a formatted string representation of the document suitable for LLM consumption.

  ## Examples
      iex> doc = ConfluenceLoader.Document.new("123", "Content here", %{title: "My Page", space_id: "SPACE1"})
      iex> ConfluenceLoader.Document.format_for_llm(doc)
  """
  @spec format_for_llm(t()) :: String.t()
  def format_for_llm(%__MODULE__{id: id, text: text, metadata: metadata}) do
    metadata_str =
      metadata
      |> Enum.map(fn {k, v} -> "#{k}: #{format_value(v)}" end)
      |> Enum.join("\n")

    """
    Document ID: #{id}

    Metadata:
    #{metadata_str}

    Content:
    #{text}
    """
  end

  # Private helper functions

  defp extract_field(map, field) when is_atom(field) do
    # Try atom key first, then string key
    case {Map.get(map, field), Map.get(map, to_string(field))} do
      {nil, nil} -> :error
      {value, _} when not is_nil(value) -> {:ok, value}
      {_, value} -> {:ok, value}
    end
  end

  defp extract_metadata(map) do
    Map.get(map, :metadata) || Map.get(map, "metadata") || %{}
  end

  # Pattern matching for different value types
  defp format_value(nil), do: ""
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_number(value), do: to_string(value)
  defp format_value(value) when is_boolean(value), do: to_string(value)
  defp format_value(value) when is_atom(value), do: to_string(value)
  defp format_value(value) when is_map(value), do: inspect(value, pretty: true, limit: :infinity)
  defp format_value(value) when is_list(value), do: inspect(value, pretty: true, limit: :infinity)
  defp format_value(value), do: inspect(value)
end

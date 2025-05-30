# Test script to debug Confluence API connection

# Get configuration from environment variables
confluence_url = System.get_env("CONFLUENCE_URL") || raise "Please set CONFLUENCE_URL environment variable"
username = System.get_env("CONFLUENCE_USERNAME") || raise "Please set CONFLUENCE_USERNAME environment variable"
api_token = System.get_env("CONFLUENCE_API_TOKEN") || raise "Please set CONFLUENCE_API_TOKEN environment variable"

IO.puts("Testing connection to: #{confluence_url}")
IO.puts("Username: #{username}")
IO.puts("")

# Test different API base paths
api_paths_to_try = [
  "/wiki/api/v2",      # Default for most Confluence instances
  "/api/v2",           # Some Confluence Cloud instances
  "/rest/api/v2",      # Alternative path
  ""                   # No base path (API directly under domain)
]

IO.puts("Testing different API v2 base paths...")
IO.puts("")

# Find the first working API path
working_path = Enum.find(api_paths_to_try, fn api_path ->
  IO.puts("Testing with base path: '#{api_path}'")

  # Create a client with this specific API path
  client = ConfluenceLoader.new_client(confluence_url, username, api_token, api_base_path: api_path)

  result = case ConfluenceLoader.Client.get(client, "/pages?limit=1") do
    {:ok, response} ->
      IO.puts("✓ SUCCESS! Found working API v2 at: #{api_path}")
      IO.puts("  Response has #{Map.get(response, "results", []) |> length()} results")
      true

    {:error, {:api_error, 404, _}} ->
      IO.puts("✗ Not found (404)")
      false

    {:error, {:api_error, status, _}} ->
      IO.puts("✗ API error with status: #{status}")
      false

    {:error, reason} ->
      IO.puts("✗ Error: #{inspect(reason)}")
      false
  end

  IO.puts("")
  result
end)

if working_path do
  IO.puts("=====================================")
  IO.puts("SOLUTION FOUND!")
  IO.puts("=====================================")
  IO.puts("")
  IO.puts("Use this configuration:")
  IO.puts("")
  IO.puts("client = ConfluenceLoader.new_client(")
  IO.puts("  \"#{confluence_url}\",")
  IO.puts("  \"#{username}\",")
  IO.puts("  \"your-api-token\",")
  if working_path != "/wiki/api/v2" do
    IO.puts("  api_base_path: \"#{working_path}\"")
  end
  IO.puts(")")
else
  IO.puts("=====================================")
  IO.puts("No working API v2 path found!")
  IO.puts("=====================================")
  IO.puts("")
  IO.puts("This could mean:")
  IO.puts("1. Your Confluence instance doesn't support REST API v2")
  IO.puts("2. Authentication is failing")
  IO.puts("3. The API is at a different location")
  IO.puts("")

  # Test REST API v1 as fallback
  IO.puts("Testing REST API v1 (legacy)...")
  auth = Base.encode64("#{username}:#{api_token}")
  headers = [
    {"Authorization", "Basic #{auth}"},
    {"Accept", "application/json"}
  ]

  v1_url = "#{confluence_url}/rest/api/content?limit=1"
  case HTTPoison.get(v1_url, headers) do
    {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
      IO.puts("✓ REST API v1 is working at /rest/api/content")
      IO.puts("  However, this library requires API v2.")
      IO.puts("  You may need to upgrade your Confluence instance or use a different library.")

    _ ->
      IO.puts("✗ REST API v1 also not working")
      IO.puts("  Please verify your credentials and URL")
  end
end

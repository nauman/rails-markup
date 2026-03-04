# frozen_string_literal: true

module RailsMarkup
  # Main entry point — starts HTTP server and optionally MCP server.
  # HTTP and MCP share the same Store instance so annotations flow both ways.
  class Server
    attr_reader :store

    def initialize(port: 4747, mcp_only: false)
      @port     = port
      @mcp_only = mcp_only
      @store    = Store.new
    end

    def start
      if @mcp_only
        start_mcp
      else
        start_http_and_mcp
      end
    end

    private

    def start_mcp
      mcp = McpServer.new(store: @store)
      mcp.start
    end

    def start_http_and_mcp
      # Run MCP in a thread so HTTP server can use the main thread
      mcp_thread = Thread.new do
        mcp = McpServer.new(store: @store)
        mcp.start
      rescue IOError
        # stdin closed — MCP client disconnected
      end

      http = HttpServer.new(store: @store, port: @port)
      $stderr.puts "[rails-markup] HTTP server listening on port #{@port}"
      $stderr.puts "[rails-markup] MCP server listening on stdio"
      http.start
    ensure
      mcp_thread&.kill
    end
  end
end

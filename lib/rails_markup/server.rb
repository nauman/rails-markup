# frozen_string_literal: true

require "socket"

module RailsMarkup
  # Main entry point — starts HTTP server and optionally MCP server.
  # HTTP and MCP share the same Store instance so annotations flow both ways.
  # If the HTTP port is already taken, MCP proxies to the existing server.
  class Server
    attr_reader :store

    def initialize(port: 4747, mcp_only: false)
      @port     = port
      @mcp_only = mcp_only
      @store    = Store.new
    end

    def start
      if @mcp_only
        start_mcp_only
      else
        start_http_and_mcp
      end
    end

    private

    def start_mcp(store)
      mcp = McpServer.new(store: store)
      mcp.start
    end

    # MCP-only mode: always proxy to the HTTP server.
    # The user runs `rails-markup server` separately for HTTP.
    def start_mcp_only
      $stderr.puts "[rails-markup] MCP server listening on stdio (proxying to HTTP on port #{@port})"
      proxy = HttpStoreProxy.new(base_url: "http://localhost:#{@port}")
      start_mcp(proxy)
    rescue IOError
      # stdin closed — MCP client disconnected
    end

    def start_http_and_mcp
      if port_available?(@port)
        # We own the port — start HTTP + MCP with shared in-memory store
        http_thread = Thread.new do
          http = HttpServer.new(store: @store, port: @port)
          $stderr.puts "[rails-markup] HTTP server listening on port #{@port}"
          http.start
        end

        $stderr.puts "[rails-markup] MCP server listening on stdio"
        start_mcp(@store)
      else
        # Port is taken — proxy MCP reads/writes to the existing HTTP server
        $stderr.puts "[rails-markup] Port #{@port} in use — MCP proxying to existing server"
        $stderr.puts "[rails-markup] MCP server listening on stdio"
        proxy = HttpStoreProxy.new(base_url: "http://localhost:#{@port}")
        start_mcp(proxy)
      end
    rescue IOError
      # stdin closed — MCP client disconnected
    end

    def port_available?(port)
      server = TCPServer.new("0.0.0.0", port)
      server.close
      true
    rescue Errno::EADDRINUSE
      false
    end
  end
end

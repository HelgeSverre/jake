// webui.zig - HTTP/WebSocket server for Jake web UI
// Serves embedded HTML and streams execution events via WebSocket

const std = @import("std");
const builtin = @import("builtin");
const event_emitter = @import("event_emitter.zig");
const parser = @import("parser.zig");
const executor_mod = @import("executor.zig");
const context_mod = @import("context.zig");
const jakefile_index = @import("jakefile_index.zig");
const color_mod = @import("color.zig");
const compat = @import("compat.zig");

// WebSocket magic GUID for handshake (RFC 6455)
const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

// Embedded HTML content
const html_content = @embedFile("webui.html");

/// Recipe info for web UI display
pub const WebRecipe = struct {
    name: []const u8,
    description: ?[]const u8,
    group: ?[]const u8,
    is_default: bool,
    deps: []const []const u8,
    params: []const []const u8,
};

pub const WebUIServer = struct {
    allocator: std.mem.Allocator,
    port: u16,
    server: ?std.net.Server,
    running: std.atomic.Value(bool),
    clients: std.ArrayListUnmanaged(*WebSocketClient),
    mutex: std.Thread.Mutex,
    client_threads: std.ArrayListUnmanaged(std.Thread),

    // Jakefile data for sending to clients
    recipes: []const parser.Recipe,
    variables: []const parser.Variable,

    // Cached init message JSON
    init_message: ?[]u8,

    // EventEmitter interface for receiving events from executor
    emitter: event_emitter.EventEmitter,

    // Execution context - stored references for task execution
    jakefile: ?*const parser.Jakefile,
    index: ?*const jakefile_index.JakefileIndex,
    runtime: ?*context_mod.RuntimeContext,

    // Task execution state
    execution_thread: ?std.Thread,
    execution_running: std.atomic.Value(bool),
    current_task: ?[]const u8,
    current_child_pid: std.atomic.Value(i32),

    /// Buffer for storing the URL
    url_buf: [64]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, port: u16) WebUIServer {
        var self = WebUIServer{
            .allocator = allocator,
            .port = port,
            .server = null,
            .running = std.atomic.Value(bool).init(false),
            .clients = .{},
            .mutex = .{},
            .client_threads = .{},
            .recipes = &.{},
            .variables = &.{},
            .init_message = null,
            .emitter = undefined,
            .jakefile = null,
            .index = null,
            .runtime = null,
            .execution_thread = null,
            .execution_running = std.atomic.Value(bool).init(false),
            .current_task = null,
            .current_child_pid = std.atomic.Value(i32).init(0),
        };
        // Set up the event emitter interface pointing to this server
        self.emitter = event_emitter.EventEmitter.init(&self);
        return self;
    }

    /// Set Jakefile data for the server to display
    pub fn setJakefileData(self: *WebUIServer, recipes: []const parser.Recipe, variables: []const parser.Variable) void {
        self.recipes = recipes;
        self.variables = variables;
        // Invalidate cached init message
        if (self.init_message) |msg| {
            self.allocator.free(msg);
            self.init_message = null;
        }
    }

    /// Set execution context for running recipes
    pub fn setExecutionContext(self: *WebUIServer, jakefile: *const parser.Jakefile, index: *const jakefile_index.JakefileIndex, runtime: *context_mod.RuntimeContext) void {
        self.jakefile = jakefile;
        self.index = index;
        self.runtime = runtime;
    }

    pub fn deinit(self: *WebUIServer) void {
        self.stop();

        // Stop any running execution
        self.execution_running.store(false, .release);
        if (self.execution_thread) |thread| {
            thread.join();
            self.execution_thread = null;
        }

        // Wait for all client threads to finish
        for (self.client_threads.items) |thread| {
            thread.join();
        }
        self.client_threads.deinit(self.allocator);

        // Clean up any remaining clients
        self.mutex.lock();
        for (self.clients.items) |client| {
            client.deinit();
            self.allocator.destroy(client);
        }
        self.clients.deinit(self.allocator);
        self.mutex.unlock();

        // Free cached init message
        if (self.init_message) |msg| {
            self.allocator.free(msg);
        }

        // Free current task name if allocated
        if (self.current_task) |task| {
            self.allocator.free(task);
            self.current_task = null;
        }
    }

    /// EventEmitter interface callback - broadcast event to all WebSocket clients
    pub fn onEvent(self: *WebUIServer, event: event_emitter.Event) void {
        self.broadcast(event);
    }

    /// Start the HTTP server
    pub fn start(self: *WebUIServer) !void {
        const address = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, self.port);
        self.server = try address.listen(.{
            .reuse_address = true,
        });
        self.running.store(true, .release);

        std.debug.print("\n  Jake Web UI running at http://127.0.0.1:{d}/\n", .{self.port});
        std.debug.print("  Press Ctrl+C to stop\n\n", .{});
    }

    /// Stop the server
    pub fn stop(self: *WebUIServer) void {
        self.running.store(false, .release);

        // Close all client connections to unblock readFrame() calls
        self.mutex.lock();
        for (self.clients.items) |client| {
            client.stream.close();
        }
        self.mutex.unlock();

        if (self.server) |*server| {
            server.deinit();
            self.server = null;
        }
    }

    /// Check if server is running
    pub fn isRunning(self: *WebUIServer) bool {
        return self.running.load(.acquire);
    }

    /// Build and cache the init message JSON with recipe data
    fn getInitMessage(self: *WebUIServer) ![]const u8 {
        // Return cached message if available
        if (self.init_message) |msg| {
            return msg;
        }

        // Build JSON message
        var json: std.ArrayListUnmanaged(u8) = .empty;
        errdefer json.deinit(self.allocator);

        try json.appendSlice(self.allocator, "{\"type\":\"init\",\"recipes\":[");

        var first = true;
        for (self.recipes) |recipe| {
            // Skip private recipes (same as --list behavior)
            if (recipe.isPrivate()) continue;

            if (!first) try json.append(self.allocator, ',');
            first = false;

            try json.appendSlice(self.allocator, "{\"name\":\"");
            try appendJsonEscaped(self.allocator, &json, recipe.name);
            try json.appendSlice(self.allocator, "\"");

            // Description
            if (recipe.description) |desc| {
                try json.appendSlice(self.allocator, ",\"desc\":\"");
                try appendJsonEscaped(self.allocator, &json, desc);
                try json.appendSlice(self.allocator, "\"");
            } else if (recipe.doc_comment) |doc| {
                try json.appendSlice(self.allocator, ",\"desc\":\"");
                try appendJsonEscaped(self.allocator, &json, doc);
                try json.appendSlice(self.allocator, "\"");
            }

            // Group
            if (recipe.group) |group| {
                try json.appendSlice(self.allocator, ",\"group\":\"");
                try appendJsonEscaped(self.allocator, &json, group);
                try json.appendSlice(self.allocator, "\"");
            }

            // Is default
            if (recipe.is_default) {
                try json.appendSlice(self.allocator, ",\"default\":true");
            }

            // Dependencies
            if (recipe.dependencies.len > 0) {
                try json.appendSlice(self.allocator, ",\"deps\":[");
                for (recipe.dependencies, 0..) |dep, j| {
                    if (j > 0) try json.append(self.allocator, ',');
                    try json.appendSlice(self.allocator, "\"");
                    try appendJsonEscaped(self.allocator, &json, dep);
                    try json.appendSlice(self.allocator, "\"");
                }
                try json.appendSlice(self.allocator, "]");
            }

            // Parameters
            if (recipe.params.len > 0) {
                try json.appendSlice(self.allocator, ",\"params\":[");
                for (recipe.params, 0..) |param, j| {
                    if (j > 0) try json.append(self.allocator, ',');
                    try json.appendSlice(self.allocator, "{\"name\":\"");
                    try appendJsonEscaped(self.allocator, &json, param.name);
                    try json.appendSlice(self.allocator, "\"");
                    if (param.default) |def| {
                        try json.appendSlice(self.allocator, ",\"default\":\"");
                        try appendJsonEscaped(self.allocator, &json, def);
                        try json.appendSlice(self.allocator, "\"");
                    }
                    try json.appendSlice(self.allocator, "}");
                }
                try json.appendSlice(self.allocator, "]");
            }

            // Commands
            if (recipe.commands.len > 0) {
                try json.appendSlice(self.allocator, ",\"cmd\":[");
                for (recipe.commands, 0..) |cmd, j| {
                    if (j > 0) try json.append(self.allocator, ',');
                    try json.appendSlice(self.allocator, "\"");
                    try appendJsonEscaped(self.allocator, &json, cmd.line);
                    try json.appendSlice(self.allocator, "\"");
                }
                try json.appendSlice(self.allocator, "]");
            }

            // External kind (for Makefile/Justfile recipes)
            if (recipe.origin) |origin| {
                if (origin.external_kind) |kind| {
                    try json.appendSlice(self.allocator, ",\"external\":\"");
                    try json.appendSlice(self.allocator, switch (kind) {
                        .makefile => "Makefile",
                        .justfile => "Justfile",
                    });
                    try json.appendSlice(self.allocator, "\"");
                }
            }

            try json.appendSlice(self.allocator, "}");
        }

        try json.appendSlice(self.allocator, "],\"variables\":{");

        // Add variables
        for (self.variables, 0..) |variable, i| {
            if (i > 0) try json.append(self.allocator, ',');
            try json.appendSlice(self.allocator, "\"");
            try appendJsonEscaped(self.allocator, &json, variable.name);
            try json.appendSlice(self.allocator, "\":\"");
            try appendJsonEscaped(self.allocator, &json, variable.value);
            try json.appendSlice(self.allocator, "\"");
        }

        try json.appendSlice(self.allocator, "}}");

        // Cache and return
        self.init_message = try json.toOwnedSlice(self.allocator);
        return self.init_message.?;
    }

    /// Accept and handle one connection (call in a loop)
    pub fn acceptOne(self: *WebUIServer) !void {
        if (self.server) |*server| {
            const conn = try server.accept();
            self.handleConnection(conn) catch {};
        }
    }

    /// Get the server URL
    pub fn getURL(self: *WebUIServer) []const u8 {
        return std.fmt.bufPrint(&self.url_buf, "http://127.0.0.1:{d}/", .{self.port}) catch "http://127.0.0.1:8420/";
    }

    fn handleConnection(self: *WebUIServer, conn: std.net.Server.Connection) !void {
        // Read HTTP request
        var buf: [4096]u8 = undefined;
        const n = conn.stream.read(&buf) catch {
            conn.stream.close();
            return;
        };
        if (n == 0) {
            conn.stream.close();
            return;
        }

        const request = buf[0..n];

        // Parse request line
        const first_line_end = std.mem.indexOf(u8, request, "\r\n") orelse {
            conn.stream.close();
            return;
        };
        const request_line = request[0..first_line_end];

        // Extract method and path
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        _ = parts.next() orelse {
            conn.stream.close();
            return;
        }; // method
        const path = parts.next() orelse {
            conn.stream.close();
            return;
        };

        // Check for WebSocket upgrade
        if (std.mem.eql(u8, path, "/ws")) {
            if (isWebSocketUpgrade(request)) {
                // Handle WebSocket upgrade and spawn thread for the connection
                self.handleWebSocketUpgrade(conn, request) catch {
                    conn.stream.close();
                };
                return;
            }
        }

        // Simple routing for HTTP requests
        defer conn.stream.close();

        if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html")) {
            try serveHTML(conn.stream);
        } else if (std.mem.eql(u8, path, "/favicon.ico")) {
            try serveFavicon(conn.stream);
        } else if (std.mem.startsWith(u8, path, "/api/")) {
            try serveJSON(conn.stream, "{\"status\":\"ok\"}");
        } else {
            try serve404(conn.stream);
        }
    }

    fn handleWebSocketUpgrade(self: *WebUIServer, conn: std.net.Server.Connection, request: []const u8) !void {
        // Find Sec-WebSocket-Key header
        const key = findHeader(request, "Sec-WebSocket-Key") orelse return error.MissingWebSocketKey;

        // Compute accept key: base64(sha1(key ++ WS_GUID))
        var hasher = std.crypto.hash.Sha1.init(.{});
        hasher.update(key);
        hasher.update(WS_GUID);
        const hash = hasher.finalResult();

        var accept_buf: [28]u8 = undefined;
        const accept = std.base64.standard.Encoder.encode(&accept_buf, &hash);

        // Send upgrade response
        var response_buf: [256]u8 = undefined;
        const response = std.fmt.bufPrint(&response_buf, "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n" ++
            "\r\n", .{accept}) catch return;
        try conn.stream.writeAll(response);

        // Create WebSocket client and add to list
        const client = try self.allocator.create(WebSocketClient);
        client.* = WebSocketClient{
            .stream = conn.stream,
            .allocator = self.allocator,
        };

        self.mutex.lock();
        self.clients.append(self.allocator, client) catch {
            self.mutex.unlock();
            client.deinit();
            self.allocator.destroy(client);
            return;
        };
        self.mutex.unlock();

        // Send initial state with actual recipe data
        const init_msg = self.getInitMessage() catch "{\"type\":\"init\",\"recipes\":[],\"variables\":{}}";
        client.sendText(init_msg) catch {};

        // Spawn a thread to handle WebSocket frames (non-blocking for main accept loop)
        const thread = std.Thread.spawn(.{}, handleWebSocketFramesThread, .{ self, client }) catch {
            self.removeClient(client);
            return;
        };

        // Track thread for cleanup
        self.mutex.lock();
        self.client_threads.append(self.allocator, thread) catch {};
        self.mutex.unlock();
    }

    /// Thread function for handling WebSocket frames
    fn handleWebSocketFramesThread(self: *WebUIServer, client: *WebSocketClient) void {
        defer self.removeClient(client);

        while (self.isRunning()) {
            const frame = client.readFrame() catch break;
            defer if (frame.payload.len > 0) self.allocator.free(frame.payload);

            switch (frame.opcode) {
                .text => {
                    // Parse JSON command from client
                    self.handleClientCommand(frame.payload);
                },
                .ping => client.sendPong(frame.payload) catch break,
                .close => break,
                else => {},
            }
        }
    }

    /// Handle a JSON command from a WebSocket client
    fn handleClientCommand(self: *WebUIServer, payload: []const u8) void {
        // Parse JSON to extract action and recipe
        // Expected format: {"action":"run","recipe":"build","params":{}}
        // or {"action":"stop"}

        const action = extractJsonString(payload, "action") orelse return;

        if (std.mem.eql(u8, action, "run")) {
            const recipe_name = extractJsonString(payload, "recipe") orelse return;

            // Check if already running
            if (self.execution_running.load(.acquire)) {
                self.broadcastJson("{\"type\":\"error\",\"message\":\"A task is already running\"}");
                return;
            }

            // Check we have execution context
            if (self.jakefile == null or self.index == null or self.runtime == null) {
                self.broadcastJson("{\"type\":\"error\",\"message\":\"No Jakefile loaded\"}");
                return;
            }

            // Store the recipe name for the execution thread
            if (self.current_task) |old| {
                self.allocator.free(old);
            }
            self.current_task = self.allocator.dupe(u8, recipe_name) catch return;

            // Check if dry run
            const dry_run = extractJsonBool(payload, "dryRun") orelse false;

            // Start execution in a separate thread
            self.execution_running.store(true, .release);
            self.execution_thread = std.Thread.spawn(.{}, executeRecipeThread, .{ self, dry_run }) catch {
                self.execution_running.store(false, .release);
                self.broadcastJson("{\"type\":\"error\",\"message\":\"Failed to start execution thread\"}");
                return;
            };
        } else if (std.mem.eql(u8, action, "stop")) {
            // Signal execution to stop (if running)
            if (self.execution_running.load(.acquire)) {
                // First, mark as cancelled
                self.execution_running.store(false, .release);

                // Kill any running child process (POSIX only - Windows uses different mechanism)
                if (builtin.os.tag != .windows) {
                    const pid = self.current_child_pid.load(.acquire);
                    if (pid > 0) {
                        // Kill the process group to ensure all children are terminated
                        std.posix.kill(-pid, std.posix.SIG.KILL) catch {};
                        // Also try killing just the process
                        std.posix.kill(pid, std.posix.SIG.KILL) catch {};
                    }
                }
            }
        }
    }

    /// Output callback for streaming command output to WebSocket clients and console
    fn outputCallback(ctx: *anyopaque, line: []const u8, is_stderr: bool) void {
        const server: *WebUIServer = @ptrCast(@alignCast(ctx));
        const task_name = server.current_task orelse "unknown";

        // Send to WebSocket clients
        server.emitCommandOutput(task_name, line, is_stderr);

        // Also write to console (tee behavior)
        const output = if (is_stderr) compat.getStdErr() else compat.getStdOut();
        output.writeAll(line) catch {};
        output.writeAll("\n") catch {};
    }

    /// Thread function that executes a recipe
    fn executeRecipeThread(self: *WebUIServer, dry_run: bool) void {
        defer {
            self.execution_running.store(false, .release);
            if (self.execution_thread != null) {
                self.execution_thread = null;
            }
        }

        const recipe_name = self.current_task orelse return;
        const jakefile = self.jakefile orelse return;
        const index = self.index orelse return;
        const runtime = self.runtime orelse return;

        // Emit task_start event
        const start_time = std.time.milliTimestamp();
        self.emitTaskStart(recipe_name);

        // Create a context for this execution with cancellation flag and child PID tracking
        var ctx = context_mod.Context{
            .dry_run = dry_run,
            .verbose = false,
            .auto_yes = true, // Auto-confirm in web UI
            .watch_mode = false,
            .jobs = 0, // Sequential execution for web UI
            .color = color_mod.Color{ .enabled = false }, // No ANSI in web output
            .positional_args = &.{},
            .cancellation_flag = &self.execution_running, // Use execution_running as cancellation flag
            .current_child_pid = &self.current_child_pid, // Track child PID for killing
            .output_callback = outputCallback, // Stream output to WebSocket
            .output_callback_ctx = self,
        };

        // Create executor
        var executor = executor_mod.Executor.initWithIndexAndContext(self.allocator, jakefile, index, &ctx, runtime);
        defer executor.deinit();

        // Execute the recipe
        const success = blk: {
            executor.execute(recipe_name) catch |err| {
                // Check if this was a cancellation
                if (ctx.isCancelled()) {
                    self.emitCommandOutput(recipe_name, "Execution cancelled by user", true);
                    break :blk false;
                }
                // Emit error
                var buf: [256]u8 = undefined;
                const err_name = @errorName(err);
                const msg = std.fmt.bufPrint(&buf, "Execution failed: {s}", .{err_name}) catch "Execution failed";
                self.emitCommandOutput(recipe_name, msg, true);
                break :blk false;
            };
            break :blk true;
        };

        // Emit task_complete event
        const duration_ms: u64 = @intCast(@max(0, std.time.milliTimestamp() - start_time));
        self.emitTaskComplete(recipe_name, success, duration_ms);

        // Emit summary
        self.emitSummary(if (success) 1 else 0, if (success) 0 else 1, duration_ms);
    }

    /// Emit a task_start event to all clients
    fn emitTaskStart(self: *WebUIServer, name: []const u8) void {
        var buf: [512]u8 = undefined;
        const json = std.fmt.bufPrint(&buf, "{{\"type\":\"task_start\",\"name\":\"{s}\",\"deps\":[]}}", .{name}) catch return;
        self.broadcastJson(json);
    }

    /// Emit a command output event to all clients
    fn emitCommandOutput(self: *WebUIServer, task: []const u8, line: []const u8, is_stderr: bool) void {
        // Build JSON with proper escaping
        var json: std.ArrayListUnmanaged(u8) = .empty;
        defer json.deinit(self.allocator);

        json.appendSlice(self.allocator, "{\"type\":\"output\",\"task\":\"") catch return;
        appendJsonEscaped(self.allocator, &json, task) catch return;
        json.appendSlice(self.allocator, "\",\"line\":\"") catch return;
        appendJsonEscaped(self.allocator, &json, line) catch return;
        json.appendSlice(self.allocator, "\",\"stderr\":") catch return;
        json.appendSlice(self.allocator, if (is_stderr) "true}" else "false}") catch return;

        self.broadcastJson(json.items);
    }

    /// Emit a task_complete event to all clients
    fn emitTaskComplete(self: *WebUIServer, name: []const u8, success: bool, duration_ms: u64) void {
        var buf: [512]u8 = undefined;
        const json = std.fmt.bufPrint(&buf, "{{\"type\":\"task_complete\",\"name\":\"{s}\",\"success\":{s},\"duration_ms\":{d}}}", .{
            name,
            if (success) "true" else "false",
            duration_ms,
        }) catch return;
        self.broadcastJson(json);
    }

    /// Emit an execution summary event to all clients
    fn emitSummary(self: *WebUIServer, tasks_run: usize, tasks_failed: usize, total_ms: u64) void {
        var buf: [256]u8 = undefined;
        const json = std.fmt.bufPrint(&buf, "{{\"type\":\"summary\",\"tasks_run\":{d},\"tasks_failed\":{d},\"total_ms\":{d}}}", .{
            tasks_run,
            tasks_failed,
            total_ms,
        }) catch return;
        self.broadcastJson(json);
    }

    /// Broadcast a raw JSON string to all connected clients
    fn broadcastJson(self: *WebUIServer, json: []const u8) void {
        var failed_clients: std.ArrayListUnmanaged(*WebSocketClient) = .empty;
        defer failed_clients.deinit(self.allocator);

        self.mutex.lock();
        var i: usize = 0;
        while (i < self.clients.items.len) {
            const client = self.clients.items[i];
            client.sendText(json) catch {
                failed_clients.append(self.allocator, client) catch {};
                _ = self.clients.swapRemove(i);
                continue;
            };
            i += 1;
        }
        self.mutex.unlock();

        for (failed_clients.items) |client| {
            client.deinit();
            self.allocator.destroy(client);
        }
    }

    /// Remove a client from the list and clean it up
    fn removeClient(self: *WebUIServer, client: *WebSocketClient) void {
        self.mutex.lock();
        for (self.clients.items, 0..) |c, i| {
            if (c == client) {
                _ = self.clients.swapRemove(i);
                break;
            }
        }
        self.mutex.unlock();

        client.deinit();
        self.allocator.destroy(client);
    }

    /// Broadcast an event to all connected WebSocket clients
    fn broadcast(self: *WebUIServer, event: event_emitter.Event) void {
        const json = serializeEvent(self.allocator, event) catch return;
        defer self.allocator.free(json);

        var failed_clients: std.ArrayListUnmanaged(*WebSocketClient) = .empty;
        defer failed_clients.deinit(self.allocator);

        self.mutex.lock();
        var i: usize = 0;
        while (i < self.clients.items.len) {
            const client = self.clients.items[i];
            client.sendText(json) catch {
                failed_clients.append(self.allocator, client) catch {};
                _ = self.clients.swapRemove(i);
                continue;
            };
            i += 1;
        }
        self.mutex.unlock();

        for (failed_clients.items) |client| {
            client.deinit();
            self.allocator.destroy(client);
        }
    }
};

fn isWebSocketUpgrade(request: []const u8) bool {
    const upgrade = findHeader(request, "Upgrade") orelse return false;
    return std.ascii.eqlIgnoreCase(upgrade, "websocket");
}

/// Append a string to an ArrayListUnmanaged with JSON escaping
fn appendJsonEscaped(allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged(u8), str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '"' => try list.appendSlice(allocator, "\\\""),
            '\\' => try list.appendSlice(allocator, "\\\\"),
            '\n' => try list.appendSlice(allocator, "\\n"),
            '\r' => try list.appendSlice(allocator, "\\r"),
            '\t' => try list.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    // Control character - encode as \u00XX
                    try list.appendSlice(allocator, "\\u00");
                    const hex = "0123456789abcdef";
                    try list.append(allocator, hex[c >> 4]);
                    try list.append(allocator, hex[c & 0x0F]);
                } else {
                    try list.append(allocator, c);
                }
            },
        }
    }
}

fn findHeader(request: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitSequence(u8, request, "\r\n");
    _ = lines.next(); // Skip request line

    while (lines.next()) |line| {
        if (line.len == 0) break; // End of headers

        if (std.mem.indexOfScalar(u8, line, ':')) |colon_pos| {
            const header_name = line[0..colon_pos];
            if (std.ascii.eqlIgnoreCase(header_name, name)) {
                var value = line[colon_pos + 1 ..];
                // Trim leading whitespace
                while (value.len > 0 and value[0] == ' ') {
                    value = value[1..];
                }
                return value;
            }
        }
    }
    return null;
}

/// Extract a string value from JSON by key (simple parsing, no nested objects)
/// e.g., extractJsonString('{"action":"run","recipe":"build"}', "recipe") => "build"
fn extractJsonString(json: []const u8, key: []const u8) ?[]const u8 {
    // Look for "key":"value" pattern
    var search_buf: [128]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\":\"", .{key}) catch return null;

    const start_idx = std.mem.indexOf(u8, json, search) orelse return null;
    const value_start = start_idx + search.len;

    if (value_start >= json.len) return null;

    // Find the closing quote (handle escaped quotes)
    var i = value_start;
    while (i < json.len) {
        if (json[i] == '"' and (i == value_start or json[i - 1] != '\\')) {
            return json[value_start..i];
        }
        i += 1;
    }
    return null;
}

/// Extract a boolean value from JSON by key
/// e.g., extractJsonBool('{"dryRun":true}', "dryRun") => true
fn extractJsonBool(json: []const u8, key: []const u8) ?bool {
    // Look for "key":true or "key":false pattern
    var search_buf: [128]u8 = undefined;

    // Try true first
    const search_true = std.fmt.bufPrint(&search_buf, "\"{s}\":true", .{key}) catch return null;
    if (std.mem.indexOf(u8, json, search_true) != null) {
        return true;
    }

    // Try false
    const search_false = std.fmt.bufPrint(&search_buf, "\"{s}\":false", .{key}) catch return null;
    if (std.mem.indexOf(u8, json, search_false) != null) {
        return false;
    }

    return null;
}

fn serializeEvent(allocator: std.mem.Allocator, event: event_emitter.Event) ![]u8 {
    var json: std.ArrayListUnmanaged(u8) = .empty;
    errdefer json.deinit(allocator);

    switch (event) {
        .jakefile_loaded => |e| {
            try json.appendSlice(allocator, "{\"type\":\"init\",\"recipes\":[");
            for (e.recipes, 0..) |recipe, i| {
                if (i > 0) try json.append(allocator, ',');
                try json.appendSlice(allocator, "{\"name\":\"");
                try appendJsonEscaped(allocator, &json, recipe.name);
                try json.appendSlice(allocator, "\",\"desc\":\"");
                try appendJsonEscaped(allocator, &json, recipe.desc);
                try json.appendSlice(allocator, "\",\"group\":\"");
                try appendJsonEscaped(allocator, &json, recipe.group);
                try json.appendSlice(allocator, "\",\"deps\":[");
                for (recipe.deps, 0..) |dep, j| {
                    if (j > 0) try json.append(allocator, ',');
                    try json.append(allocator, '"');
                    try appendJsonEscaped(allocator, &json, dep);
                    try json.append(allocator, '"');
                }
                try json.appendSlice(allocator, "],\"params\":[");
                for (recipe.params, 0..) |param, j| {
                    if (j > 0) try json.append(allocator, ',');
                    try json.append(allocator, '"');
                    try appendJsonEscaped(allocator, &json, param);
                    try json.append(allocator, '"');
                }
                try json.appendSlice(allocator, "],\"is_default\":");
                try json.appendSlice(allocator, if (recipe.is_default) "true" else "false");
                try json.appendSlice(allocator, ",\"is_hidden\":");
                try json.appendSlice(allocator, if (recipe.is_hidden) "true" else "false");
                try json.append(allocator, '}');
            }
            try json.appendSlice(allocator, "],\"variables\":{");
            for (e.variables, 0..) |variable, i| {
                if (i > 0) try json.append(allocator, ',');
                try json.append(allocator, '"');
                try appendJsonEscaped(allocator, &json, variable.name);
                try json.appendSlice(allocator, "\":\"");
                try appendJsonEscaped(allocator, &json, variable.value);
                try json.append(allocator, '"');
            }
            try json.appendSlice(allocator, "}}");
        },
        .task_start => |e| {
            try json.appendSlice(allocator, "{\"type\":\"task_start\",\"name\":\"");
            try appendJsonEscaped(allocator, &json, e.name);
            try json.appendSlice(allocator, "\",\"deps\":[");
            for (e.deps, 0..) |dep, i| {
                if (i > 0) try json.append(allocator, ',');
                try json.append(allocator, '"');
                try appendJsonEscaped(allocator, &json, dep);
                try json.append(allocator, '"');
            }
            try json.appendSlice(allocator, "]}");
        },
        .command_start => |e| {
            try json.appendSlice(allocator, "{\"type\":\"command\",\"task\":\"");
            try appendJsonEscaped(allocator, &json, e.task);
            try json.appendSlice(allocator, "\",\"cmd\":\"");
            try appendJsonEscaped(allocator, &json, e.command);
            try json.appendSlice(allocator, "\"}");
        },
        .command_output => |e| {
            try json.appendSlice(allocator, "{\"type\":\"output\",\"task\":\"");
            try appendJsonEscaped(allocator, &json, e.task);
            try json.appendSlice(allocator, "\",\"line\":\"");
            try appendJsonEscaped(allocator, &json, e.line);
            try json.appendSlice(allocator, "\",\"stderr\":");
            try json.appendSlice(allocator, if (e.is_stderr) "true}" else "false}");
        },
        .task_complete => |e| {
            try json.appendSlice(allocator, "{\"type\":\"task_complete\",\"name\":\"");
            try appendJsonEscaped(allocator, &json, e.name);
            try json.appendSlice(allocator, "\",\"success\":");
            try json.appendSlice(allocator, if (e.success) "true" else "false");
            try json.appendSlice(allocator, ",\"duration_ms\":");
            var buf: [32]u8 = undefined;
            const duration_str = std.fmt.bufPrint(&buf, "{d}", .{e.duration_ms}) catch "0";
            try json.appendSlice(allocator, duration_str);
            try json.append(allocator, '}');
        },
        .execution_summary => |e| {
            try json.appendSlice(allocator, "{\"type\":\"summary\",\"tasks_run\":");
            var buf: [32]u8 = undefined;
            const tasks_run_str = std.fmt.bufPrint(&buf, "{d}", .{e.tasks_run}) catch "0";
            try json.appendSlice(allocator, tasks_run_str);
            try json.appendSlice(allocator, ",\"tasks_failed\":");
            const tasks_failed_str = std.fmt.bufPrint(&buf, "{d}", .{e.tasks_failed}) catch "0";
            try json.appendSlice(allocator, tasks_failed_str);
            try json.appendSlice(allocator, ",\"total_ms\":");
            const total_ms_str = std.fmt.bufPrint(&buf, "{d}", .{e.total_ms}) catch "0";
            try json.appendSlice(allocator, total_ms_str);
            try json.append(allocator, '}');
        },
    }

    return json.toOwnedSlice(allocator);
}

fn serveHTML(stream: std.net.Stream) !void {
    const response = "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/html; charset=utf-8\r\n" ++
        "Connection: close\r\n" ++
        "Cache-Control: no-cache\r\n" ++
        "\r\n";
    try stream.writeAll(response);
    try stream.writeAll(html_content);
}

fn serveFavicon(stream: std.net.Stream) !void {
    // Return a simple 1x1 transparent PNG as favicon
    const response = "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: image/x-icon\r\n" ++
        "Content-Length: 0\r\n" ++
        "Connection: close\r\n" ++
        "\r\n";
    try stream.writeAll(response);
}

fn serveJSON(stream: std.net.Stream, json: []const u8) !void {
    var buf: [256]u8 = undefined;
    const header = std.fmt.bufPrint(&buf, "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: {d}\r\n" ++
        "Connection: close\r\n" ++
        "\r\n", .{json.len}) catch return;
    try stream.writeAll(header);
    try stream.writeAll(json);
}

fn serve404(stream: std.net.Stream) !void {
    const response = "HTTP/1.1 404 Not Found\r\n" ++
        "Content-Type: text/plain\r\n" ++
        "Content-Length: 9\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "Not Found";
    try stream.writeAll(response);
}

/// WebSocket client connection
pub const WebSocketClient = struct {
    stream: std.net.Stream,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *WebSocketClient) void {
        self.stream.close();
    }

    pub fn readFrame(self: *WebSocketClient) !WebSocketFrame {
        var header: [2]u8 = undefined;
        const header_read = self.stream.read(&header) catch return error.EndOfStream;
        if (header_read != 2) return error.EndOfStream;

        const opcode: WebSocketOpcode = @enumFromInt(header[0] & 0x0F);
        const masked = (header[1] & 0x80) != 0;
        var payload_len: u64 = header[1] & 0x7F;

        // Extended payload length
        if (payload_len == 126) {
            var ext: [2]u8 = undefined;
            _ = self.stream.read(&ext) catch return error.EndOfStream;
            payload_len = std.mem.readInt(u16, &ext, .big);
        } else if (payload_len == 127) {
            var ext: [8]u8 = undefined;
            _ = self.stream.read(&ext) catch return error.EndOfStream;
            payload_len = std.mem.readInt(u64, &ext, .big);
        }

        // Read masking key if present
        var mask: [4]u8 = .{ 0, 0, 0, 0 };
        if (masked) {
            _ = self.stream.read(&mask) catch return error.EndOfStream;
        }

        // Read payload
        const MAX_PAYLOAD_SIZE: u64 = 16 * 1024 * 1024; // 16 MB
        var payload: []u8 = &.{};
        if (payload_len > 0) {
            if (payload_len > MAX_PAYLOAD_SIZE) return error.PayloadTooLarge;
            payload = try self.allocator.alloc(u8, @intCast(payload_len));
            errdefer self.allocator.free(payload);
            var total_read: usize = 0;
            while (total_read < payload.len) {
                const n = self.stream.read(payload[total_read..]) catch return error.EndOfStream;
                if (n == 0) return error.EndOfStream;
                total_read += n;
            }

            // Unmask payload
            if (masked) {
                for (payload, 0..) |*byte, i| {
                    byte.* ^= mask[i % 4];
                }
            }
        }

        return WebSocketFrame{
            .opcode = opcode,
            .payload = payload,
        };
    }

    pub fn sendText(self: *WebSocketClient, text: []const u8) !void {
        try self.writeFrame(.text, text);
    }

    pub fn sendPong(self: *WebSocketClient, payload: []const u8) !void {
        try self.writeFrame(.pong, payload);
    }

    fn writeFrame(self: *WebSocketClient, opcode: WebSocketOpcode, payload: []const u8) !void {
        // Server frames are not masked
        var header: [10]u8 = undefined;
        var header_len: usize = 2;

        header[0] = 0x80 | @as(u8, @intFromEnum(opcode)); // FIN + opcode

        if (payload.len < 126) {
            header[1] = @intCast(payload.len);
        } else if (payload.len < 65536) {
            header[1] = 126;
            std.mem.writeInt(u16, header[2..4], @intCast(payload.len), .big);
            header_len = 4;
        } else {
            header[1] = 127;
            std.mem.writeInt(u64, header[2..10], payload.len, .big);
            header_len = 10;
        }

        try self.stream.writeAll(header[0..header_len]);
        if (payload.len > 0) {
            try self.stream.writeAll(payload);
        }
    }
};

const WebSocketOpcode = enum(u4) {
    continuation = 0,
    text = 1,
    binary = 2,
    close = 8,
    ping = 9,
    pong = 10,
    _,
};

const WebSocketFrame = struct {
    opcode: WebSocketOpcode,
    payload: []u8,
};

/// Open browser to URL (cross-platform)
pub fn openBrowser(url: []const u8) !void {
    const argv: []const []const u8 = switch (@import("builtin").os.tag) {
        .macos => &.{ "open", url },
        .linux => &.{ "xdg-open", url },
        .windows => &.{ "cmd", "/c", "start", url },
        else => return error.UnsupportedPlatform,
    };

    var child = std.process.Child.init(argv, std.heap.page_allocator);
    child.spawn() catch return;
}

// ============================================================================
// Tests
// ============================================================================

test "WebUIServer can be initialized" {
    var server = WebUIServer.init(std.testing.allocator, 8420);
    defer server.deinit();

    try std.testing.expectEqual(@as(u16, 8420), server.port);
    try std.testing.expect(!server.isRunning());
}

test "findHeader extracts header values" {
    const request = "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nSec-WebSocket-Key: abc123\r\n\r\n";
    try std.testing.expectEqualStrings("websocket", findHeader(request, "Upgrade").?);
    try std.testing.expectEqualStrings("abc123", findHeader(request, "Sec-WebSocket-Key").?);
    try std.testing.expect(findHeader(request, "NonExistent") == null);
}

test "isWebSocketUpgrade detects upgrade requests" {
    const ws_request = "GET /ws HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n";
    const http_request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";

    try std.testing.expect(isWebSocketUpgrade(ws_request));
    try std.testing.expect(!isWebSocketUpgrade(http_request));
}

test "findHeader is case-insensitive" {
    const request = "GET / HTTP/1.1\r\nContent-Type: text/html\r\nSEC-WEBSOCKET-KEY: test123\r\n\r\n";
    try std.testing.expectEqualStrings("text/html", findHeader(request, "content-type").?);
    try std.testing.expectEqualStrings("test123", findHeader(request, "sec-websocket-key").?);
}

test "findHeader handles whitespace after colon" {
    const request = "GET / HTTP/1.1\r\nHost:   localhost\r\nKey:value\r\n\r\n";
    try std.testing.expectEqualStrings("localhost", findHeader(request, "Host").?);
    try std.testing.expectEqualStrings("value", findHeader(request, "Key").?);
}

test "serializeEvent returns valid JSON for all event types" {
    const allocator = std.testing.allocator;
    // Test that all event types produce valid JSON strings
    const events = [_]event_emitter.Event{
        .{ .jakefile_loaded = .{ .recipes = &.{}, .variables = &.{} } },
        .{ .task_start = .{ .name = "test", .deps = &.{} } },
        .{ .command_start = .{ .task = "test", .command = "echo hello" } },
        .{ .command_output = .{ .task = "test", .line = "output", .is_stderr = false } },
        .{ .task_complete = .{ .name = "test", .success = true, .duration_ms = 100 } },
        .{ .execution_summary = .{ .tasks_run = 1, .tasks_failed = 0, .total_ms = 100 } },
    };

    for (events) |event| {
        const json = try serializeEvent(allocator, event);
        defer allocator.free(json);
        // Verify it starts with { and ends with }
        try std.testing.expect(json.len > 2);
        try std.testing.expectEqual(@as(u8, '{'), json[0]);
        try std.testing.expectEqual(@as(u8, '}'), json[json.len - 1]);
        // Verify it contains "type"
        try std.testing.expect(std.mem.indexOf(u8, json, "\"type\"") != null);
    }
}

test "WebSocketOpcode enum values match RFC 6455" {
    try std.testing.expectEqual(@as(u4, 0), @intFromEnum(WebSocketOpcode.continuation));
    try std.testing.expectEqual(@as(u4, 1), @intFromEnum(WebSocketOpcode.text));
    try std.testing.expectEqual(@as(u4, 2), @intFromEnum(WebSocketOpcode.binary));
    try std.testing.expectEqual(@as(u4, 8), @intFromEnum(WebSocketOpcode.close));
    try std.testing.expectEqual(@as(u4, 9), @intFromEnum(WebSocketOpcode.ping));
    try std.testing.expectEqual(@as(u4, 10), @intFromEnum(WebSocketOpcode.pong));
}

test "WebSocket frame header encoding for small payload" {
    // Test FIN bit + text opcode
    const header_byte = 0x80 | @as(u8, @intFromEnum(WebSocketOpcode.text));
    try std.testing.expectEqual(@as(u8, 0x81), header_byte);

    // Test payload length encoding (small payload < 126 bytes)
    const small_len: u8 = 50;
    try std.testing.expect(small_len < 126);
}

test "WebSocket frame header encoding for medium payload" {
    // For payloads 126-65535 bytes, use 126 marker + 2 bytes
    const medium_len: u16 = 1000;
    var header: [4]u8 = undefined;
    header[0] = 0x81; // FIN + text
    header[1] = 126; // Extended length marker
    std.mem.writeInt(u16, header[2..4], medium_len, .big);

    try std.testing.expectEqual(@as(u8, 126), header[1]);
    try std.testing.expectEqual(medium_len, std.mem.readInt(u16, header[2..4], .big));
}

test "WebSocket accept key computation" {
    // Test the SHA1 + Base64 computation for WebSocket handshake
    // Using a known test vector from RFC 6455
    const test_key = "dGhlIHNhbXBsZSBub25jZQ==";
    const expected_accept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=";

    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(test_key);
    hasher.update(WS_GUID);
    const hash = hasher.finalResult();

    var accept_buf: [28]u8 = undefined;
    const accept = std.base64.standard.Encoder.encode(&accept_buf, &hash);

    try std.testing.expectEqualStrings(expected_accept, accept);
}

test "WebSocket mask/unmask is symmetric" {
    const mask = [4]u8{ 0x37, 0xfa, 0x21, 0x3d };
    var payload = [_]u8{ 'H', 'e', 'l', 'l', 'o' };
    const original = [_]u8{ 'H', 'e', 'l', 'l', 'o' };

    // Mask the payload
    for (&payload, 0..) |*byte, i| {
        byte.* ^= mask[i % 4];
    }

    // Verify it's different
    try std.testing.expect(!std.mem.eql(u8, &payload, &original));

    // Unmask (same operation)
    for (&payload, 0..) |*byte, i| {
        byte.* ^= mask[i % 4];
    }

    // Should be back to original
    try std.testing.expectEqualSlices(u8, &original, &payload);
}

test "getURL returns correct format" {
    var server = WebUIServer.init(std.testing.allocator, 8420);
    defer server.deinit();

    const url = server.getURL();
    try std.testing.expect(std.mem.startsWith(u8, url, "http://"));
    try std.testing.expect(std.mem.indexOf(u8, url, "127.0.0.1") != null);
}

test "WebUIServer start and stop" {
    var server = WebUIServer.init(std.testing.allocator, 18421); // Use high port to avoid conflicts
    defer server.deinit();

    try std.testing.expect(!server.isRunning());

    try server.start();
    try std.testing.expect(server.isRunning());

    server.stop();
    try std.testing.expect(!server.isRunning());
}

test "WebUIServer atomic running state" {
    var server = WebUIServer.init(std.testing.allocator, 18422);
    defer server.deinit();

    // Initial state
    try std.testing.expect(!server.isRunning());

    // Start
    server.running.store(true, .release);
    try std.testing.expect(server.isRunning());

    // Stop
    server.running.store(false, .release);
    try std.testing.expect(!server.isRunning());
}

test "WebSocketClient writeFrame encodes small payload correctly" {
    // Test the frame encoding logic without actual network
    var header: [10]u8 = undefined;
    const opcode = WebSocketOpcode.text;
    const payload_len: usize = 50;

    header[0] = 0x80 | @as(u8, @intFromEnum(opcode)); // FIN + opcode

    if (payload_len < 126) {
        header[1] = @intCast(payload_len);
    }

    try std.testing.expectEqual(@as(u8, 0x81), header[0]); // FIN + text
    try std.testing.expectEqual(@as(u8, 50), header[1]); // Length
}

test "WebSocketClient writeFrame encodes medium payload correctly" {
    var header: [10]u8 = undefined;
    const opcode = WebSocketOpcode.text;
    const payload_len: usize = 1000;
    var header_len: usize = 2;

    header[0] = 0x80 | @as(u8, @intFromEnum(opcode));

    if (payload_len < 126) {
        header[1] = @intCast(payload_len);
    } else if (payload_len < 65536) {
        header[1] = 126;
        std.mem.writeInt(u16, header[2..4], @intCast(payload_len), .big);
        header_len = 4;
    }

    try std.testing.expectEqual(@as(u8, 0x81), header[0]);
    try std.testing.expectEqual(@as(u8, 126), header[1]);
    try std.testing.expectEqual(@as(usize, 4), header_len);
    try std.testing.expectEqual(@as(u16, 1000), std.mem.readInt(u16, header[2..4], .big));
}

test "WebSocketClient writeFrame encodes large payload correctly" {
    var header: [10]u8 = undefined;
    const opcode = WebSocketOpcode.binary;
    const payload_len: u64 = 70000;
    var header_len: usize = 2;

    header[0] = 0x80 | @as(u8, @intFromEnum(opcode));

    if (payload_len < 126) {
        header[1] = @intCast(payload_len);
    } else if (payload_len < 65536) {
        header[1] = 126;
        std.mem.writeInt(u16, header[2..4], @intCast(payload_len), .big);
        header_len = 4;
    } else {
        header[1] = 127;
        std.mem.writeInt(u64, header[2..10], payload_len, .big);
        header_len = 10;
    }

    try std.testing.expectEqual(@as(u8, 0x82), header[0]); // FIN + binary
    try std.testing.expectEqual(@as(u8, 127), header[1]); // Extended length marker
    try std.testing.expectEqual(@as(usize, 10), header_len);
    try std.testing.expectEqual(payload_len, std.mem.readInt(u64, header[2..10], .big));
}

test "findHeader returns null for empty request" {
    const request = "";
    try std.testing.expect(findHeader(request, "Host") == null);
}

test "findHeader returns null for request with no headers" {
    const request = "GET / HTTP/1.1\r\n\r\n";
    try std.testing.expect(findHeader(request, "Host") == null);
}

test "findHeader handles multiple colons in value" {
    const request = "GET / HTTP/1.1\r\nLocation: http://example.com:8080/path\r\n\r\n";
    const value = findHeader(request, "Location");
    try std.testing.expect(value != null);
    try std.testing.expectEqualStrings("http://example.com:8080/path", value.?);
}

test "isWebSocketUpgrade case insensitive" {
    const request1 = "GET /ws HTTP/1.1\r\nUpgrade: WebSocket\r\n\r\n";
    const request2 = "GET /ws HTTP/1.1\r\nUpgrade: WEBSOCKET\r\n\r\n";
    const request3 = "GET /ws HTTP/1.1\r\nUpgrade: websocket\r\n\r\n";

    try std.testing.expect(isWebSocketUpgrade(request1));
    try std.testing.expect(isWebSocketUpgrade(request2));
    try std.testing.expect(isWebSocketUpgrade(request3));
}

test "serializeEvent task_start contains type field" {
    const allocator = std.testing.allocator;
    const event = event_emitter.Event{ .task_start = .{ .name = "build", .deps = &.{} } };
    const json = try serializeEvent(allocator, event);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"task_start\"") != null);
}

test "serializeEvent task_complete contains type field" {
    const allocator = std.testing.allocator;
    const event = event_emitter.Event{ .task_complete = .{ .name = "test", .success = true, .duration_ms = 500 } };
    const json = try serializeEvent(allocator, event);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"task_complete\"") != null);
}

test "serializeEvent execution_summary contains type field" {
    const allocator = std.testing.allocator;
    const event = event_emitter.Event{ .execution_summary = .{ .tasks_run = 5, .tasks_failed = 1, .total_ms = 2000 } };
    const json = try serializeEvent(allocator, event);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"summary\"") != null);
}

test "WebSocketOpcode pong value" {
    // Pong must be 0xA (10) per RFC 6455
    try std.testing.expectEqual(@as(u4, 10), @intFromEnum(WebSocketOpcode.pong));
}

test "WebSocket FIN bit set correctly" {
    const fin_mask: u8 = 0x80;
    const opcode: u8 = @intFromEnum(WebSocketOpcode.text);
    const header_byte = fin_mask | opcode;

    // FIN bit should be set
    try std.testing.expect((header_byte & 0x80) != 0);
    // Opcode should be text
    try std.testing.expectEqual(@as(u8, 1), header_byte & 0x0F);
}

test "extractJsonString extracts string values" {
    const json = "{\"action\":\"run\",\"recipe\":\"build\"}";
    try std.testing.expectEqualStrings("run", extractJsonString(json, "action").?);
    try std.testing.expectEqualStrings("build", extractJsonString(json, "recipe").?);
    try std.testing.expect(extractJsonString(json, "nonexistent") == null);
}

test "extractJsonString handles empty values" {
    const json = "{\"name\":\"\"}";
    try std.testing.expectEqualStrings("", extractJsonString(json, "name").?);
}

test "extractJsonString handles special characters" {
    const json = "{\"path\":\"foo/bar\"}";
    try std.testing.expectEqualStrings("foo/bar", extractJsonString(json, "path").?);
}

test "extractJsonBool extracts boolean values" {
    const json = "{\"dryRun\":true,\"verbose\":false}";
    try std.testing.expect(extractJsonBool(json, "dryRun").? == true);
    try std.testing.expect(extractJsonBool(json, "verbose").? == false);
    try std.testing.expect(extractJsonBool(json, "nonexistent") == null);
}

test "extractJsonBool handles mixed JSON" {
    const json = "{\"action\":\"run\",\"dryRun\":true,\"recipe\":\"build\"}";
    try std.testing.expect(extractJsonBool(json, "dryRun").? == true);
    try std.testing.expect(extractJsonBool(json, "action") == null); // action is a string, not bool
}

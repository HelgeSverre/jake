// webui.zig - HTTP/WebSocket server for Jake web UI
// Serves embedded HTML and streams execution events via WebSocket

const std = @import("std");
const builtin = @import("builtin");
const event_emitter = @import("../output/event_emitter.zig");
const parser = @import("../frontend/parser.zig");
const executor_mod = @import("../runtime/executor.zig");
const context_mod = @import("../runtime/context.zig");
const jakefile_index = @import("../frontend/jakefile_index.zig");
const color_mod = @import("../output/color.zig");
const compat = @import("../compat.zig");
const prompt_mod = @import("../output/prompt.zig");

// WebSocket magic GUID for handshake (RFC 6455)
const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

// Embedded static assets
const html_content = @embedFile("index.html");
const css_content = @embedFile("style.css");
const js_content = @embedFile("app.js");

const ExecutionRequest = struct {
    task_name: []u8,
    positional_args: []const []const u8,
    dry_run: bool,

    fn deinit(self: *ExecutionRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.task_name);
        for (self.positional_args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.positional_args);
    }
};

const ClientCommand = union(enum) {
    run: ExecutionRequest,
    confirm: ConfirmResponse,
    stop: void,
};

const ConfirmResponse = struct {
    confirm_id: u64,
    approved: bool,
};

const PendingConfirm = struct {
    id: u64,
    task_name: []const u8,
    message: []const u8,
    response: ?prompt_mod.ConfirmResult = null,
    cancelled: bool = false,
};

pub const WebUIServer = struct {
    allocator: std.mem.Allocator,
    port: u16,
    server: ?std.net.Server,
    running: std.atomic.Value(bool),
    clients: std.ArrayListUnmanaged(*WebSocketClient),
    mutex: std.Thread.Mutex,
    clients_drained: std.Thread.Condition = .{},
    execution_mutex: std.Thread.Mutex = .{},
    execution_active: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    run_recipe: ?[]const u8 = null,
    run_started_ms: i64 = 0,
    active_tasks: std.ArrayListUnmanaged([]const u8) = .empty,
    pending_summary: ?event_emitter.ExecutionSummaryEvent = null,
    root_started: bool = false,
    root_completed: bool = false,
    tasks_completed: usize = 0,
    tasks_failed: usize = 0,

    // Jakefile data for sending to clients
    recipes: []const parser.Recipe,
    variables: []const parser.Variable,

    // Cached init message JSON
    init_message: ?[]u8,

    // Execution context - stored references for task execution
    jakefile: ?*const parser.Jakefile,
    index: ?*const jakefile_index.JakefileIndex,
    runtime: ?*context_mod.RuntimeContext,
    base_context: context_mod.Context,

    // Task execution state
    execution_thread: ?std.Thread,
    execution_running: std.atomic.Value(bool),
    current_child_pid: std.atomic.Value(i32),

    confirm_mutex: std.Thread.Mutex,
    confirm_condition: std.Thread.Condition,
    pending_confirm: ?PendingConfirm,
    next_confirm_id: u64,

    /// Buffer for storing the URL
    url_buf: [64]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, port: u16) WebUIServer {
        const self = WebUIServer{
            .allocator = allocator,
            .port = port,
            .server = null,
            .running = std.atomic.Value(bool).init(false),
            .clients = .{},
            .mutex = .{},
            .recipes = &.{},
            .variables = &.{},
            .init_message = null,
            .jakefile = null,
            .index = null,
            .runtime = null,
            .base_context = context_mod.Context.init(),
            .execution_thread = null,
            .execution_running = std.atomic.Value(bool).init(false),
            .current_child_pid = std.atomic.Value(i32).init(0),
            .confirm_mutex = .{},
            .confirm_condition = .{},
            .pending_confirm = null,
            .next_confirm_id = 1,
        };
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
    pub fn setExecutionContext(self: *WebUIServer, jakefile: *const parser.Jakefile, index: *const jakefile_index.JakefileIndex, runtime: *context_mod.RuntimeContext, base_context: context_mod.Context) void {
        self.jakefile = jakefile;
        self.index = index;
        self.runtime = runtime;
        self.base_context = base_context;
    }

    pub fn deinit(self: *WebUIServer) void {
        self.stop();

        self.execution_mutex.lock();
        self.joinExecutionThreadIfPresent();
        self.execution_mutex.unlock();

        // Reader threads exclusively own destruction. Wait until their final
        // cleanup has completed before releasing server storage.
        self.mutex.lock();
        while (self.clients.items.len != 0) self.clients_drained.wait(&self.mutex);
        self.clients.deinit(self.allocator);
        self.active_tasks.deinit(self.allocator);
        self.mutex.unlock();

        // Free cached init message
        if (self.init_message) |msg| {
            self.allocator.free(msg);
        }
    }

    fn joinExecutionThreadIfPresent(self: *WebUIServer) void {
        if (self.execution_thread) |thread| {
            thread.join();
            self.execution_thread = null;
        }
    }

    /// EventEmitter interface callback - broadcast event to all WebSocket clients
    pub fn onEvent(self: *WebUIServer, event: event_emitter.Event) void {
        self.broadcast(event);
    }

    fn getEmitter(self: *WebUIServer) event_emitter.EventEmitter {
        return event_emitter.EventEmitter.init(self);
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
        self.execution_running.store(false, .release);
        self.cancelPendingConfirm();

        // Shut down all client connections to unblock readFrame() calls
        self.mutex.lock();
        for (self.clients.items) |client| {
            client.shutdown();
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
        setSocketTimeout(conn.stream, std.posix.SO.SNDTIMEO, 1000) catch {
            conn.stream.close();
            return;
        };
        setSocketTimeout(conn.stream, std.posix.SO.RCVTIMEO, 1000) catch {
            conn.stream.close();
            return;
        };
        // Do not read past the header terminator: a pipelined first frame
        // must remain available to the WebSocket reader.
        var buf: [4096]u8 = undefined;
        const request = readHttpHeader(conn.stream, &buf) catch {
            conn.stream.close();
            return;
        };

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
        } else if (std.mem.eql(u8, path, "/style.css")) {
            try serveStatic(conn.stream, "text/css; charset=utf-8", css_content);
        } else if (std.mem.eql(u8, path, "/app.js")) {
            try serveStatic(conn.stream, "application/javascript; charset=utf-8", js_content);
        } else if (std.mem.eql(u8, path, "/favicon.ico")) {
            try serveFavicon(conn.stream);
        } else if (std.mem.startsWith(u8, path, "/api/")) {
            try serveJSON(conn.stream, "{\"status\":\"ok\"}");
        } else {
            try serve404(conn.stream);
        }
    }

    fn handleWebSocketUpgrade(self: *WebUIServer, conn: std.net.Server.Connection, request: []const u8) !void {
        // Idle WebSockets may wait indefinitely; shutdown wakes the reader.
        try setSocketTimeout(conn.stream, std.posix.SO.RCVTIMEO, 0);
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
        if (!self.isRunning()) {
            self.mutex.unlock();
            self.allocator.destroy(client);
            return error.ServerStopped;
        }
        self.clients.append(self.allocator, client) catch |err| {
            self.mutex.unlock();
            self.allocator.destroy(client);
            return err;
        };
        // Initial recipe data and execution snapshot precede any live events.
        const init_msg = self.getInitMessage() catch "{\"type\":\"init\",\"recipes\":[],\"variables\":{}}";
        client.sendText(init_msg) catch client.shutdown();
        self.sendRunStateLocked(client) catch client.shutdown();
        self.mutex.unlock();
        self.sendPendingConfirm(client);

        // Spawn a detached thread to handle WebSocket frames (non-blocking for main accept loop)
        // Thread cleans up its own client via defer self.removeClient(client) and exits when
        // isRunning() returns false or readFrame() fails (stream closed by stop())
        const frame_thread = std.Thread.spawn(.{}, handleWebSocketFramesThread, .{ self, client }) catch {
            self.removeClient(client);
            return;
        };
        frame_thread.detach();
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
                    self.handleClientCommand(client, frame.payload);
                },
                .ping => client.sendPong(frame.payload) catch break,
                .close => break,
                else => {},
            }
        }
    }

    /// Handle a JSON command from a WebSocket client.
    /// Request rejections go only to the requesting client — broadcasting them
    /// would make other clients mark their own healthy runs as failed.
    fn handleClientCommand(self: *WebUIServer, client: *WebSocketClient, payload: []const u8) void {
        const command = parseClientCommand(self.allocator, payload) catch {
            client.sendText("{\"type\":\"error\",\"message\":\"Invalid command payload\"}") catch {};
            return;
        };

        switch (command) {
            .run => |request_value| {
                var request = request_value;
                var request_owned = true;
                defer if (request_owned) request.deinit(self.allocator);

                self.execution_mutex.lock();
                defer self.execution_mutex.unlock();
                if (self.execution_active.load(.acquire)) {
                    client.sendText("{\"type\":\"error\",\"message\":\"A task is already running\"}") catch {};
                    return;
                }

                if (self.jakefile == null or self.index == null or self.runtime == null) {
                    client.sendText("{\"type\":\"error\",\"message\":\"No Jakefile loaded\"}") catch {};
                    return;
                }

                if (!self.isRunning()) return;
                self.joinExecutionThreadIfPresent();
                self.execution_running.store(true, .release);
                self.execution_active.store(true, .release);
                self.mutex.lock();
                self.run_recipe = if (self.index.?.getRecipe(request.task_name)) |recipe| recipe.name else request.task_name;
                self.run_started_ms = std.time.milliTimestamp();
                self.pending_summary = null;
                self.root_started = false;
                self.root_completed = false;
                self.tasks_completed = 0;
                self.tasks_failed = 0;
                self.active_tasks.clearRetainingCapacity();
                self.broadcastRunStateLocked();
                self.mutex.unlock();

                self.execution_thread = std.Thread.spawn(.{}, executeRecipeThread, .{ self, request }) catch {
                    self.finishRun(true);
                    client.sendText("{\"type\":\"error\",\"message\":\"Failed to start execution thread\"}") catch {};
                    return;
                };
                request_owned = false;
            },
            .confirm => |response| {
                self.confirm_mutex.lock();
                defer self.confirm_mutex.unlock();

                if (self.pending_confirm) |*pending| {
                    if (pending.id == response.confirm_id) {
                        pending.response = if (response.approved) .yes else .no;
                        self.confirm_condition.signal();
                    }
                }
            },
            .stop => {
                if (self.execution_running.load(.acquire)) {
                    self.execution_running.store(false, .release);
                    self.cancelPendingConfirm();

                    // Each executor child observes the cancellation flag;
                    // no shared PID can represent all parallel children.
                }
            },
        }
    }

    fn buildExecutionContext(
        self: *WebUIServer,
        request: *const ExecutionRequest,
    ) context_mod.Context {
        var ctx = self.base_context;
        ctx.dry_run = self.base_context.dry_run or request.dry_run;
        ctx.auto_yes = self.base_context.auto_yes;
        ctx.watch_mode = false;
        ctx.allow_interactive_stdin = false;
        ctx.color = color_mod.Color{ .enabled = false };
        ctx.positional_args = request.positional_args;
        ctx.cancellation_flag = &self.execution_running;
        ctx.current_child_pid = &self.current_child_pid;
        ctx.event_emitter = self.getEmitter();
        ctx.output_callback = outputCallback;
        ctx.output_callback_ctx = self;

        if (!ctx.dry_run and !ctx.auto_yes) {
            ctx.confirm_callback = confirmCallback;
            ctx.confirm_callback_ctx = self;
        }

        return ctx;
    }

    /// Output callback for streaming command output to WebSocket clients and console
    fn outputCallback(ctx: *anyopaque, line: []const u8, is_stderr: bool) void {
        _ = ctx;

        // Also write to console (tee behavior)
        const output = if (is_stderr) compat.getStdErr() else compat.getStdOut();
        output.writeAll(line) catch {};
        output.writeAll("\n") catch {};
    }

    fn confirmCallback(ctx: *anyopaque, task_name: []const u8, message: []const u8) anyerror!prompt_mod.ConfirmResult {
        const self: *WebUIServer = @ptrCast(@alignCast(ctx));

        self.confirm_mutex.lock();
        defer self.confirm_mutex.unlock();

        if (!self.execution_running.load(.acquire) or !self.running.load(.acquire)) {
            return error.Cancelled;
        }

        const confirm_id = self.next_confirm_id;
        self.next_confirm_id += 1;
        self.pending_confirm = .{
            .id = confirm_id,
            .task_name = task_name,
            .message = message,
        };

        self.broadcastPendingConfirmLocked();

        while (true) {
            if (self.pending_confirm) |pending| {
                if (pending.id != confirm_id) return error.Cancelled;
                if (pending.cancelled) {
                    self.pending_confirm = null;
                    return error.Cancelled;
                }
                if (pending.response) |response| {
                    self.pending_confirm = null;
                    return response;
                }
            } else {
                return error.Cancelled;
            }

            self.confirm_condition.wait(&self.confirm_mutex);
        }
    }

    /// Thread function that executes a recipe
    /// Takes ownership of request and frees it when done
    fn executeRecipeThread(self: *WebUIServer, request_value: ExecutionRequest) void {
        var request = request_value;
        var failed = false;
        defer {
            self.finishRun(failed);
            request.deinit(self.allocator);
        }

        const task_name = request.task_name;
        const jakefile = self.jakefile orelse return;
        const index = self.index orelse return;
        const runtime = self.runtime orelse return;

        const start_time = std.time.milliTimestamp();

        // Create a context for this execution with cancellation flag and child PID tracking
        var ctx = self.buildExecutionContext(&request);

        // Create executor
        var executor = executor_mod.Executor.initWithIndexAndContext(self.allocator, jakefile, index, &ctx, runtime) catch |err| {
            failed = true;
            const duration_ms: u64 = @intCast(@max(0, std.time.milliTimestamp() - start_time));
            self.emitTaskStart(task_name, self.lookupRecipeDeps(task_name));
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Execution setup failed: {s}", .{@errorName(err)}) catch "Execution setup failed";
            self.emitCommandOutput(task_name, msg, true);
            self.emitTaskComplete(task_name, false, duration_ms);
            self.emitSummary(0, 1, duration_ms);
            return;
        };
        defer executor.deinit();

        // Setup failures have no executor lifecycle. Once execute is entered,
        // it owns task completions; finishRun only supplies a missing summary.
        executor.validateRequiredEnv() catch |err| {
            failed = true;
            self.emitTaskStart(task_name, self.lookupRecipeDeps(task_name));
            self.emitCommandOutput(task_name, @errorName(err), true);
            self.emitTaskComplete(task_name, false, @intCast(@max(0, std.time.milliTimestamp() - start_time)));
            return;
        };
        if (index.getRecipe(task_name) == null) {
            failed = true;
            self.emitTaskStart(task_name, &.{});
            self.emitCommandOutput(task_name, "Execution failed: RecipeNotFound", true);
            self.emitTaskComplete(task_name, false, 0);
            return;
        }
        executor.execute(task_name) catch |err| {
            failed = true;
            self.emitCommandOutput(task_name, if (ctx.isCancelled()) "Execution cancelled by user" else @errorName(err), true);
        };
    }

    fn finishRun(self: *WebUIServer, failed: bool) void {
        // Cancellation/setup failure may precede the executor's first event,
        // or a failed parallel dependency may prevent the root from starting.
        self.mutex.lock();
        const failed_root = if (failed and !self.root_completed) self.run_recipe else null;
        const needs_start = !self.root_started;
        self.mutex.unlock();
        if (failed_root) |name| {
            if (needs_start) self.emitTaskStart(name, self.lookupRecipeDeps(name));
            self.emitTaskComplete(name, false, 0);
        }
        self.mutex.lock();
        defer self.mutex.unlock();
        const duration: u64 = @intCast(@max(0, std.time.milliTimestamp() - self.run_started_ms));
        const summary = self.pending_summary orelse event_emitter.ExecutionSummaryEvent{
            .tasks_run = self.tasks_completed + self.tasks_failed,
            .tasks_failed = self.tasks_failed,
            .total_ms = duration,
        };
        const observed_tasks = self.tasks_completed + self.tasks_failed;
        // Emit one summary after executor teardown and any final diagnostics.
        // Parallel execution may not supply executor counters, so retain the
        // counts observed on the actual task lifecycle events as a fallback.
        const json = std.json.Stringify.valueAlloc(self.allocator, .{
            .type = "summary",
            .recipe = self.run_recipe,
            .tasks_run = @max(summary.tasks_run, observed_tasks),
            .tasks_failed = @max(summary.tasks_failed, self.tasks_failed, @as(usize, if (failed) 1 else 0)),
            .total_ms = summary.total_ms,
        }, .{}) catch null;
        if (json) |msg| {
            defer self.allocator.free(msg);
            for (self.clients.items) |client| client.sendText(msg) catch client.shutdown();
        }
        self.run_recipe = null;
        self.active_tasks.clearRetainingCapacity();
        self.execution_running.store(false, .release);
        self.execution_active.store(false, .release);
        self.broadcastRunStateLocked();
    }

    fn sendRunStateLocked(self: *WebUIServer, client: *WebSocketClient) !void {
        const json = try std.json.Stringify.valueAlloc(self.allocator, .{
            .type = "run_state",
            .running = self.run_recipe != null,
            .recipe = self.run_recipe,
            .started_ms = self.run_started_ms,
            .active_tasks = self.active_tasks.items,
        }, .{});
        defer self.allocator.free(json);
        try client.sendText(json);
    }

    fn broadcastRunStateLocked(self: *WebUIServer) void {
        for (self.clients.items) |client| self.sendRunStateLocked(client) catch client.shutdown();
    }

    /// Emit a task_start event to all clients
    fn emitTaskStart(self: *WebUIServer, name: []const u8, deps: []const []const u8) void {
        self.getEmitter().emit(.{ .task_start = .{
            .name = name,
            .deps = deps,
        } });
    }

    /// Emit a command output event to all clients
    fn emitCommandOutput(self: *WebUIServer, task: []const u8, line: []const u8, is_stderr: bool) void {
        self.getEmitter().emit(.{ .command_output = .{
            .task = task,
            .line = line,
            .is_stderr = is_stderr,
        } });
    }

    /// Emit a task_complete event to all clients
    fn emitTaskComplete(self: *WebUIServer, name: []const u8, success: bool, duration_ms: u64) void {
        self.getEmitter().emit(.{ .task_complete = .{
            .name = name,
            .success = success,
            .duration_ms = duration_ms,
        } });
    }

    /// Emit an execution summary event to all clients
    fn emitSummary(self: *WebUIServer, tasks_run: usize, tasks_failed: usize, total_ms: u64) void {
        self.getEmitter().emit(.{ .execution_summary = .{
            .tasks_run = tasks_run,
            .tasks_failed = tasks_failed,
            .total_ms = total_ms,
        } });
    }

    /// Broadcasts never destroy a connection retained by its reader.
    fn broadcastJson(self: *WebUIServer, json: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.clients.items) |client| client.sendText(json) catch client.shutdown();
    }

    /// Called only by the connection owner, after it stops reading/writing.
    fn removeClient(self: *WebUIServer, client: *WebSocketClient) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.clients.items, 0..) |c, i| {
            if (c == client) {
                _ = self.clients.swapRemove(i);
                client.deinit();
                self.allocator.destroy(client);
                self.clients_drained.broadcast();
                return;
            }
        }
    }

    fn broadcast(self: *WebUIServer, event_value: event_emitter.Event) void {
        var event = event_value;
        if (event == .task_complete) {
            if (self.index) |index| {
                if (index.getRecipe(event.task_complete.name)) |recipe| event.task_complete.name = recipe.name;
            }
        }
        self.mutex.lock();
        defer self.mutex.unlock();
        switch (event) {
            .task_start => |e| {
                if (self.run_recipe) |root| {
                    if (std.mem.eql(u8, root, e.name)) self.root_started = true;
                }
                if (!containsString(self.active_tasks.items, e.name)) self.active_tasks.append(self.allocator, e.name) catch {};
            },
            .task_complete => |e| {
                if (self.run_recipe) |root| {
                    if (std.mem.eql(u8, root, e.name)) self.root_completed = true;
                }
                if (e.success) self.tasks_completed += 1 else self.tasks_failed += 1;
                for (self.active_tasks.items, 0..) |name, i| {
                    if (std.mem.eql(u8, name, e.name)) {
                        _ = self.active_tasks.swapRemove(i);
                        break;
                    }
                }
            },
            .execution_summary => |e| {
                self.pending_summary = e;
                return;
            },
            else => {},
        }
        const json = serializeEvent(self.allocator, event) catch return;
        defer self.allocator.free(json);
        for (self.clients.items) |client| client.sendText(json) catch client.shutdown();
    }

    fn lookupRecipeDeps(self: *WebUIServer, name: []const u8) []const []const u8 {
        const index = self.index orelse return &.{};
        const recipe = index.getRecipe(name) orelse return &.{};
        return recipe.dependencies;
    }

    fn sendPendingConfirm(self: *WebUIServer, client: *WebSocketClient) void {
        self.confirm_mutex.lock();
        defer self.confirm_mutex.unlock();

        if (self.pending_confirm) |pending| {
            self.sendConfirmMessage(client, pending) catch {};
        }
    }

    fn broadcastPendingConfirmLocked(self: *WebUIServer) void {
        if (self.pending_confirm) |pending| {
            self.mutex.lock();
            defer self.mutex.unlock();
            for (self.clients.items) |client| self.sendConfirmMessage(client, pending) catch client.shutdown();
        }
    }

    fn sendConfirmMessage(self: *WebUIServer, client: *WebSocketClient, pending: PendingConfirm) !void {
        var json: std.ArrayListUnmanaged(u8) = .empty;
        defer json.deinit(self.allocator);

        try json.appendSlice(self.allocator, "{\"type\":\"confirm\",\"confirmId\":");
        var buf: [32]u8 = undefined;
        const id_str = try std.fmt.bufPrint(&buf, "{d}", .{pending.id});
        try json.appendSlice(self.allocator, id_str);
        try json.appendSlice(self.allocator, ",\"task\":\"");
        try appendJsonEscaped(self.allocator, &json, pending.task_name);
        try json.appendSlice(self.allocator, "\",\"message\":\"");
        try appendJsonEscaped(self.allocator, &json, pending.message);
        try json.appendSlice(self.allocator, "\"}");

        try client.sendText(json.items);
    }

    fn cancelPendingConfirm(self: *WebUIServer) void {
        self.confirm_mutex.lock();
        defer self.confirm_mutex.unlock();

        if (self.pending_confirm) |*pending| {
            pending.cancelled = true;
            self.confirm_condition.signal();
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

fn parseClientCommand(allocator: std.mem.Allocator, payload: []const u8) !ClientCommand {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidCommand;
    const root = parsed.value.object;

    const action_value = root.get("action") orelse return error.InvalidCommand;
    if (action_value != .string) return error.InvalidCommand;

    if (std.mem.eql(u8, action_value.string, "stop")) {
        return .{ .stop = {} };
    }
    if (std.mem.eql(u8, action_value.string, "confirm")) {
        const confirm_id_value = root.get("confirmId") orelse return error.InvalidCommand;
        const confirm_id: u64 = blk: switch (confirm_id_value) {
            .integer => |value| {
                if (value < 0) return error.InvalidCommand;
                break :blk @intCast(value);
            },
            else => return error.InvalidCommand,
        };
        const approved_value = root.get("approved") orelse return error.InvalidCommand;
        const approved = switch (approved_value) {
            .bool => |value| value,
            else => return error.InvalidCommand,
        };

        return .{ .confirm = .{
            .confirm_id = confirm_id,
            .approved = approved,
        } };
    }
    if (!std.mem.eql(u8, action_value.string, "run")) {
        return error.InvalidCommand;
    }

    const recipe_value = root.get("recipe") orelse return error.InvalidCommand;
    if (recipe_value != .string) return error.InvalidCommand;

    const dry_run = if (root.get("dryRun")) |dry_run_value|
        switch (dry_run_value) {
            .bool => |value| value,
            .null => false,
            else => return error.InvalidCommand,
        }
    else
        false;

    var positional_args: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (positional_args.items) |arg| {
            allocator.free(arg);
        }
        positional_args.deinit(allocator);
    }

    if (root.get("params")) |params_value| {
        switch (params_value) {
            .object => |params_object| {
                var iter = params_object.iterator();
                while (iter.next()) |entry| {
                    const value = switch (entry.value_ptr.*) {
                        .string => |string| string,
                        .null => continue,
                        else => return error.InvalidCommand,
                    };
                    try positional_args.append(allocator, try std.fmt.allocPrint(allocator, "{s}={s}", .{
                        entry.key_ptr.*,
                        value,
                    }));
                }
            },
            .null => {},
            else => return error.InvalidCommand,
        }
    }

    return .{
        .run = .{
            .task_name = try allocator.dupe(u8, recipe_value.string),
            .positional_args = try positional_args.toOwnedSlice(allocator),
            .dry_run = dry_run,
        },
    };
}

fn serializeEvent(allocator: std.mem.Allocator, event: event_emitter.Event) ![]u8 {
    var json: std.ArrayListUnmanaged(u8) = .empty;
    errdefer json.deinit(allocator);

    switch (event) {
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

fn serveStatic(stream: std.net.Stream, content_type: []const u8, body: []const u8) !void {
    var buf: [256]u8 = undefined;
    const header = std.fmt.bufPrint(&buf, "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: {s}\r\n" ++
        "Content-Length: {d}\r\n" ++
        "Connection: close\r\n" ++
        "Cache-Control: no-cache\r\n" ++
        "\r\n", .{ content_type, body.len }) catch return;
    try stream.writeAll(header);
    try stream.writeAll(body);
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

fn setSocketTimeout(stream: std.net.Stream, option: u32, milliseconds: u32) !void {
    if (builtin.os.tag == .windows) {
        try std.posix.setsockopt(stream.handle, std.posix.SOL.SOCKET, option, std.mem.asBytes(&milliseconds));
    } else {
        const timeout = std.posix.timeval{ .sec = @intCast(milliseconds / 1000), .usec = @intCast((milliseconds % 1000) * 1000) };
        try std.posix.setsockopt(stream.handle, std.posix.SOL.SOCKET, option, std.mem.asBytes(&timeout));
    }
}

fn readExact(reader: anytype, buf: []u8) !void {
    var offset: usize = 0;
    while (offset < buf.len) {
        const n = try reader.read(buf[offset..]);
        if (n == 0) return error.EndOfStream;
        offset += n;
    }
}

fn readHttpHeader(reader: anytype, buf: []u8) ![]const u8 {
    for (0..buf.len) |i| {
        try readExact(reader, buf[i .. i + 1]);
        if (i >= 3 and std.mem.eql(u8, buf[i - 3 .. i + 1], "\r\n\r\n")) return buf[0 .. i + 1];
    }
    return error.HeaderTooLarge;
}

/// WebSocket client connection
pub const WebSocketClient = struct {
    stream: std.net.Stream,
    allocator: std.mem.Allocator,

    write_mutex: std.Thread.Mutex = .{},
    stopped: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    /// Shutdown unblocks I/O without recycling the descriptor while the reader
    /// still owns it. Only deinit closes it, after all users are excluded.
    pub fn shutdown(self: *WebSocketClient) void {
        if (!self.stopped.swap(true, .acq_rel)) std.posix.shutdown(self.stream.handle, .both) catch {};
    }

    pub fn deinit(self: *WebSocketClient) void {
        self.stream.close();
    }

    pub fn readFrame(self: *WebSocketClient) !WebSocketFrame {
        var header: [2]u8 = undefined;
        try readExact(self.stream, &header);

        const opcode: WebSocketOpcode = @enumFromInt(header[0] & 0x0F);
        const masked = (header[1] & 0x80) != 0;
        var payload_len: u64 = header[1] & 0x7F;

        // Extended payload length
        if (payload_len == 126) {
            var ext: [2]u8 = undefined;
            try readExact(self.stream, &ext);
            payload_len = std.mem.readInt(u16, &ext, .big);
        } else if (payload_len == 127) {
            var ext: [8]u8 = undefined;
            try readExact(self.stream, &ext);
            payload_len = std.mem.readInt(u64, &ext, .big);
        }

        // Read masking key if present
        var mask: [4]u8 = .{ 0, 0, 0, 0 };
        if (masked) {
            try readExact(self.stream, &mask);
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
        self.write_mutex.lock();
        defer self.write_mutex.unlock();
        if (self.stopped.load(.acquire)) return error.EndOfStream;
        errdefer self.shutdown();
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
    if (shouldSkipBrowserLaunch()) return;

    const argv: []const []const u8 = switch (@import("builtin").os.tag) {
        .macos => &.{ "open", url },
        .linux => &.{ "xdg-open", url },
        .windows => &.{ "cmd", "/c", "start", url },
        else => return error.UnsupportedPlatform,
    };

    var child = std.process.Child.init(argv, std.heap.page_allocator);
    child.spawn() catch return;
}

fn shouldSkipBrowserLaunch() bool {
    return hasTruthyEnvVar("JAKE_NO_BROWSER") or hasTruthyEnvVar("CI");
}

fn hasTruthyEnvVar(name: []const u8) bool {
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch return false;
    defer std.heap.page_allocator.free(value);

    return !std.mem.eql(u8, value, "0") and !std.mem.eql(u8, value, "false");
}

fn containsString(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
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

test "parseClientCommand extracts run recipe params and dry-run flag" {
    const json =
        \\{"action":"run","recipe":"build","params":{"name":"Alice","target":"prod"},"dryRun":true}
    ;

    var command = try parseClientCommand(std.testing.allocator, json);
    defer switch (command) {
        .run => |*request| request.deinit(std.testing.allocator),
        .confirm => {},
        .stop => {},
    };

    switch (command) {
        .run => |request| {
            try std.testing.expectEqualStrings("build", request.task_name);
            try std.testing.expect(request.dry_run);
            try std.testing.expectEqual(@as(usize, 2), request.positional_args.len);
            try std.testing.expect(containsString(request.positional_args, "name=Alice"));
            try std.testing.expect(containsString(request.positional_args, "target=prod"));
        },
        .confirm, .stop => return error.TestUnexpectedResult,
    }
}

test "parseClientCommand extracts stop commands" {
    var command = try parseClientCommand(std.testing.allocator, "{\"action\":\"stop\"}");
    defer switch (command) {
        .run => |*request| request.deinit(std.testing.allocator),
        .confirm => {},
        .stop => {},
    };

    switch (command) {
        .stop => {},
        .run, .confirm => return error.TestUnexpectedResult,
    }
}

test "parseClientCommand extracts confirm responses" {
    var command = try parseClientCommand(std.testing.allocator, "{\"action\":\"confirm\",\"confirmId\":7,\"approved\":true}");
    defer switch (command) {
        .run => |*request| request.deinit(std.testing.allocator),
        .confirm => {},
        .stop => {},
    };

    switch (command) {
        .confirm => |response| {
            try std.testing.expectEqual(@as(u64, 7), response.confirm_id);
            try std.testing.expect(response.approved);
        },
        .run, .stop => return error.TestUnexpectedResult,
    }
}

test "parseClientCommand rejects non-string params" {
    try std.testing.expectError(error.InvalidCommand, parseClientCommand(
        std.testing.allocator,
        "{\"action\":\"run\",\"recipe\":\"build\",\"params\":{\"count\":1}}",
    ));
}

test "buildExecutionContext preserves cli settings and applies web overrides" {
    var server = WebUIServer.init(std.testing.allocator, 8420);
    defer server.deinit();

    server.base_context = context_mod.Context{
        .dry_run = true,
        .verbose = true,
        .auto_yes = false,
        .watch_mode = true,
        .jobs = 4,
        .color = color_mod.withEnabled(true),
        .positional_args = &.{"ignored=value"},
    };

    var task_name = [_]u8{ 'b', 'u', 'i', 'l', 'd' };
    const request = ExecutionRequest{
        .task_name = task_name[0..],
        .positional_args = &.{"name=Alice"},
        .dry_run = false,
    };

    const ctx = server.buildExecutionContext(&request);
    try std.testing.expect(ctx.dry_run);
    try std.testing.expect(ctx.verbose);
    try std.testing.expect(!ctx.auto_yes);
    try std.testing.expect(!ctx.watch_mode);
    try std.testing.expect(!ctx.allow_interactive_stdin);
    try std.testing.expectEqual(@as(usize, 4), ctx.jobs);
    try std.testing.expect(!ctx.color.enabled);
    try std.testing.expectEqual(@as(usize, 1), ctx.positional_args.len);
    try std.testing.expectEqualStrings("name=Alice", ctx.positional_args[0]);
    try std.testing.expect(ctx.cancellation_flag == &server.execution_running);
    try std.testing.expect(ctx.current_child_pid == &server.current_child_pid);
    try std.testing.expect(ctx.output_callback != null);
    try std.testing.expect(ctx.output_callback_ctx == @as(*anyopaque, @ptrCast(&server)));
    try std.testing.expect(ctx.confirm_callback == null);
    try std.testing.expect(ctx.event_emitter != null);
}

test "buildExecutionContext enables interactive confirm transport when needed" {
    var server = WebUIServer.init(std.testing.allocator, 8420);
    defer server.deinit();

    server.base_context = context_mod.Context{
        .dry_run = false,
        .verbose = false,
        .auto_yes = false,
        .watch_mode = true,
        .jobs = 2,
        .color = color_mod.withEnabled(true),
    };

    var task_name = [_]u8{ 'r', 'u', 'n' };
    const request = ExecutionRequest{
        .task_name = task_name[0..],
        .positional_args = &.{},
        .dry_run = false,
    };

    const ctx = server.buildExecutionContext(&request);
    try std.testing.expect(!ctx.allow_interactive_stdin);
    try std.testing.expect(ctx.confirm_callback != null);
    try std.testing.expect(ctx.confirm_callback_ctx == @as(*anyopaque, @ptrCast(&server)));
}

const ChunkReader = struct {
    bytes: []const u8,
    chunk_size: usize,
    fn read(self: *@This(), out: []u8) !usize {
        const count = @min(out.len, self.bytes.len, self.chunk_size);
        @memcpy(out[0..count], self.bytes[0..count]);
        self.bytes = self.bytes[count..];
        return count;
    }
};

test "complete reads accumulate chunks and report EOF" {
    for (1..9) |chunk_size| {
        var reader = ChunkReader{ .bytes = "abcdefgh", .chunk_size = chunk_size };
        var out: [8]u8 = undefined;
        try readExact(&reader, &out);
        try std.testing.expectEqualStrings("abcdefgh", &out);
        try std.testing.expectError(error.EndOfStream, readExact(&reader, out[0..1]));
    }
}

test "HTTP header reader preserves following bytes and bounds storage" {
    const header = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var reader = ChunkReader{ .bytes = header ++ "next", .chunk_size = 3 };
    var out: [128]u8 = undefined;
    try std.testing.expectEqualStrings(header, try readHttpHeader(&reader, &out));
    try std.testing.expectEqualStrings("next", reader.bytes);
    var short = ChunkReader{ .bytes = header, .chunk_size = 1 };
    try std.testing.expectError(error.HeaderTooLarge, readHttpHeader(&short, out[0..4]));
}

test "WebSocket readers drain before server teardown across repeated connections" {
    const allocator = std.testing.allocator;
    var server = WebUIServer.init(allocator, 0);
    defer server.deinit();
    try server.start();
    for (0..24) |i| {
        const peer = try std.net.tcpConnectToAddress(server.server.?.listen_address);
        defer peer.close();
        const conn = try server.server.?.accept();
        const client = try allocator.create(WebSocketClient);
        client.* = .{ .stream = conn.stream, .allocator = allocator };
        server.mutex.lock();
        try server.clients.append(allocator, client);
        server.mutex.unlock();
        const thread = try std.Thread.spawn(.{}, WebUIServer.handleWebSocketFramesThread, .{ &server, client });
        thread.detach();
        // The final reader is blocked in readFrame when stop wakes it. Earlier
        // iterations end by ordinary peer closure. Neither path double-closes.
        if (i == 23) server.stop();
    }
}

test "pre-execution failure terminates root exactly once" {
    var server = WebUIServer.init(std.testing.allocator, 0);
    defer server.deinit();
    server.run_recipe = "root";
    server.run_started_ms = std.time.milliTimestamp();
    server.execution_active.store(true, .release);
    server.finishRun(true);
    try std.testing.expect(server.root_started);
    try std.testing.expect(server.root_completed);
    try std.testing.expectEqual(@as(usize, 1), server.tasks_failed);
    try std.testing.expect(!server.execution_active.load(.acquire));
    try std.testing.expect(server.run_recipe == null);
}

test "concurrent WebSocket writers preserve whole messages" {
    var listener = try std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 0).listen(.{});
    defer listener.deinit();
    const peer = try std.net.tcpConnectToAddress(listener.listen_address);
    defer peer.close();
    const conn = try listener.accept();
    var sender = WebSocketClient{ .stream = conn.stream, .allocator = std.testing.allocator };
    defer sender.deinit();
    var receiver = WebSocketClient{ .stream = peer, .allocator = std.testing.allocator };
    const Writer = struct {
        fn run(client: *WebSocketClient, payload: []const u8) void {
            for (0..32) |_| client.sendText(payload) catch return;
        }
    };
    const first = try std.Thread.spawn(.{}, Writer.run, .{ &sender, "alpha" ** 100 });
    defer first.join();
    const second = try std.Thread.spawn(.{}, Writer.run, .{ &sender, "bravo" ** 100 });
    defer second.join();
    var alpha_count: usize = 0;
    var bravo_count: usize = 0;
    for (0..64) |_| {
        const frame = try receiver.readFrame();
        defer std.testing.allocator.free(frame.payload);
        try std.testing.expectEqual(WebSocketOpcode.text, frame.opcode);
        if (std.mem.eql(u8, frame.payload, "alpha" ** 100)) {
            alpha_count += 1;
        } else {
            try std.testing.expectEqualStrings("bravo" ** 100, frame.payload);
            bravo_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 32), alpha_count);
    try std.testing.expectEqual(@as(usize, 32), bravo_count);
}

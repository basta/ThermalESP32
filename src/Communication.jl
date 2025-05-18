module Communication

using Sockets
using ..Constants # For RawStreamConfig
using ..ImageProcessing # For process_tcp_frame, ThermalImage

export connect_and_process_stream

"""
    connect_and_process_stream(config::RawStreamConfig, frame_processor_callback::Function;
                               max_retries=5, retry_delay_s=2.0)

Connects to the ESP32 thermal camera server and continuously reads and processes
data frames using the raw stream protocol.

Arguments:
- `config`: `RawStreamConfig` object with connection and frame parameters.
- `frame_processor_callback`: A function `(thermal_image::ThermalImage)::Bool` that
  is called for each processed frame. It should return `true` to continue streaming,
  or `false` to stop.
- `max_retries`: Maximum number of connection retries.
- `retry_delay_s`: Delay in seconds between retries.

The callback receives a `ThermalImage` object.
"""
function connect_and_process_stream(
    config::RawStreamConfig,
    frame_processor_callback::Function;
    max_retries::Int=5,
    retry_delay_s::Float64=2.0
)
    socket = nothing
    receive_buffer = UInt8[]
    attempt = 0

    while attempt <= max_retries
        attempt += 1
        try
            @info "Attempting to connect (attempt $attempt/$(max_retries+1)) to $(config.server_ip):$(config.server_port)..."
            socket = Sockets.connect(config.server_ip, config.server_port)
            @info "Successfully connected to server."
            break # Exit retry loop on successful connection
        catch e
            @warn "Connection attempt $attempt failed: $e"
            if attempt > max_retries
                @error "Maximum connection retries reached. Giving up."
                rethrow()
            end
            sleep(retry_delay_s)
        end
    end

    running = true
    try
        while running && isopen(socket)
            try
                # Non-blocking read if possible, or tune readavailable behavior
                # For simplicity, readavailable will block until data or EOF/error
                data_chunk = readavailable(socket)

                if isempty(data_chunk)
                    if !isopen(socket) # Check if socket closed by peer or other issue
                        @warn "Socket closed while trying to read data."
                        running = false
                        continue
                    end
                    # If socket is open but no data, could be normal, just sleep briefly
                    sleep(0.001) # Small sleep to prevent busy-looping if no data
                    continue
                end

                append!(receive_buffer, data_chunk)

                while length(receive_buffer) >= config.tcp_total_frame_size && running
                    current_tcp_frame = receive_buffer[1:config.tcp_total_frame_size]
                    # Efficiently remove processed part of the buffer
                    receive_buffer = @view receive_buffer[(config.tcp_total_frame_size+1):end]

                    parsed_image_data = process_tcp_frame(current_tcp_frame, config)

                    # Call the user-provided callback
                    keep_running = frame_processor_callback(parsed_image_data)
                    if !isa(keep_running, Bool)
                        @warn "Frame processor callback did not return a Bool. Assuming true to continue."
                        running = true
                    else
                        running = keep_running
                    end

                    if !running
                        @info "Frame processor callback requested to stop streaming."
                        break
                    end
                end # while buffer has enough data

            catch e
                if e isa InterruptException
                    @info "Streaming interrupted by user (Ctrl-C)."
                    running = false
                elseif e isa EOFError
                    @info "Connection closed by server (EOF)."
                    running = false
                elseif e isa Base.IOError && !isopen(socket)
                    @warn "IOError and socket is now closed. Likely connection lost: $e."
                    running = false
                elseif e isa Base.IOError
                    @warn "IOError during socket read: $e. Connection might be unstable."
                    # Optionally, could try to continue or implement more robust error handling here
                    running = false # For safety, stop on unknown IOErrors
                else
                    @error "Unhandled error in streaming loop: $(typeof(e)) - $e"
                    # Consider logging stacktrace(catch_backtrace())
                    running = false # Stop on unhandled errors
                end
            end # try-catch for socket read and processing
        end # while running and socket is open
    finally
        if socket !== nothing && isopen(socket)
            try
                close(socket)
                @info "Socket closed."
            catch e_close
                @warn "Error closing socket: $e_close"
            end
        elseif socket !== nothing
            @info "Socket was already closed or not opened successfully."
        end
        @info "Streaming finished."
    end # try-finally for connection management
end

end # module Communication

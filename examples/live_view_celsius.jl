# examples/live_view_celsius.jl

# This example demonstrates live thermal data acquisition, conversion to Celsius,
# and visualization using GLMakie. It also shows how to record the Celsius data.

using ThermalESP32
using GLMakie # For visualization
using Dates   # For timestamps
using Printf  # For formatting output

# Activate GLMakie backend (important for some environments)
GLMakie.activate!(inline=false) # Set to true for inline plots in notebooks/ sommige IDEs

function main_live_view_celsius()
    println("Thermal Data Live Viewer (Celsius) & Recorder")

    # --- Configuration ---
    # Use default config or customize as needed
    # server_cfg = RawStreamConfig(server_ip="your.esp32.ip.here")
    server_cfg = RawStreamConfig() # Uses defaults: 192.168.4.1, port 3333, 80x62 frame

    # Recording settings
    enable_recording = true # Set to false to disable recording
    recording_dir = "thermal_recordings_celsius"
    mkpath(recording_dir) # Ensure directory exists

    # Using a vector to store frames in memory before batch saving
    # For very long recordings, consider writing frame by frame to disk directly inside the callback.
    recorded_frames_celsius = Matrix{Float32}[]

    # --- Makie Setup for Temperatures ---
    obs_thermal_data = Observable(zeros(Float32, server_cfg.frame_height, server_cfg.frame_width))

    # Initial temperature range for color mapping (adjust as needed)
    slider_min_val_initial = 15.0f0  # °C
    slider_max_val_initial = 40.0f0  # °C
    slider_overall_min = -20.0f0 # °C
    slider_overall_max = 120.0f0 # °C
    slider_step = 0.5f0          # °C

    obs_color_min = Observable(slider_min_val_initial)
    obs_color_max = Observable(slider_max_val_initial)

    color_range_obs = lift(obs_color_min, obs_color_max) do cmin, cmax
        (min(cmin, cmax - slider_step), max(cmax, cmin + slider_step))
    end

    fig = Figure(size=(server_cfg.frame_width * 8, server_cfg.frame_height * 8 + 200)) # Adjusted size
    ax = Axis(fig[1, 1], title="Live Thermal Image (°C)", aspect=DataAspect())
    hm = heatmap!(ax, obs_thermal_data, colormap=:hot, colorrange=color_range_obs)
    Colorbar(fig[1, 2], hm, label="Temperature (°C)")

    # Sliders for adjusting color range
    slider_layout = GridLayout(fig[2, 1:2]) # Span sliders across both columns of the top layout

    Label(slider_layout[1, 1], "Min Temp:", halign=:right)
    sl_min = Slider(slider_layout[1, 2], range=slider_overall_min:slider_step:slider_overall_max, startvalue=slider_min_val_initial)
    Label(slider_layout[1, 3], lift(x -> @sprintf("%.1f°C", x), obs_color_min), halign=:left, width=100)

    Label(slider_layout[2, 1], "Max Temp:", halign=:right)
    sl_max = Slider(slider_layout[2, 2], range=slider_overall_min:slider_step:slider_overall_max, startvalue=slider_max_val_initial)
    Label(slider_layout[2, 3], lift(x -> @sprintf("%.1f°C", x), obs_color_max), halign=:left, width=100)

    on(sl_min.value) do val
        obs_color_min[] = val
    end
    on(sl_max.value) do val
        obs_color_max[] = val
    end

    colsize!(slider_layout, 1, Auto())
    colsize!(slider_layout, 2, Relative(0.6)) # Slider takes most space
    colsize!(slider_layout, 3, Auto())

    display(fig)
    println("Makie plot initialized. Waiting for data...")

    # --- Frame Processing Callback ---
    local packet_count
    packet_count = 0
    function process_received_frame(thermal_image::ThermalImage)::Bool

        if !events(fig.scene).window_open[]
            println("Makie window closed by user. Stopping.")
            return false # Stop streaming if plot window is closed
        end

        if thermal_image.is_valid && thermal_image.thermal_image_matrix !== nothing
            packet_count += 1
            raw_img_matrix = thermal_image.thermal_image_matrix

            # Convert raw data to temperatures
            temp_matrix = ThermalESP32.raw_matrix_to_celsius(raw_img_matrix)

            # Update Makie plot
            obs_thermal_data[] = temp_matrix

            # Record the temperature matrix (Float32)
            if enable_recording
                push!(recorded_frames_celsius, temp_matrix)
            end

            if packet_count % 30 == 0 # Print stats less frequently
                min_val_temp = minimum(temp_matrix)
                max_val_temp = maximum(temp_matrix)
                stats_line = @sprintf "Frame #%d: %dx%d, Temp Min: %.2f°C, Max: %.2f°C, CRange: (%.1f, %.1f)°C" packet_count size(temp_matrix, 2) size(temp_matrix, 1) min_val_temp max_val_temp obs_color_min[] obs_color_max[]
                println(stats_line)
            end
        else
            @warn "Received invalid or empty frame data at packet #$packet_count."
        end
        return true # Continue streaming
    end

    # --- Start Streaming ---
    try
        ThermalESP32.connect_and_process_stream(server_cfg, process_received_frame)
    catch ex
        if ex isa InterruptException
            println("\nStream capture interrupted by user (Ctrl-C).")
        else
            println("\nAn error occurred during streaming: $ex")
            showerror(stdout, ex, catch_backtrace()) # Show stack trace for other errors
        end
    finally
        println("Streaming stopped.")
        if enable_recording && !isempty(recorded_frames_celsius)
            timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
            output_filename = joinpath(recording_dir, "thermal_temps_f32_$(timestamp).bin")
            println("Saving $(length(recorded_frames_celsius)) recorded Celsius frames to $output_filename...")
            try
                ThermalESP32.save_thermal_frames_celsius(
                    output_filename,
                    recorded_frames_celsius,
                    UInt16(server_cfg.frame_width),
                    UInt16(server_cfg.frame_height)
                )
            catch e_save
                @error "Failed to save recorded frames: $e_save"
            end
        elseif enable_recording
            println("No frames were recorded.")
        end

        # Keep Makie window open a bit longer or until manually closed if script ends quickly
        if events(fig.scene).window_open[]
            println("Makie window will remain open. Close it manually to exit the script completely if it doesn't auto-close.")
            # wait_for_manual_close(fig) # You might need a helper for this in some backends
        end
    end
    println("Live view and recorder finished.")
end


# To run the example:
if abspath(PROGRAM_FILE) == @__FILE__
    main_live_view_celsius()
end

# ThermalESP32.jl: A Julia Package for Waveshare ESP32 Thermal Camera Communication

**Author:** Ondřej Baštař
**Affiliation:** Czech Technical University in Prague, Faculty of Electrical Engineering

## 1. Introduction

`ThermalESP32.jl` is a software package developed in the Julia programming language, designed to facilitate robust communication and data processing with the Waveshare ESP32-based thermal imaging camera module. This package provides a comprehensive suite of tools for establishing TCP/IP connections, receiving raw thermal data streams, processing these streams into calibrated thermal image matrices, and converting raw sensor readings into standard temperature units (degrees Celsius).

The primary motivation for this package is to offer a flexible and efficient interface for researchers and developers working on applications requiring real-time thermal data acquisition and analysis, particularly in fields such as robotics, process monitoring, non-destructive testing, and experimental fluid dynamics or heat transfer studies.

## 2. Features

* **TCP/IP Communication:** Establishes and manages a TCP client connection to the ESP32 thermal camera server.
* **Raw Data Streaming:** Efficiently handles continuous raw data streams from the camera module.
* **Frame Processing:** Parses incoming TCP frames, stripping headers/trailers and extracting raw pixel data.
* **Image Reconstruction:** Converts the 1D raw pixel data vector into a 2D matrix representing the thermal image, accounting for sensor resolution and data endianness.
* **Temperature Conversion:** Provides functions to convert raw 16-bit sensor values to floating-point temperature values in degrees Celsius using a standard calibration formula.
* **Data Persistence:** Includes utilities for saving acquired thermal frames (both raw and Celsius-converted) to binary files and loading them for subsequent analysis or playback.
* **Modular Design:** Organized into distinct modules for configuration, image processing, communication, and data utilities, promoting extensibility.
* **Example Implementations:** Offers practical examples demonstrating live visualization, data recording, playback, and integration with control interfaces.
* **(Experimental) Structured Packet Parsing:** Contains preliminary support for an alternative structured packet format ("GFRA").

## 3. System Requirements and Dependencies

* **Julia:** Version 1.6 or higher.
* **Core Julia Packages:**
    * `Sockets`: For TCP/IP communication.
    * `Dates`: For timestamping recordings.
    * `Printf`: For formatted string output.
    * `Statistics`: Used in some example data analysis.
* **For Examples & Extended Functionality:**
    * `GLMakie.jl`: For 2D thermal image visualization in examples.
    * `LibSerialPort.jl`: For serial communication with auxiliary devices (e.g., ESP32 for control commands) demonstrated in specific examples.

These dependencies are managed through the package's `Project.toml` file.

## 4. Installation

1.  **Clone the Repository (if not registered in Julia's General registry):**
    ```bash
    git clone github.com/basta/ThermalESP32
    ```

2.  **Install the Package:**
    Open the Julia REPL, enter the Pkg mode by pressing `]`, and then execute:
    ```julia
    pkg> add path/to/ThermalESP32.jl
    ```
    If the package is registered in the General registry, it can be installed via:
    ```julia
    pkg> add ThermalESP32
    ```

## 5. Package Structure

The package is organized as follows:

* **`Project.toml`**: Defines package metadata, dependencies, and compatibility.
* **`README.md`**: This document.
* **`LICENSE`**: Specifies the open-source license under which the package is distributed.
* **`src/`**: Contains the core source code of the package, organized into several modules:
    * `ThermalESP32.jl`: The main module file, which integrates and exports functionalities from other sub-modules.
    * `Constants.jl`: Defines configuration structures (e.g., `RawStreamConfig`) and default parameters for camera communication.
    * `ImageProcessing.jl`: Handles the conversion of raw byte streams into `ThermalImage` objects, including reshaping and endian correction.
    * `StructuredPacketParser.jl`: Provides experimental support for parsing an alternative, structured packet format from the ESP32.
    * `Communication.jl`: Manages the TCP connection, data reception, and buffering for continuous streaming.
    * `DataUtils.jl`: Contains functions for temperature conversion (raw to Celsius) and for saving/loading thermal data to/from disk.
    * `SerialUtils.jl`: Offers helper functions for serial port communication, primarily used by example scripts for interacting with control interfaces.
* **`examples/`**: Includes example scripts that demonstrate various uses of the package, such as:
    * Live thermal image visualization.
    * Recording thermal data to files.
    * Playing back recorded data.
* **`test/`**: Contains unit tests for verifying the correctness of package functionalities.

## 6. Core Components and Basic Usage

The package provides a set of types and functions to interact with the thermal camera.

### 6.1. Configuration

Communication parameters are defined using the `RawStreamConfig` structure:

```julia
using ThermalESP32

# Default configuration for raw stream mode
config = RawStreamConfig(
    server_ip="192.168.4.1",   # IP address of the ESP32 camera server
    server_port=3333,          # Port number for the TCP server
    frame_width=80,            # Width of the thermal image in pixels
    frame_height=62,           # Height of the thermal image in pixels
    strip_head_bytes=160,      # Bytes to strip from the beginning of each TCP frame
    strip_tail_bytes=160       # Bytes to strip from the end of each TCP frame
)
```

### 6.2. Data Structures

* **`ThermalImage`**: A structure returned by `process_tcp_frame`, containing:
    * `is_valid::Bool`: Indicates if the frame was successfully parsed.
    * `thermal_image_matrix::Union{Matrix{UInt16}, Nothing}`: A 2D matrix of raw 16-bit thermal values.

### 6.3. Key Functions

* **`process_tcp_frame(frame_bytes::Vector{UInt8}, cfg::RawStreamConfig)::ThermalImage`**:
    Parses a complete TCP data frame and extracts the thermal image.
* **`raw_to_celsius(raw_value::UInt16)::Float32`**:
    Converts a single raw thermal value to Celsius.
* **`raw_matrix_to_celsius(raw_matrix::Matrix{UInt16})::Matrix{Float32}`**:
    Converts an entire matrix of raw thermal values to Celsius.
* **`connect_and_process_stream(config::RawStreamConfig, frame_processor_callback::Function)`**:
    The primary function for live data acquisition. It connects to the camera, receives data, processes frames, and invokes a user-defined `frame_processor_callback` for each valid `ThermalImage`. The callback function should return `true` to continue streaming or `false` to stop.
* **`save_thermal_frames_raw(filepath, frames_vector, width, height)` / `load_thermal_frames_raw(filepath)`**:
    For saving and loading sequences of raw `UInt16` thermal image matrices.
* **`save_thermal_frames_celsius(filepath, frames_vector, width, height)` / `load_thermal_frames_celsius(filepath)`**:
    For saving and loading sequences of `Float32` Celsius-converted thermal image matrices.

### 6.4. Basic Streaming Example

The following example demonstrates connecting to the camera, retrieving frames, and printing basic statistics for each frame.

```julia
using ThermalESP32
using Printf

function simple_stream_processor()
    config = RawStreamConfig() # Use default settings
    frame_count = 0

    # Define a callback function to process each frame
    function my_frame_callback(thermal_image::ThermalImage)::Bool
        nonlocal frame_count
        if thermal_image.is_valid && thermal_image.thermal_image_matrix !== nothing
            frame_count += 1
            temp_matrix_celsius = raw_matrix_to_celsius(thermal_image.thermal_image_matrix)
            min_temp = minimum(temp_matrix_celsius)
            max_temp = maximum(temp_matrix_celsius)
            mean_temp = sum(temp_matrix_celsius) / length(temp_matrix_celsius)

            @printf "Frame %04d: Min=%.2f°C, Max=%.2f°C, Mean=%.2f°C\n" frame_count min_temp max_temp mean_temp

            if frame_count >= 100 # Example: stop after 100 frames
                println("Acquired 100 frames. Stopping.")
                return false
            end
        else
            @warn "Received an invalid frame."
        end
        return true # Continue streaming
    end

    println("Starting thermal stream acquisition...")
    try
        connect_and_process_stream(config, my_frame_callback)
    catch ex
        if ex isa InterruptException
            println("\nStreaming interrupted by user.")
        else
            println("\nError during streaming: $ex")
        end
    finally
        println("Streaming session concluded. Total frames processed: $frame_count")
    end
end

# To run:
# simple_stream_processor()
```

## 7. Data Format for Saved Files

When thermal frames are saved using `save_thermal_frames_raw` or `save_thermal_frames_celsius`, the binary file format is as follows:
1.  Frame Width (`UInt16`)
2.  Frame Height (`UInt16`)
3.  Sequentially stored frame data:
    * For raw data: Each frame consists of `width * height` `UInt16` pixel values, written in column-major order.
    * For Celsius data: Each frame consists of `width * height` `Float32` temperature values, written in column-major order.

## 8. Examples

The `examples/` directory contains more comprehensive scripts, including:
* `live_view_celsius.jl`: Live visualization of thermal data with GLMakie, including interactive color range adjustment and optional recording of Celsius data.
* `playback_recorded_data.jl`: Demonstrates loading and replaying previously saved thermal data (both raw and Celsius).
* `control_panel_gui.jl`: A more complex example showcasing a GUI for thermal visualization, sending control commands (e.g., PID parameters) to an ESP32 via serial port, and displaying feedback from the device.

## 9. License

This project is licensed under the [Specify Your Chosen License Here, e.g., MIT License]. Please see the `LICENSE` file for full details.

## 1é. Contact

Ondřej Baštař - jsembasta@gmail.com
Czech Technical University in Prague

module ThermalESP32

# Standard library imports
using Sockets
using Printf
using Dates
using Statistics

# External dependencies (will be listed in Project.toml)
# Makie and LibSerialPort are primarily for examples, but core utilities might use them

# Include internal modules
include("Constants.jl")
include("ImageProcessing.jl")
include("StructuredPacketParser.jl") # For the alternative packet format
include("DataUtils.jl")
include("Communication.jl")
include("SerialUtils.jl") # General serial utilities


# From Constants.jl
export RawStreamConfig, StructuredPacketConfig # Add more configs if needed

# From ImageProcessing.jl
export ThermalImage, process_tcp_frame

# From StructuredPacketParser.jl
export ParsedPacket, parse_thermal_packet

# From DataUtils.jl
export raw_to_celsius, raw_matrix_to_celsius
export save_thermal_frames_raw, load_thermal_frames_raw
export save_thermal_frames_celsius, load_thermal_frames_celsius # New functions for celsius data

# From Communication.jl
export connect_and_process_stream

# From SerialUtils.jl
export list_serial_ports, send_serial_command


# You might want to add a high-level function here if applicable,
# or just re-export from submodules.

end # module ThermalESP32

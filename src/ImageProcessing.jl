module Constants

export RawStreamConfig, StructuredPacketConfig

"""
Configuration for the ESP32 Thermal Server Client (Raw Stream Mode).
"""
struct RawStreamConfig
    server_ip::String
    server_port::Int
    frame_width::Int
    frame_height::Int
    raw_image_size_bytes::Int
    strip_head_bytes::Int
    strip_tail_bytes::Int
    tcp_total_frame_size::Int

    function RawStreamConfig(;
        server_ip::String="192.168.4.1",
        server_port::Int=3333,
        frame_width::Int=80,
        frame_height::Int=62,
        strip_head_bytes::Int=160,
        strip_tail_bytes::Int=160
    )
        raw_image_size_bytes = frame_width * frame_height * 2 # UInt16 per pixel
        tcp_total_frame_size = raw_image_size_bytes + strip_head_bytes + strip_tail_bytes
        new(server_ip, server_port, frame_width, frame_height,
            raw_image_size_bytes, strip_head_bytes, strip_tail_bytes, tcp_total_frame_size)
    end
end

# Default instance for easy access if needed, though passing config explicitly is better
# const DEFAULT_RAW_STREAM_CONFIG = RawStreamConfig()

"""
Configuration for the ESP32 Thermal Server Client (Structured Packet Mode).
Based on analysis of packet_parser.jl.
"""
struct StructuredPacketConfig
    server_ip::String
    server_port::Int # Assuming same port, adjust if different
    image_width::Int # From your packet_parser.jl context (e.g., 80)
    image_height::Int # From your packet_parser.jl context (e.g., 60)
    expected_packet_size::Int # e.g., 10257 bytes
    # Add other relevant constants from packet_parser.jl logic if needed
    # e.g., prefix, payload_len_expected, frame_type_expected

    function StructuredPacketConfig(;
        server_ip::String="192.168.4.1", # Default, adjust if necessary
        server_port::Int=3333, # Default, adjust if necessary
        image_width::Int=80, # Example, ensure this matches your device for this mode
        image_height::Int=60, # Example
        expected_packet_size::Int=10257 # From your packet_parser.jl
    )
        new(server_ip, server_port, image_width, image_height, expected_packet_size)
    end
end

# const DEFAULT_STRUCTURED_PACKET_CONFIG = StructuredPacketConfig()

end # module Constants

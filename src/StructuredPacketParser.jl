module StructuredPacketParser

using ..Constants # To access StructuredPacketConfig

export ParsedPacket, parse_thermal_packet

"""
Structure to hold the parsed data from a thermal packet (GFRA format).
"""
struct ParsedPacket
    is_valid::Bool
    header_prefix_ok::Bool
    payload_len_str::String
    payload_len_val::Union{UInt32,Nothing} # Expected: 0x2808 (10248)
    frame_type::String
    metadata::Vector{UInt8} # 160 bytes
    thermal_image_raw::Vector{UInt8} # e.g. 10080 bytes for 80x60, or 9920 for 80x62
    thermal_image::Union{Matrix{UInt16},Nothing} # IMAGE_HEIGHT x IMAGE_WIDTH
    crc_string::String
    crc_value::Union{UInt16,Nothing} # Typically 16-bit for 4 hex chars
end

"""
    parse_thermal_packet(packet_bytes::Vector{UInt8}, cfg::StructuredPacketConfig)::ParsedPacket

Parses a raw byte vector representing one thermal data packet (GFRA format).
"""
function parse_thermal_packet(packet_bytes::Vector{UInt8}, cfg::StructuredPacketConfig)::ParsedPacket
    local is_overall_valid = true
    local is_prefix_ok = false
    local parsed_payload_len_str = ""
    local parsed_payload_len_val::Union{UInt32,Nothing} = nothing
    local parsed_frame_type = ""
    local parsed_metadata = UInt8[]
    local parsed_thermal_raw = UInt8[]
    local parsed_thermal_image::Union{Matrix{UInt16},Nothing} = nothing
    local parsed_crc_str = ""
    local parsed_crc_val::Union{UInt16,Nothing} = nothing

    if length(packet_bytes) != cfg.expected_packet_size
        @error "Invalid packet size: $(length(packet_bytes)). Expected $(cfg.expected_packet_size)."
        return ParsedPacket(false, false, "", nothing, "", UInt8[], UInt8[], nothing, "", nothing)
    end

    # Bytes 0-3: Prefix (e.g., "   #") -> Julia 1:4
    # Bytes 4-7: Payload Length (ASCII hex, e.g., "2808") -> Julia 5:8
    # Bytes 8-11: Frame Type (e.g., "GFRA") -> Julia 9:12
    # Bytes 12-171: Metadata (160 bytes) -> Julia 13:172
    # Bytes 172- (172 + W*H*2 - 1): Thermal Image Data -> Julia 173 : (172 + W*H*2)
    # Bytes (172 + W*H*2) - (172 + W*H*2 + 3): CRC (4 chars) -> Julia (173 + W*H*2) : (172 + W*H*2 + 4)

    # 1. Bytes 0-3: "   #"
    expected_prefix = UInt8[' ', ' ', ' ', '#']
    actual_prefix = packet_bytes[1:4]
    is_prefix_ok = (actual_prefix == expected_prefix)
    if !is_prefix_ok
        @warn "Packet prefix mismatch. Expected $expected_prefix, got $actual_prefix"
        is_overall_valid = false
    end

    # 2. Bytes 4-7: "2808" (ASCII hex for payload length 0x2808 = 10248)
    # Your original code expects 0x2808 = 10248.
    parsed_payload_len_str = String(packet_bytes[5:8])
    try
        parsed_payload_len_val = parse(UInt32, parsed_payload_len_str, base=16)
        if parsed_payload_len_val != 0x2808
            @warn "Payload length field value mismatch. Expected 0x2808, got 0x$(string(parsed_payload_len_val, base=16, pad=4)) (from \"$parsed_payload_len_str\")"
            is_overall_valid = false
        end
    catch e
        @warn "Could not parse payload length string: \"$parsed_payload_len_str\". Error: $e"
        is_overall_valid = false
        parsed_payload_len_val = nothing
    end

    # 3. Bytes 8-11: "GFRA" (Frame type)
    parsed_frame_type = String(packet_bytes[9:12])
    if parsed_frame_type != "GFRA"
        @warn "Unexpected frame type. Expected \"GFRA\", got \"$parsed_frame_type\""
        # Not necessarily invalidating the whole packet structure, but it's a warning.
    end

    # 4. Bytes 12-171 (0-indexed): 160 bytes of metadata/padding -> Julia indices 13:172
    parsed_metadata = packet_bytes[13:172]

    # 5. Bytes 172-10251 (0-indexed): 10080 bytes of thermal image data -> Julia indices 173:10252
    image_data_start_idx = 173
    expected_raw_image_size = cfg.image_width * cfg.image_height * sizeof(UInt16)
    image_data_end_idx = image_data_start_idx + expected_raw_image_size - 1

    if image_data_end_idx > length(packet_bytes) || (image_data_start_idx + expected_raw_image_size - 1) > 10252
        @warn "Calculated image data end index $image_data_end_idx exceeds packet parsing assumptions or available bytes."
        # This part needs careful review based on actual packet spec.
        # For now, using the hardcoded end from original:
        parsed_thermal_raw = packet_bytes[173:10252] # This assumes 10080 bytes
    else
        parsed_thermal_raw = packet_bytes[image_data_start_idx:image_data_end_idx]
    end


    if length(parsed_thermal_raw) == expected_raw_image_size
        try
            temp_u16_vector_view = reinterpret(UInt16, parsed_thermal_raw)
            thermal_data_uint16_flat = ltoh.(temp_u16_vector_view)
            parsed_thermal_image = permutedims(reshape(thermal_data_uint16_flat, cfg.image_width, cfg.image_height), (2, 1))
        catch e
            @error "Could not convert or reshape thermal image data. Error: $e"
            parsed_thermal_image = nothing
            is_overall_valid = false
        end
    else
        @warn "Thermal raw data size mismatch. Expected $expected_raw_image_size (for ${cfg.image_width}x${cfg.image_height}), got $(length(parsed_thermal_raw)) from indices 173:$(image_data_end_idx)"
        is_overall_valid = false
    end

    # 6. Bytes 10252-10255 (0-indexed): 4-char ASCII CRC -> Julia indices 10253:10256
    # This assumes the CRC is immediately after the image data block that ended at 10252.
    crc_start_idx = image_data_end_idx + 1 # Should be 10253 if image data was 10080 bytes ending at 10252
    crc_end_idx = crc_start_idx + 3       # For a 4-char CRC

    if crc_end_idx <= length(packet_bytes) && crc_start_idx == 10253 # Sticking to original indexing for this part
        parsed_crc_str = String(packet_bytes[10253:10256])
        try
            parsed_crc_val = parse(UInt16, parsed_crc_str, base=16)
        catch e
            @warn "Could not parse CRC string: \"$parsed_crc_str\". Error: $e"
            parsed_crc_val = nothing
        end
    else
        @warn "Not enough bytes for CRC or CRC start index mismatch. Expected start at 10253. Calculated image end: $image_data_end_idx"
        is_overall_valid = false # If CRC cannot be read, it's likely a problem
    end


    is_overall_valid = is_overall_valid && (parsed_thermal_image !== nothing)

    return ParsedPacket(
        is_overall_valid, is_prefix_ok, parsed_payload_len_str, parsed_payload_len_val,
        parsed_frame_type, parsed_metadata, parsed_thermal_raw, parsed_thermal_image,
        parsed_crc_str, parsed_crc_val
    )
end

end # module StructuredPacketParser

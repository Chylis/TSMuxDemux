//
//  TSBitReader.h
//  TSMuxDemux
//
//  Stack-allocated bit/byte reader with automatic bounds checking.
//  All read operations set an error flag if bounds are exceeded.
//

#ifndef TSBitReader_h
#define TSBitReader_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Stack-allocated bit-stream reader with automatic bounds checking.
///
/// Supports both bit-level and byte-level operations. All operations that exceed
/// bounds set the `error` flag and return zero/nil. Once error is set, all
/// subsequent reads return zero/nil without modifying state.
///
/// Example usage:
/// ```
/// TSBitReader reader = TSBitReaderMake(data);
/// uint32_t flags = TSBitReaderReadBits(&reader, 3);      // Read 3 bits
/// uint32_t pid = TSBitReaderReadBits(&reader, 13);       // Read 13 bits
/// uint8_t counter = TSBitReaderReadBits(&reader, 4);     // Read 4 bits
/// if (reader.error) { /* handle error */ }
/// ```
typedef struct {
    const uint8_t * _Nullable bytes;    ///< Pointer to data buffer (not owned)
    NSUInteger length;                   ///< Total bytes in buffer
    NSUInteger byteOffset;               ///< Current byte position (0-based)
    uint8_t bitOffset;                   ///< Bits consumed in current byte (0-7, 0 = byte-aligned)
    BOOL error;                          ///< Set when read exceeds bounds
} TSBitReader;

#pragma mark - Initialization

/// Creates a reader from NSData.
/// @param data Source data. Reader does NOT retain - caller must ensure data outlives reader.
/// @return Initialized reader at position 0.
static inline TSBitReader TSBitReaderMake(NSData *data) {
    return (TSBitReader){
        .bytes = (const uint8_t *)data.bytes,
        .length = data.length,
        .byteOffset = 0,
        .bitOffset = 0,
        .error = NO
    };
}

/// Creates a reader from raw bytes.
/// @param bytes Pointer to byte buffer. Caller must ensure buffer outlives reader.
/// @param length Number of bytes in buffer.
/// @return Initialized reader at position 0.
static inline TSBitReader TSBitReaderMakeWithBytes(const uint8_t *bytes, NSUInteger length) {
    if (bytes == NULL && length > 0) {
        return (TSBitReader){
            .bytes = NULL,
            .length = 0,
            .byteOffset = 0,
            .bitOffset = 0,
            .error = YES
        };
    }
    return (TSBitReader){
        .bytes = bytes,
        .length = length,
        .byteOffset = 0,
        .bitOffset = 0,
        .error = NO
    };
}

#pragma mark - Bit-Level Operations

/// Reads up to 32 bits from the stream.
/// @param reader The bit reader.
/// @param numBits Number of bits to read (1-32).
/// @return The bits as a right-aligned uint32_t, or 0 if error.
/// @note Sets error flag if insufficient bits remain.
static inline uint32_t TSBitReaderReadBits(TSBitReader *reader, uint8_t numBits) {
    if (reader->error || numBits == 0 || numBits > 32) {
        reader->error = YES;
        return 0;
    }

    // Calculate total bits available
    NSUInteger totalBitsAvailable;
    if (reader->byteOffset >= reader->length) {
        totalBitsAvailable = 0;
    } else {
        totalBitsAvailable = (reader->length - reader->byteOffset) * 8 - reader->bitOffset;
    }

    if (totalBitsAvailable < numBits) {
        reader->error = YES;
        return 0;
    }

    uint32_t result = 0;
    uint8_t bitsRemaining = numBits;

    while (bitsRemaining > 0) {
        uint8_t bitsAvailableInByte = 8 - reader->bitOffset;
        uint8_t bitsToRead = (bitsRemaining < bitsAvailableInByte) ? bitsRemaining : bitsAvailableInByte;

        // Extract bits from current byte
        uint8_t shift = bitsAvailableInByte - bitsToRead;
        uint8_t mask = ((1 << bitsToRead) - 1) << shift;
        uint8_t bits = (reader->bytes[reader->byteOffset] & mask) >> shift;

        result = (result << bitsToRead) | bits;
        bitsRemaining -= bitsToRead;
        reader->bitOffset += bitsToRead;

        if (reader->bitOffset >= 8) {
            reader->byteOffset++;
            reader->bitOffset = 0;
        }
    }

    return result;
}

/// Skips the specified number of bits.
/// @param reader The bit reader.
/// @param numBits Number of bits to skip.
/// @note Sets error flag if insufficient bits remain.
static inline void TSBitReaderSkipBits(TSBitReader *reader, NSUInteger numBits) {
    if (reader->error) return;

    // Calculate total bits available
    NSUInteger totalBitsAvailable;
    if (reader->byteOffset >= reader->length) {
        totalBitsAvailable = 0;
    } else {
        totalBitsAvailable = (reader->length - reader->byteOffset) * 8 - reader->bitOffset;
    }

    if (totalBitsAvailable < numBits) {
        reader->error = YES;
        return;
    }

    // Add bits to skip to current position
    NSUInteger totalBitPos = reader->byteOffset * 8 + reader->bitOffset + numBits;
    reader->byteOffset = totalBitPos / 8;
    reader->bitOffset = totalBitPos % 8;
}

#pragma mark - Byte-Level Operations

/// Reads a single byte.
/// @param reader The bit reader. Must be byte-aligned.
/// @return The byte value, or 0 if error.
/// @note Sets error flag if not byte-aligned or insufficient bytes remain.
static inline uint8_t TSBitReaderReadUInt8(TSBitReader *reader) {
    if (reader->error || reader->bitOffset != 0) {
        reader->error = YES;
        return 0;
    }
    if (reader->byteOffset >= reader->length) {
        reader->error = YES;
        return 0;
    }
    return reader->bytes[reader->byteOffset++];
}

/// Reads a big-endian 16-bit unsigned integer.
/// @param reader The bit reader. Must be byte-aligned.
/// @return The value, or 0 if error.
/// @note Sets error flag if not byte-aligned or insufficient bytes remain.
static inline uint16_t TSBitReaderReadUInt16BE(TSBitReader *reader) {
    if (reader->error || reader->bitOffset != 0) {
        reader->error = YES;
        return 0;
    }
    if (reader->byteOffset + 2 > reader->length) {
        reader->error = YES;
        return 0;
    }
    uint16_t value = ((uint16_t)reader->bytes[reader->byteOffset] << 8) |
                      (uint16_t)reader->bytes[reader->byteOffset + 1];
    reader->byteOffset += 2;
    return value;
}

/// Reads a big-endian 32-bit unsigned integer.
/// @param reader The bit reader. Must be byte-aligned.
/// @return The value, or 0 if error.
/// @note Sets error flag if not byte-aligned or insufficient bytes remain.
static inline uint32_t TSBitReaderReadUInt32BE(TSBitReader *reader) {
    if (reader->error || reader->bitOffset != 0) {
        reader->error = YES;
        return 0;
    }
    if (reader->byteOffset + 4 > reader->length) {
        reader->error = YES;
        return 0;
    }
    uint32_t value = ((uint32_t)reader->bytes[reader->byteOffset] << 24) |
                     ((uint32_t)reader->bytes[reader->byteOffset + 1] << 16) |
                     ((uint32_t)reader->bytes[reader->byteOffset + 2] << 8) |
                      (uint32_t)reader->bytes[reader->byteOffset + 3];
    reader->byteOffset += 4;
    return value;
}

/// Reads bytes as NSData without copying.
/// @param reader The bit reader. Must be byte-aligned.
/// @param count Number of bytes to read.
/// @return NSData wrapping the bytes (not copied), or nil if error. Caller must copy if data needs to outlive the source buffer.
/// @note Sets error flag if not byte-aligned or insufficient bytes remain.
static inline NSData * _Nullable TSBitReaderReadData(TSBitReader *reader, NSUInteger count) {
    if (reader->error || reader->bitOffset != 0) {
        reader->error = YES;
        return nil;
    }
    if (reader->byteOffset + count > reader->length) {
        reader->error = YES;
        return nil;
    }
    NSData *data = [NSData dataWithBytesNoCopy:(void *)(reader->bytes + reader->byteOffset)
                                        length:count
                                  freeWhenDone:NO];
    reader->byteOffset += count;
    return data;
}

/// Skips the specified number of bytes.
/// @param reader The bit reader. Must be byte-aligned.
/// @param count Number of bytes to skip.
/// @note Sets error flag if not byte-aligned or insufficient bytes remain.
static inline void TSBitReaderSkip(TSBitReader *reader, NSUInteger count) {
    if (reader->error || reader->bitOffset != 0) {
        reader->error = YES;
        return;
    }
    if (reader->byteOffset + count > reader->length) {
        reader->error = YES;
        return;
    }
    reader->byteOffset += count;
}

#pragma mark - State Queries

/// Returns the number of bits remaining in the buffer.
static inline NSUInteger TSBitReaderRemainingBits(const TSBitReader *reader) {
    if (reader->byteOffset >= reader->length) return 0;
    return (reader->length - reader->byteOffset) * 8 - reader->bitOffset;
}

/// Returns the number of complete bytes remaining (ignores partial byte).
static inline NSUInteger TSBitReaderRemainingBytes(const TSBitReader *reader) {
    if (reader->byteOffset >= reader->length) return 0;
    if (reader->bitOffset != 0) {
        // Not aligned: remaining bytes start after current partial byte
        return (reader->byteOffset + 1 < reader->length) ? (reader->length - reader->byteOffset - 1) : 0;
    }
    return reader->length - reader->byteOffset;
}

/// Returns YES if the reader has at least the specified number of bits remaining.
static inline BOOL TSBitReaderHasBits(const TSBitReader *reader, NSUInteger count) {
    return TSBitReaderRemainingBits(reader) >= count;
}

#pragma mark - Sub-Reader

/// Creates a sub-reader for a specific byte length, advancing the parent reader.
/// @param reader The parent reader. Must be byte-aligned.
/// @param length Number of bytes for the sub-reader.
/// @return A new reader covering the specified range, or an errored reader if bounds exceeded.
/// @note Sets parent's error flag if not byte-aligned or insufficient bytes remain.
static inline TSBitReader TSBitReaderSubReader(TSBitReader *reader, NSUInteger length) {
    if (reader->error || reader->bitOffset != 0 || reader->byteOffset + length > reader->length) {
        reader->error = YES;
        return (TSBitReader){ .bytes = NULL, .length = 0, .byteOffset = 0, .bitOffset = 0, .error = YES };
    }
    TSBitReader sub = {
        .bytes = reader->bytes + reader->byteOffset,
        .length = length,
        .byteOffset = 0,
        .bitOffset = 0,
        .error = NO
    };
    reader->byteOffset += length;
    return sub;
}

NS_ASSUME_NONNULL_END

#endif /* TSBitReader_h */

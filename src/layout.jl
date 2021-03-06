"""
    child_size(::Type{T}, args...) where {T}

The number of bytes needed to allocate children of `T`, not including `self_size(T)`.

Defaults to 0.
"""
child_size(::Type{T}) where T = 0

"""
    init(blob::Blob{T}, args...) where T

Initialize `blob`.

Assumes that `blob` it at least `self_size(T) + child_size(T, args...)` bytes long.
"""
function init(blob::Blob{T}, args...) where T
    init(blob, Blob{Void}(blob + self_size(T)), args...)
end

"""
    init(blob::Blob{T}, free::Blob{Void}, args...)::Blob{Void} where T

Initialize `blob`, where `free` is the beginning of the remaining free space. Must return `free + child_size(T, args...)`.

The default implementation where `child_size(T) == 0` does nothing. Override this method to add custom initializers for your types.
"""
function init(blob::Blob{T}, free::Blob{Void}) where T
    @assert child_size(T) == 0 "Default init cannot be used for types for which child_size(T) != 0"
    # TODO should we zero memory?
    free
end

child_size(::Type{Blob{T}}, args...) where T = self_size(T) + child_size(T, args...)

function init(blob::Blob{Blob{T}}, free::Blob{Void}, args...) where T
    nested_blob = Blob{T}(free)
    @blob blob[] = nested_blob
    init(nested_blob, free + self_size(T), args...)
end

child_size(::Type{BlobVector{T}}, length::Int64) where {T} = self_size(T) * length

function init(blob::Blob{BlobVector{T}}, free::Blob{Void}, length::Int64) where T
    @blob blob.data[] = Blob{T}(free)
    @blob blob.length[] = length
    free + child_size(BlobVector{T}, length)
end

child_size(::Type{BlobBitVector}, length::Int64) = self_size(UInt64) * Int64(ceil(length / 64))

function init(blob::Blob{BlobBitVector}, free::Blob{Void}, length::Int64)
    @blob blob.data[] = Blob{UInt64}(free)
    @blob blob.length[] = length
    free + child_size(BlobBitVector, length)
end

child_size(::Type{BlobString}, length::Int64) = length

function init(blob::Blob{BlobString}, free::Blob{Void}, length::Int64)
    @blob blob.data[] = Blob{UInt8}(free)
    @blob blob.len[] = length
    free + child_size(BlobString, length)
end

child_size(::Type{BlobString}, string::Union{String, BlobString}) = sizeof(string)

function init(blob::Blob{BlobString}, free::Blob{Void}, string::Union{String, BlobString})
    free = init(blob, free, sizeof(string))
    unsafe_copy!((@blob blob[]), string)
    free
end

"""
    malloc(::Type{T}, args...)::Blob{T} where T

Allocate an uninitialized `Blob{T}`.
"""
function malloc(::Type{T}, args...)::Blob{T} where T
    size = self_size(T) + child_size(T, args...)
    Blob{T}(Libc.malloc(size), 0, size)
end

"""
    malloc_and_init(::Type{T}, args...)::Blob{T} where T

Allocate and initialize a new `Blob{T}`.
"""
function malloc_and_init(::Type{T}, args...)::Blob{T} where T
    size = self_size(T) + child_size(T, args...)
    blob = Blob{T}(Libc.malloc(size), 0, size)
    used = init(blob, args...)
    @assert used - blob == size
    blob
end

"""
    free(blob::Blob)

Free the underlying allocation for `blob`.
"""
function free(blob::Blob)
    Libc.free(getfield(blob, :base))
end

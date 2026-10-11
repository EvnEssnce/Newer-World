class_name NetCodec
extends RefCounted
## Compact binary encoding for snapshots (World._broadcast_snapshot). Godot's own
## Variant encoding spends 4 bytes on every value's type and pads everything to
## 4 bytes (a bool or a 0 costs 8); this one spends 1 byte on the type and packs
## small numbers. Lossless: decode(encode(v)) == v with the same types, so
## reconciliation compares exactly what the server had. Pure, unit tested
## (tests/test_net_codec.gd).
##
## Supported: null, bool, int, float, String, Vector2, Vector3, Array (of
## these), PackedInt32Array, PackedStringArray. Anything else is an error and
## encodes as null.
##
## Each value starts with one tag byte:
## - 0x80-0xFF: an int from -64 to 63 in the tag itself (tag - 0xC0).
## - INT: a zigzag varint (small magnitudes take few bytes, either sign).
## - FLOAT_WHOLE: a float with no fraction (0.0, 100.0), as a zigzag varint.
##   FLOAT32 if a 32-bit float holds it exactly, else FLOAT64.
## - Vectors are 32-bit floats (what Godot stores), with a 1-byte zero form.
## - Counts and string lengths are varints. INT32_FILL is a packed int array
##   whose elements are all the same (no cooldowns running, empty slots).
## Ints must be within MAX_INT (2^62).

const TAG_NULL := 0x00
const TAG_FALSE := 0x01
const TAG_TRUE := 0x02
const TAG_INT := 0x03
const TAG_FLOAT_WHOLE := 0x04
const TAG_FLOAT32 := 0x05
const TAG_FLOAT64 := 0x06
const TAG_STRING := 0x07
const TAG_VECTOR2 := 0x08
const TAG_VECTOR2_ZERO := 0x09
const TAG_VECTOR3 := 0x0A
const TAG_VECTOR3_ZERO := 0x0B
const TAG_ARRAY := 0x0C
const TAG_INT32_ARRAY := 0x0D
const TAG_INT32_FILL := 0x0E
const TAG_STRING_ARRAY := 0x0F

## Ints from SMALL_INT_MIN to SMALL_INT_MAX fit in the tag byte.
const SMALL_INT_TAG := 0x80
const SMALL_INT_MIN := -64
const SMALL_INT_MAX := 63
## Whole floats up to this magnitude use FLOAT_WHOLE (all exact in a double).
const MAX_WHOLE_FLOAT := 9007199254740992.0  # 2^53
## Largest int magnitude (2^62 - 1): zigzagged, it still fits a non-negative int.
const MAX_INT := 4611686018427387903
## Largest INT32_FILL count (it takes 1 byte whatever the count, so bad data
## could otherwise ask for a huge array).
const MAX_FILL := 4096


static func encode(value: Variant) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	write(buffer, value)
	return buffer.data_array


## The decoded value, or null if the bytes are malformed (cut short, an
## unknown tag, bytes left over). Quiet: the caller reports it.
static func decode(bytes: PackedByteArray) -> Variant:
	var reader := _Reader.new()
	reader.buffer.data_array = bytes
	var value: Variant = _read(reader)
	if not reader.ok or reader.buffer.get_available_bytes() != 0:
		return null
	return value


## Writes an array's header; follow it with exactly `count` values (write() or
## put_data() of already encoded ones). Lets a snapshot reuse each player's
## encoded entry for every recipient.
static func write_array_header(buffer: StreamPeerBuffer, count: int) -> void:
	buffer.put_u8(TAG_ARRAY)
	_put_varint(buffer, count)


static func write(buffer: StreamPeerBuffer, value: Variant) -> void:
	match typeof(value):
		TYPE_NIL:
			buffer.put_u8(TAG_NULL)
		TYPE_BOOL:
			buffer.put_u8(TAG_TRUE if value else TAG_FALSE)
		TYPE_INT:
			_write_int(buffer, value)
		TYPE_FLOAT:
			_write_float(buffer, value)
		TYPE_STRING:
			buffer.put_u8(TAG_STRING)
			_put_string(buffer, value)
		TYPE_VECTOR2:
			var v: Vector2 = value
			if v == Vector2.ZERO and not _has_negative_zero([v.x, v.y]):
				buffer.put_u8(TAG_VECTOR2_ZERO)
			else:
				buffer.put_u8(TAG_VECTOR2)
				buffer.put_float(v.x)
				buffer.put_float(v.y)
		TYPE_VECTOR3:
			var v: Vector3 = value
			if v == Vector3.ZERO and not _has_negative_zero([v.x, v.y, v.z]):
				buffer.put_u8(TAG_VECTOR3_ZERO)
			else:
				buffer.put_u8(TAG_VECTOR3)
				buffer.put_float(v.x)
				buffer.put_float(v.y)
				buffer.put_float(v.z)
		TYPE_ARRAY:
			var array: Array = value
			write_array_header(buffer, array.size())
			for item: Variant in array:
				write(buffer, item)
		TYPE_PACKED_INT32_ARRAY:
			_write_int32_array(buffer, value)
		TYPE_PACKED_STRING_ARRAY:
			var strings: PackedStringArray = value
			buffer.put_u8(TAG_STRING_ARRAY)
			_put_varint(buffer, strings.size())
			for s in strings:
				_put_string(buffer, s)
		_:
			push_error("NetCodec: can't encode a %s" % type_string(typeof(value)))
			buffer.put_u8(TAG_NULL)


## Reading state: the bytes, and whether they made sense so far. After the
## first problem, reads return null/0 without touching the buffer.
class _Reader:
	var buffer := StreamPeerBuffer.new()
	var ok := true

	## True if `count` more bytes are there; else marks the data bad.
	func has(count: int) -> bool:
		if ok and buffer.get_available_bytes() < count:
			ok = false
		return ok

	func u8() -> int:
		return buffer.get_u8() if has(1) else 0

	func f32() -> float:
		return buffer.get_float() if has(4) else 0.0

	func f64() -> float:
		return buffer.get_double() if has(8) else 0.0

	## 7 bits per byte, low first (see NetCodec._put_varint).
	func varint() -> int:
		var value := 0
		# 9 bytes hold 63 bits, all a non-negative int has.
		for shift in range(0, 63, 7):
			var b := u8()
			value |= (b & 0x7F) << shift
			if value < 0:
				break  # past 63 bits
			if b & 0x80 == 0:
				return value
		ok = false
		return 0

	func zigzag() -> int:
		return NetCodec._unzigzag(varint())

	## A count of things that take at least a byte each, so bad data can't
	## make it allocate a huge array.
	func count() -> int:
		var n := varint()
		if not has(n):
			return 0
		return n

	func string() -> String:
		var size := count()
		return buffer.get_utf8_string(size) if size > 0 else ""


static func _read(r: _Reader) -> Variant:
	var tag := r.u8()
	if not r.ok:
		return null
	if tag >= SMALL_INT_TAG:
		return tag - SMALL_INT_TAG + SMALL_INT_MIN
	match tag:
		TAG_NULL:
			return null
		TAG_FALSE:
			return false
		TAG_TRUE:
			return true
		TAG_INT:
			return r.zigzag()
		TAG_FLOAT_WHOLE:
			return float(r.zigzag())
		TAG_FLOAT32:
			return r.f32()
		TAG_FLOAT64:
			return r.f64()
		TAG_STRING:
			return r.string()
		TAG_VECTOR2:
			var x := r.f32()
			return Vector2(x, r.f32())
		TAG_VECTOR2_ZERO:
			return Vector2.ZERO
		TAG_VECTOR3:
			var x := r.f32()
			var y := r.f32()
			return Vector3(x, y, r.f32())
		TAG_VECTOR3_ZERO:
			return Vector3.ZERO
		TAG_ARRAY:
			var count := r.count()
			var array := []
			array.resize(count)
			for i in count:
				array[i] = _read(r)
			return array
		TAG_INT32_ARRAY:
			var count := r.count()
			var ints := PackedInt32Array()
			ints.resize(count)
			for i in count:
				ints[i] = r.zigzag()
			return ints
		TAG_INT32_FILL:
			var count := r.varint()
			if count > MAX_FILL:
				r.ok = false
				return null
			var ints := PackedInt32Array()
			ints.resize(count)
			ints.fill(r.zigzag())
			return ints
		TAG_STRING_ARRAY:
			var count := r.count()
			var strings := PackedStringArray()
			strings.resize(count)
			for i in count:
				strings[i] = r.string()
			return strings
	r.ok = false
	return null


static func _write_int(buffer: StreamPeerBuffer, value: int) -> void:
	if value >= SMALL_INT_MIN and value <= SMALL_INT_MAX:
		buffer.put_u8(SMALL_INT_TAG + value - SMALL_INT_MIN)
		return
	buffer.put_u8(TAG_INT)
	_put_varint(buffer, _zigzag(value))


static func _write_float(buffer: StreamPeerBuffer, value: float) -> void:
	if (value == floorf(value) and absf(value) <= MAX_WHOLE_FLOAT
			and not _has_negative_zero([value])):
		buffer.put_u8(TAG_FLOAT_WHOLE)
		_put_varint(buffer, _zigzag(int(value)))
	elif PackedFloat32Array([value])[0] == value:
		buffer.put_u8(TAG_FLOAT32)
		buffer.put_float(value)
	else:
		# Also NaN (never equal to itself).
		buffer.put_u8(TAG_FLOAT64)
		buffer.put_double(value)


static func _write_int32_array(buffer: StreamPeerBuffer, ints: PackedInt32Array) -> void:
	var same := ints.size() > 1
	for i in range(1, ints.size()):
		if ints[i] != ints[0]:
			same = false
			break
	buffer.put_u8(TAG_INT32_FILL if same else TAG_INT32_ARRAY)
	_put_varint(buffer, ints.size())
	if same:
		_put_varint(buffer, _zigzag(ints[0]))
		return
	for n in ints:
		_put_varint(buffer, _zigzag(n))


## -0.0 == 0.0, but it isn't the same float (atan2 and 1/x tell them apart), so
## it skips the forms that would turn it into 0.0.
static func _has_negative_zero(values: Array) -> bool:
	for v: float in values:
		if v == 0.0 and PackedFloat64Array([v]).to_byte_array()[7] & 0x80:
			return true
	return false


## Small magnitudes of either sign become small non-negative numbers:
## 0, -1, 1, -2, 2... -> 0, 1, 2, 3, 4... Written without shifts: Godot refuses
## to shift negative ints. Ints must be within MAX_INT.
static func _zigzag(n: int) -> int:
	if absi(n) > MAX_INT:
		push_error("NetCodec: int %d is out of range" % n)
		n = clampi(n, -MAX_INT, MAX_INT)
	return n * 2 if n >= 0 else -n * 2 - 1


static func _unzigzag(z: int) -> int:
	return z >> 1 if z & 1 == 0 else -(z >> 1) - 1


## 7 bits per byte, low first; the high bit says another byte follows.
## `value` >= 0.
static func _put_varint(buffer: StreamPeerBuffer, value: int) -> void:
	while value >= 0x80:
		buffer.put_u8((value & 0x7F) | 0x80)
		value >>= 7
	buffer.put_u8(value)


static func _put_string(buffer: StreamPeerBuffer, s: String) -> void:
	var utf8 := s.to_utf8_buffer()
	_put_varint(buffer, utf8.size())
	buffer.put_data(utf8)

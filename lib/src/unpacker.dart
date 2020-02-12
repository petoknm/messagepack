import 'dart:convert';
import 'dart:typed_data';

/// Streaming unpaker
///
/// unpackXXX methods returns value if it exist, or `null`.
/// Throws [FormatException] if value is not an requested type,
/// but in that case throwing exception not corrupt internal state,
/// so other unpackXXX methods can be called after that.
///
/// Note: In source code `_offset += 3;` with odd values (3) means,
/// that 1 byte read for header and 2 bytes read for data itself.
class Unpacker {
  Unpacker(this._list) : _d = ByteData.view(_list.buffer, _list.offsetInBytes);

  final Uint8List _list;
  final ByteData _d;
  int _offset = 0;

  final _strCodec = const Utf8Codec();

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Throws [FormatException] if value is not a bool,
  bool unpackBool() {
    final b = _d.getUint8(_offset);
    bool v;
    if (b == 0xc2) {
      v = false;
      _offset += 1;
    } else if (b == 0xc3) {
      v = true;
      _offset += 1;
    } else if (b == 0xc0) {
      v = null;
      _offset += 1;
    } else {
      throw _formatException('bool', b);
    }
    return v;
  }

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Throws [FormatException] if value is not an integer,
  int unpackInt() {
    final b = _d.getUint8(_offset);
    int v;
    if (b <= 0x7f || b >= 0xe0) {
      /// Int value in fixnum range [-32..127] encoded in header 1 byte
      v = _d.getInt8(_offset);
      _offset += 1;
    } else if (b == 0xcc) {
      v = _d.getUint8(++_offset);
      _offset += 1;
    } else if (b == 0xcd) {
      v = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == 0xce) {
      v = _d.getUint32(++_offset);
      _offset += 4;
    } else if (b == 0xcf) {
      v = _d.getUint64(++_offset);
      _offset += 8;
    } else if (b == 0xd0) {
      v = _d.getInt8(++_offset);
      _offset += 1;
    } else if (b == 0xd1) {
      v = _d.getInt16(++_offset);
      _offset += 2;
    } else if (b == 0xd2) {
      v = _d.getInt32(++_offset);
      _offset += 4;
    } else if (b == 0xd3) {
      v = _d.getInt64(++_offset);
      _offset += 8;
    } else if (b == 0xc0) {
      v = null;
      _offset += 1;
    } else {
      throw _formatException('integer', b);
    }
    return v;
  }

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Throws [FormatException] if value is not a Double.
  double unpackDouble() {
    final b = _d.getUint8(_offset);
    double v;
    if (b == 0xcb) {
      v = _d.getFloat64(++_offset);
      _offset += 8;
    } else if (b == 0xc0) {
      v = null;
      _offset += 1;
    } else {
      throw _formatException('double', b);
    }
    return v;
  }

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Empty
  /// Throws [FormatException] if value is not a String.
  String unpackString() {
    final b = _d.getUint8(_offset);
    if (b == 0xc0) {
      _offset += 1;
      return null;
    }
    int len;

    /// fixstr 101XXXXX stores a byte array whose len is upto 31 bytes:
    if (b & 0xE0 == 0xA0) {
      len = b & 0x1F;
      _offset += 1;
    } else if (b == 0xc0) {
      _offset += 1;
      return null;
    } else if (b == 0xd9) {
      len = _d.getUint8(++_offset);
      _offset += 1;
    } else if (b == 0xda) {
      len = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == 0xdb) {
      len = _d.getUint32(++_offset);
      _offset += 4;
    } else {
      throw _formatException('String', b);
    }
    final data =
        Uint8List.view(_list.buffer, _list.offsetInBytes + _offset, len);
    _offset += len;
    return _strCodec.decode(data);
  }

  /// Unpack [Iterable.length] if packed value is an [Iterable] or `null`.
  ///
  /// Encoded in MsgPack packet null or 0 length unpacks to 0 for convenience.
  /// Items of the [Iterable] must be unpacked manually with respect to returned `length`
  /// Throws [FormatException] if value is not an [Iterable].
  int unpackIterableLength() {
    final b = _d.getUint8(_offset);
    int len;
    if (b & 0xF0 == 0x90) {
      /// fixarray 1001XXXX stores an array whose length is upto 15 elements:
      len = b & 0xF;
      _offset += 1;
    } else if (b == 0xc0) {
      len = 0;
      _offset += 1;
    } else if (b == 0xdc) {
      len = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == 0xdd) {
      len = _d.getUint32(++_offset);
      _offset += 4;
    } else {
      throw _formatException('Iterable length', b);
    }
    return len;
  }

  /// Unpack [Map.length] if packed value is an [Map] or `null`.
  ///
  /// Encoded in MsgPack packet null or 0 length unpacks to 0 for convenience.
  /// Items of the [Map] must be unpacked manually with respect to returned `length`
  /// Throws [FormatException] if value is not an [Map].
  int unpackMapLength() {
    final b = _d.getUint8(_offset);
    int len;
    if (b & 0xF0 == 0x80) {
      /// fixmap 1000XXXX stores a map whose length is upto 15 elements
      len = b & 0xF;
      _offset += 1;
    } else if (b == 0xc0) {
      len = 0;
      _offset += 1;
    } else if (b == 0xde) {
      len = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == 0xdf) {
      len = _d.getUint32(++_offset);
      _offset += 4;
    } else {
      throw _formatException('Map length', b);
    }
    return len;
  }

  /// Unpack value if packed value is binary or `null`.
  ///
  /// Encoded in MsgPack packet null unpacks to [List] with 0 length for convenience.
  /// Throws [FormatException] if value is not a binary.
  List<int> unpackBinary() {
    final b = _d.getUint8(_offset);
    int len;
    if (b == 0xc4) {
      len = _d.getUint8(++_offset);
      _offset += 1;
    } else if (b == 0xc0) {
      len = 0;
      _offset += 1;
    } else if (b == 0xc5) {
      len = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == 0xc6) {
      len = _d.getUint32(++_offset);
      _offset += 4;
    } else {
      throw _formatException('Binary', b);
    }
    final data =
        Uint8List.view(_list.buffer, _list.offsetInBytes + _offset, len);
    _offset += len;
    return data.toList();
  }

  Exception _formatException(String type, int b) => FormatException(
      'Try to unpack $type value, but it\'s not an $type, byte = $b');
}
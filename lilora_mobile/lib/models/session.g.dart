// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SessionAdapter extends TypeAdapter<Session> {
  @override
  final int typeId = 1;

  @override
  Session read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Session(
      id: fields[0] as String,
      name: fields[1] as String,
      startTime: fields[2] as DateTime,
      endTime: fields[3] as DateTime?,
      deviceEui: fields[4] as String?,
      notes: fields[5] as String?,
      pointCount: fields[6] as int,
      maxDistance: fields[7] as double?,
      minRssi: fields[8] as double?,
      maxRssi: fields[9] as double?,
      avgRssi: fields[10] as double?,
      minSnr: fields[11] as double?,
      maxSnr: fields[12] as double?,
      avgSnr: fields[13] as double?,
    )
      .._rssiSum = fields[14] as double
      .._snrSum = fields[15] as double;
  }

  @override
  void write(BinaryWriter writer, Session obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.startTime)
      ..writeByte(3)
      ..write(obj.endTime)
      ..writeByte(4)
      ..write(obj.deviceEui)
      ..writeByte(5)
      ..write(obj.notes)
      ..writeByte(6)
      ..write(obj.pointCount)
      ..writeByte(7)
      ..write(obj.maxDistance)
      ..writeByte(8)
      ..write(obj.minRssi)
      ..writeByte(9)
      ..write(obj.maxRssi)
      ..writeByte(10)
      ..write(obj.avgRssi)
      ..writeByte(11)
      ..write(obj.minSnr)
      ..writeByte(12)
      ..write(obj.maxSnr)
      ..writeByte(13)
      ..write(obj.avgSnr)
      ..writeByte(14)
      ..write(obj._rssiSum)
      ..writeByte(15)
      ..write(obj._snrSum);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

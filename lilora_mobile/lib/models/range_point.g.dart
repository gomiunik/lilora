// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'range_point.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RangePointAdapter extends TypeAdapter<RangePoint> {
  @override
  final int typeId = 0;

  @override
  RangePoint read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RangePoint(
      timestamp: fields[0] as DateTime,
      deviceEui: fields[1] as String,
      frameCount: fields[2] as int,
      latitude: fields[3] as double,
      longitude: fields[4] as double,
      altitude: fields[5] as int,
      fixQuality: fields[6] as int,
      hdop: fields[7] as double,
      satellites: fields[8] as int,
      rssi: fields[9] as double,
      snr: fields[10] as double,
      spreadingFactor: fields[11] as int,
      frequency: fields[12] as double,
      gatewayId: fields[13] as String?,
      gatewayLat: fields[14] as double?,
      gatewayLon: fields[15] as double?,
      distance: fields[16] as double?,
      sessionId: fields[17] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, RangePoint obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.timestamp)
      ..writeByte(1)
      ..write(obj.deviceEui)
      ..writeByte(2)
      ..write(obj.frameCount)
      ..writeByte(3)
      ..write(obj.latitude)
      ..writeByte(4)
      ..write(obj.longitude)
      ..writeByte(5)
      ..write(obj.altitude)
      ..writeByte(6)
      ..write(obj.fixQuality)
      ..writeByte(7)
      ..write(obj.hdop)
      ..writeByte(8)
      ..write(obj.satellites)
      ..writeByte(9)
      ..write(obj.rssi)
      ..writeByte(10)
      ..write(obj.snr)
      ..writeByte(11)
      ..write(obj.spreadingFactor)
      ..writeByte(12)
      ..write(obj.frequency)
      ..writeByte(13)
      ..write(obj.gatewayId)
      ..writeByte(14)
      ..write(obj.gatewayLat)
      ..writeByte(15)
      ..write(obj.gatewayLon)
      ..writeByte(16)
      ..write(obj.distance)
      ..writeByte(17)
      ..write(obj.sessionId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RangePointAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

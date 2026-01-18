// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sent_transmission.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SentTransmissionAdapter extends TypeAdapter<SentTransmission> {
  @override
  final int typeId = 3;

  @override
  SentTransmission read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SentTransmission(
      frameCount: fields[0] as int,
      latitude: fields[1] as double,
      longitude: fields[2] as double,
      hasValidGps: fields[3] as bool,
      sentTime: fields[4] as DateTime,
      received: fields[5] as bool,
      sessionId: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SentTransmission obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.frameCount)
      ..writeByte(1)
      ..write(obj.latitude)
      ..writeByte(2)
      ..write(obj.longitude)
      ..writeByte(3)
      ..write(obj.hasValidGps)
      ..writeByte(4)
      ..write(obj.sentTime)
      ..writeByte(5)
      ..write(obj.received)
      ..writeByte(6)
      ..write(obj.sessionId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SentTransmissionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
